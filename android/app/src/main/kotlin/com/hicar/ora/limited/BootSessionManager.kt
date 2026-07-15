package com.hicar.ora.limited

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.provider.Settings
import java.io.File

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
    private const val KEY_LAST_BOOT_COUNT = "last_os_boot_count"
    private const val KEY_LAST_BOOT_ID = "last_kernel_boot_id"
    private const val KEY_BEST_EFFORT_SESSION = "boot_best_effort_session_id"
    private const val KEY_BEST_EFFORT_COUNT = "boot_best_effort_count"
    private const val BOOT_INCREMENT_DEBOUNCE_MS = 60_000L

    const val BOOT_RETRY_ALARM_REQUEST_BASE = 100
    const val BOOT_RETRY_ALARM_COUNT = 3

    /** Số lần phát "best-effort" (chưa xin được audio focus) tối đa mỗi phiên boot.
     *  Giới hạn để: (1) box HAL chậm vẫn được thử lại khi có focus; (2) box không bao giờ
     *  cấp focus thì cũng chỉ phát tối đa ngần này lần → chống lặp. */
    const val MAX_BEST_EFFORT_ATTEMPTS = 2

    private fun prefs(context: Context): SharedPreferences {
        val app = context.applicationContext
        val storage = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            app.createDeviceProtectedStorageContext()
        } else {
            app
        }
        return storage.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    /** Số thứ tự boot của HĐH (Settings.Global.BOOT_COUNT, API 24+). -1 nếu không đọc được.
     *  Monotonic, KHÔNG phụ thuộc đồng hồ hệ thống → tin cậy hơn wall clock trên box. */
    private fun currentBootCount(context: Context): Long {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return -1L
        return try {
            Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT).toLong()
        } catch (_: Exception) {
            -1L
        }
    }

    /** UUID kernel sinh mới cho MỖI lần boot (đọc được ở mọi API level, kể cả box đời cũ
     *  API < 24 không có BOOT_COUNT). Không phụ thuộc đồng hồ. null nếu ROM chặn đọc. */
    private fun currentBootId(): String? {
        return try {
            File("/proc/sys/kernel/random/boot_id").readText().trim().takeIf { it.isNotEmpty() }
        } catch (_: Exception) {
            null
        }
    }

    fun incrementSessionOnBoot(context: Context): Long {
        val p = prefs(context)
        val existing = p.getLong(KEY_SESSION, 0L)
        val now = System.currentTimeMillis()

        // 🟢 ƯU TIÊN BOOT_COUNT của HĐH để nhận diện "boot mới".
        //    LÝ DO SỬA: nhiều box KHÔNG có pin RTC → mỗi lần cắt nguồn, wall clock reset về
        //    một mốc quá khứ rồi mới được NTP chỉnh lại. Debounce cũ theo wall clock khi đó
        //    cho delta ÂM (now < lastIncrement) → luôn "reuse" session cũ đã completed →
        //    box VĨNH VIỄN không phát nữa (đúng triệu chứng chạy vài ngày rồi tịt).
        //    BOOT_COUNT tăng đều mỗi lần boot, không phụ thuộc giờ giấc:
        //    - Cùng bootCount = cùng một lần boot vật lý (broadcast trùng) → reuse, chống lặp.
        //    - Khác bootCount = boot mới → LUÔN tạo session mới → chắc chắn phát.
        val bootCount = currentBootCount(context)
        if (bootCount >= 0L) {
            val lastBootCount = p.getLong(KEY_LAST_BOOT_COUNT, -1L)
            if (bootCount == lastBootCount && existing > 0L) {
                HiCarDiagnosticLog.d(
                    "HiCarBoot",
                    "Boot session reuse (bootCount=$bootCount không đổi) → id=$existing"
                )
                return existing
            }
            val next = existing + 1L
            p.edit()
                .putLong(KEY_SESSION, next)
                .putLong(KEY_LAST_BOOT_COUNT, bootCount)
                .putLong(KEY_LAST_INCREMENT_MS, now)
                .apply()
            HiCarDiagnosticLog.d("HiCarBoot", "New boot session id=$next (bootCount=$bootCount)")
            return next
        }

        // Fallback 2 (mọi API level, kể cả box đời cũ < 24): kernel boot_id — UUID mới
        // cho mỗi lần boot, không phụ thuộc đồng hồ. Bắt được cả ca đồng hồ reset về
        // đúng một mốc cố định mỗi lần boot (delta dương nhỏ đánh lừa debounce wall-clock).
        val bootId = currentBootId()
        if (bootId != null) {
            val lastBootId = p.getString(KEY_LAST_BOOT_ID, null)
            if (bootId == lastBootId && existing > 0L) {
                HiCarDiagnosticLog.d(
                    "HiCarBoot",
                    "Boot session reuse (boot_id không đổi) → id=$existing"
                )
                return existing
            }
            val next = existing + 1L
            p.edit()
                .putLong(KEY_SESSION, next)
                .putString(KEY_LAST_BOOT_ID, bootId)
                .putLong(KEY_LAST_INCREMENT_MS, now)
                .apply()
            HiCarDiagnosticLog.d("HiCarBoot", "New boot session id=$next (boot_id fallback)")
            return next
        }

        // Fallback cuối: debounce theo wall clock, nhưng delta ÂM (đồng hồ bị lùi
        // sau reboot) phải coi là BOOT MỚI, tuyệt đối không reuse session cũ.
        val lastIncrement = p.getLong(KEY_LAST_INCREMENT_MS, 0L)
        val delta = now - lastIncrement
        if (lastIncrement > 0L && delta in 0L until BOOT_INCREMENT_DEBOUNCE_MS && existing > 0L) {
            HiCarDiagnosticLog.d("HiCarBoot", "Boot session debounce → reuse id=$existing")
            return existing
        }
        val next = existing + 1L
        p.edit()
            .putLong(KEY_SESSION, next)
            .putLong(KEY_LAST_INCREMENT_MS, now)
            .apply()
        HiCarDiagnosticLog.d("HiCarBoot", "New boot session id=$next (wall-clock fallback)")
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

    /** Gỡ marker "đã phát" khi playback bị LỖI giữa chừng → mở lại đường retry cho phiên này. */
    fun clearPlaybackStarted(context: Context, sessionId: Long) {
        if (sessionId <= 0L) return
        val p = prefs(context)
        if (p.getLong(KEY_PLAYBACK_STARTED, -1L) == sessionId) {
            p.edit().remove(KEY_PLAYBACK_STARTED).apply()
            HiCarDiagnosticLog.w(
                "HiCarBoot",
                "Boot session $sessionId playback marker cleared (lỗi giữa chừng → cho phép retry)"
            )
        }
    }

    /** Tăng & trả về số lần đã phát best-effort cho [sessionId] (đếm sống qua kill process). */
    fun incrementBestEffortAttempt(context: Context, sessionId: Long): Int {
        if (sessionId <= 0L) return 0
        val p = prefs(context)
        val currentSession = p.getLong(KEY_BEST_EFFORT_SESSION, -1L)
        val count = if (currentSession == sessionId) p.getInt(KEY_BEST_EFFORT_COUNT, 0) + 1 else 1
        p.edit()
            .putLong(KEY_BEST_EFFORT_SESSION, sessionId)
            .putInt(KEY_BEST_EFFORT_COUNT, count)
            .apply()
        return count
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
