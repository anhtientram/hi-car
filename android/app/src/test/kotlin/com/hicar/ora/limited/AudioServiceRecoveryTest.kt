package com.hicar.ora.limited

import android.app.Application
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Looper
import android.provider.Settings
import java.io.File
import java.time.Duration
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.android.controller.ServiceController
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowMediaPlayer
import org.robolectric.shadows.util.DataSource

/** Drives the real service callbacks with a deterministic media/focus backend (no physical audio). */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [24, 29, 35], manifest = Config.NONE, application = Application::class)
class AudioServiceRecoveryTest {
    private lateinit var controller: ServiceController<AudioForegroundService>
    private lateinit var service: AudioForegroundService
    private lateinit var path: String
    private lateinit var audioManager: AudioManager
    private val players = mutableListOf<MediaPlayer>()

    @Before fun setup() {
        val app = RuntimeEnvironment.getApplication()
        val file = File(app.filesDir, "service-test.mp3")
        file.writeBytes(ByteArray(256) { 1 }.also { it[0] = 73; it[1] = 68; it[2] = 51 })
        path = file.absolutePath
        for (storage in listOf(app, app.createDeviceProtectedStorageContext())) {
            storage.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit().clear()
                .putString("flutter.connection_mode", "android_screen_mode")
                .putString("flutter.auth_token", "test")
                .putString("flutter.greeting_audio_path", path)
                .putBoolean("flutter.auto_play_enabled", true).commit()
        }
        ShadowMediaPlayer.addMediaInfo(DataSource.toDataSource(path), ShadowMediaPlayer.MediaInfo(300_000, 1))
        ShadowMediaPlayer.setCreateListener { player, _ -> players.add(player) }
        audioManager = app.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        shadowOf(audioManager).setNextFocusRequestResponse(AudioManager.AUDIOFOCUS_REQUEST_GRANTED)
        controller = Robolectric.buildService(AudioForegroundService::class.java).create()
        service = controller.get()
    }

    @After fun cleanup() { controller.destroy(); shadowOf(Looper.getMainLooper()).idle() }
    private fun action(action: String, automatic: Boolean = false) {
        service.onStartCommand(Intent(service, AudioForegroundService::class.java).apply {
            this.action = action; putExtra("audioPath", path)
            putExtra("automatic", automatic)
            putExtra(AudioForegroundService.EXTRA_BOOT_SESSION_ID, BootSessionManager.getCurrentSession(service))
        }, 0, 1)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(10))
    }
    private fun state() = service.playbackStatus()["state"]

    @Test fun reportedServerDeathCreatesFreshPlayerAndIgnoresOldCompletion() {
        action(AudioForegroundService.ACTION_PLAY_GREETING)
        assertEquals("playing", state())
        val old = players.single()
        val oldCompletion = shadowOf(old).onCompletionListener
        shadowOf(old).invokeErrorListener(100, 2)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals("retrying", state())
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(3))
        assertEquals(2, players.size)
        assertEquals("playing", state())
        oldCompletion.onCompletion(old)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals("playing", state())
    }

    @Test fun brokenPipeExhaustionIsFailureNotCompletion() {
        action(AudioForegroundService.ACTION_PLAY_GREETING)
        for (delay in listOf(3L, 8L)) {
            shadowOf(players.last()).invokeErrorListener(1, -32)
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(delay))
            assertEquals("playing", state())
        }
        shadowOf(players.last()).invokeErrorListener(1, -32)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals("failed", state())
        assertEquals(3, players.size)
        assertTrue(HiCarDiagnosticLog.getFullLog().contains("PLAYBACK_FAILED"))
    }

    @Test fun focusWaitPast90SecondsNeverCompletesOrRebuildsPlayer() {
        action(AudioForegroundService.ACTION_PLAY_GREETING)
        val focus = shadowOf(audioManager).lastAudioFocusRequest.listener
        shadowOf(audioManager).setNextFocusRequestResponse(AudioManager.AUDIOFOCUS_REQUEST_FAILED)
        focus.onAudioFocusChange(AudioManager.AUDIOFOCUS_LOSS_TRANSIENT)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(120))
        assertEquals("waiting_focus", state())
        assertEquals(1, players.size)
        shadowOf(audioManager).setNextFocusRequestResponse(AudioManager.AUDIOFOCUS_REQUEST_GRANTED)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(3))
        assertEquals("playing", state())
        assertEquals(1, players.size)
    }

    @Test fun stopDuringRetryPreventsAnyLaterPlayer() {
        action(AudioForegroundService.ACTION_PLAY_GREETING)
        shadowOf(players.single()).invokeErrorListener(100, 2)
        shadowOf(Looper.getMainLooper()).idle()
        action(AudioForegroundService.ACTION_STOP_AUDIO)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(20))
        assertEquals("cancelled", state())
        assertEquals(1, players.size)
    }

    private fun mode(value: String) {
        val app = RuntimeEnvironment.getApplication()
        for (storage in listOf(app, app.createDeviceProtectedStorageContext())) {
            storage.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit()
                .putString("flutter.connection_mode", value)
                .putString("flutter.target_device_address", "AA:BB:CC:DD:EE:FF").commit()
        }
        service.refreshConfiguration()
    }

    @Test fun bluetoothAndAndroidAutoWithoutConfirmedRouteNeverStartOnPhoneSpeaker() {
        for (mode in listOf("phone_bluetooth", "phone_android_auto")) {
            mode(mode)
            action(AudioForegroundService.ACTION_PLAY_GREETING, automatic = true)
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(120))
            assertEquals("waiting_route", state())
            assertTrue(players.isEmpty())
        }
    }

    @Test fun boxServiceRestartResumesStartedButNotCompletedSessionOnly() {
        mode("android_box_mode")
        Settings.Global.putInt(service.contentResolver, Settings.Global.BOOT_COUNT, 10)
        val boot = BootSessionManager.incrementSessionOnBoot(service)
        action(AudioForegroundService.ACTION_BOOT_RETRY_GREETING)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(3))
        assertEquals("playing", state())
        assertTrue(BootSessionManager.hasPlaybackStarted(service, boot))
        controller.destroy()
        assertFalse(BootSessionManager.isSessionFailed(service, boot))
        assertFalse(BootSessionManager.isSessionCompleted(service, boot))
        controller = Robolectric.buildService(AudioForegroundService::class.java).create()
        service = controller.get()
        service.onStartCommand(null, 0, 2)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(3))
        assertEquals(2, players.size)
        assertEquals("playing", state())
        shadowOf(players.last()).invokeCompletionListener()
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(BootSessionManager.isSessionCompleted(service, boot))
        action(AudioForegroundService.ACTION_BOOT_RETRY_GREETING)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(3))
        assertEquals(2, players.size)
    }
}
