package com.hicar.ora.limited

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build

/**
 * Boot session tracking persisted in device-protected storage.
 * Survives process lifetime so a long-lived FGS does not block the next real boot.
 */
object BootSessionManager {

    private const val PREFS_NAME = "HiCarBootSession"
    private const val KEY_SESSION = "boot_session_id"
    private const val KEY_COMPLETED = "last_completed_boot_session_id"
    private const val KEY_MISS_REPORTED = "boot_miss_reported_session_id"
    private const val KEY_PLAYBACK_STARTED = "boot_playback_started_session_id"
    private const val KEY_LAST_INCREMENT_MS = "last_boot_increment_at_ms"
    private const val BOOT_INCREMENT_DEBOUNCE_MS = 60_000L

    const val BOOT_RETRY_ALARM_REQUEST_BASE = 100
    const val BOOT_RETRY_ALARM_COUNT = 3

    private fun prefs(context: Context): SharedPreferences {
        val app = context.applicationContext
        val storage = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            app.createDeviceProtectedStorageContext()
        } else {
            app
        }
        return storage.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun incrementSessionOnBoot(context: Context): Long {
        val p = prefs(context)
        val now = System.currentTimeMillis()
        val lastIncrement = p.getLong(KEY_LAST_INCREMENT_MS, 0L)
        if (lastIncrement > 0L && now - lastIncrement < BOOT_INCREMENT_DEBOUNCE_MS) {
            val existing = p.getLong(KEY_SESSION, 0L)
            HiCarDiagnosticLog.d("HiCarBoot", "Boot session debounce → reuse id=$existing")
            return existing
        }
        val next = p.getLong(KEY_SESSION, 0L) + 1L
        p.edit()
            .putLong(KEY_SESSION, next)
            .putLong(KEY_LAST_INCREMENT_MS, now)
            .apply()
        HiCarDiagnosticLog.d("HiCarBoot", "New boot session id=$next")
        return next
    }

    fun getCurrentSession(context: Context): Long =
        prefs(context).getLong(KEY_SESSION, 0L)

    fun isSessionCompleted(context: Context, sessionId: Long): Boolean {
        if (sessionId <= 0L) return false
        return prefs(context).getLong(KEY_COMPLETED, -1L) >= sessionId
    }

    /** Box: đã start MediaPlayer cho session này (persist, sống qua kill process). */
    fun hasPlaybackStarted(context: Context, sessionId: Long): Boolean {
        if (sessionId <= 0L) return false
        return prefs(context).getLong(KEY_PLAYBACK_STARTED, -1L) == sessionId
    }

    fun markPlaybackStarted(context: Context, sessionId: Long) {
        if (sessionId <= 0L) return
        prefs(context).edit().putLong(KEY_PLAYBACK_STARTED, sessionId).apply()
        HiCarDiagnosticLog.d("HiCarBoot", "Boot session $sessionId playback started (persisted)")
    }

    /** Ẩn cảnh báo boot oan trên UI khi session đã phát hoặc đã chốt. */
    fun shouldSuppressBootWarnings(context: Context): Boolean {
        val sessionId = getCurrentSession(context)
        if (sessionId <= 0L) return false
        return isSessionCompleted(context, sessionId) || hasPlaybackStarted(context, sessionId)
    }

    fun markSessionCompleted(context: Context, sessionId: Long, reason: String = "completed") {
        if (sessionId <= 0L) return
        val p = prefs(context)
        val prev = p.getLong(KEY_COMPLETED, -1L)
        if (sessionId > prev) {
            p.edit().putLong(KEY_COMPLETED, sessionId).apply()
            HiCarDiagnosticLog.d("HiCarBoot", "Boot session $sessionId completed ($reason)")
            cancelBootRetryAlarms(context)
        }
    }

    fun reportMissIfNeeded(context: Context, sessionId: Long, reason: String) {
        if (sessionId <= 0L) return
        if (isSessionCompleted(context, sessionId)) return
        val p = prefs(context)
        if (p.getLong(KEY_MISS_REPORTED, -1L) == sessionId) return
        HiCarDiagnosticLog.e("HiCarBoot", "BOOT_PLAYBACK_MISSED: $reason (session=$sessionId)")
        p.edit().putLong(KEY_MISS_REPORTED, sessionId).apply()
    }

    /** Hủy alarm retry boot (Box) khi session đã phát thành công. */
    fun cancelBootRetryAlarms(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        for (index in 0 until BOOT_RETRY_ALARM_COUNT) {
            val intent = Intent(context, AudioForegroundService::class.java).apply {
                action = AudioForegroundService.ACTION_BOOT_RETRY_GREETING
            }
            val pending = PendingIntent.getService(
                context,
                BOOT_RETRY_ALARM_REQUEST_BASE + index,
                intent,
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            )
            pending?.let {
                alarmManager.cancel(it)
                it.cancel()
            }
        }
        HiCarDiagnosticLog.d("HiCarBoot", "Boot retry alarms cancelled")
    }
}
