package com.hicar.ora.limited

import android.app.Application
import android.content.Context
import android.provider.Settings
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/** Framework-backed prefs/session tests, not a physical boot/codec test. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [29, 35], manifest = Config.NONE, application = Application::class)
class BootSessionTest {
    private lateinit var app: Context
    @Before fun setup() {
        app = RuntimeEnvironment.getApplication()
        app.createDeviceProtectedStorageContext()
            .getSharedPreferences("HiCarBootSession", Context.MODE_PRIVATE).edit().clear().commit()
        Settings.Global.putInt(app.contentResolver, Settings.Global.BOOT_COUNT, 10)
    }

    @Test fun duplicateBootBroadcastDoesNotMakeANewSession() {
        val first = BootSessionManager.incrementSessionOnBoot(app)
        assertEquals(first, BootSessionManager.incrementSessionOnBoot(app))
    }

    @Test fun nextDayBootMustPlayEvenWhenYesterdayCompleted() {
        val first = BootSessionManager.incrementSessionOnBoot(app)
        BootSessionManager.markSessionCompleted(app, first)
        Settings.Global.putInt(app.contentResolver, Settings.Global.BOOT_COUNT, 11)
        val next = BootSessionManager.incrementSessionOnBoot(app)
        assertTrue(next > first)
        assertFalse(BootSessionManager.isSessionCompleted(app, next))
        assertFalse(BootSessionManager.isSessionFailed(app, next))
    }

    @Test fun startedMarkerCannotMeanCompletedAfterProcessDeath() {
        val session = BootSessionManager.incrementSessionOnBoot(app)
        BootSessionManager.markPlaybackStarted(app, session)
        BootSessionManager.savePlaybackPosition(app, session, 5000)
        assertFalse(BootSessionManager.isSessionCompleted(app, session))
        assertFalse(BootSessionManager.shouldSuppressBootWarnings(app))
        BootSessionManager.clearPlaybackStarted(app, session)
        assertEquals(5000, BootSessionManager.playbackPosition(app, session))
        assertFalse(BootSessionManager.hasPlaybackStarted(app, session))
    }

    @Test fun decoderFailureOnlyBlocksItsOwnBootSession() {
        val first = BootSessionManager.incrementSessionOnBoot(app)
        BootSessionManager.markSessionFailed(app, first)
        assertTrue(BootSessionManager.isSessionFailed(app, first))
        Settings.Global.putInt(app.contentResolver, Settings.Global.BOOT_COUNT, 11)
        val next = BootSessionManager.incrementSessionOnBoot(app)
        assertFalse(BootSessionManager.isSessionFailed(app, next))
        assertEquals(0, BootSessionManager.playbackPosition(app, next))
    }

    @Test fun longWaitCannotEvictErrorEvidenceFromFullReport() {
        HiCarDiagnosticLog.init(app)
        HiCarDiagnosticLog.clear()
        HiCarDiagnosticLog.d("HiCarAudio", "routine")
        assertFalse(HiCarDiagnosticLog.hasErrorLines(app))
        HiCarDiagnosticLog.e("HiCarAudio", "job=overnight mode=android_screen_mode state=failed what=100 extra=2")
        repeat(1100) { HiCarDiagnosticLog.d("HiCarAudio", "readiness checkpoint $it") }
        assertTrue(HiCarDiagnosticLog.getFullLog().contains("what=100 extra=2"))
        assertTrue(HiCarDiagnosticLog.hasErrorLines(app))
        HiCarDiagnosticLog.flush()
    }
}
