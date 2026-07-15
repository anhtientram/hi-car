package com.hicar.ora.limited

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.SystemClock
import android.os.UserManager
import java.io.File

/**
 * BootReceiver - Tự động kích hoạt khi thiết bị khởi động hoặc cập nhật gói ứng dụng.
 * Hỗ trợ tự động bật màn hình và phát âm thanh chào mừng cho các dòng Android Box xe hơi.
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        /** Retry boot greeting sau 15s / 40s / 90s nếu box khởi động chậm hoặc audio subsystem chưa sẵn sàng.
         *  (Rút ngắn so với 45/120/300 trước đây để phục hồi nhanh hơn, hợp với poll readiness.) */
        private val BOOT_ALARM_DELAYS_MS = longArrayOf(15_000L, 40_000L, 90_000L)

        fun scheduleBootRetryAlarms(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            BOOT_ALARM_DELAYS_MS.forEachIndexed { index, delayMs ->
                val sessionId = BootSessionManager.getCurrentSession(context)
                val intent = Intent(context, AudioForegroundService::class.java).apply {
                    action = AudioForegroundService.ACTION_BOOT_RETRY_GREETING
                    putExtra(AudioForegroundService.EXTRA_PREFER_BOOT_AUDIO, true)
                    putExtra(AudioForegroundService.EXTRA_BOOT_SESSION_ID, sessionId)
                }
                // FLAG_UPDATE_CURRENT: nếu còn PendingIntent cũ (session trước) thì cập nhật
                // extras (session id mới) thay vì dùng lại extras cũ đã stale.
                val pending = PendingIntent.getService(
                    context,
                    BootSessionManager.BOOT_RETRY_ALARM_REQUEST_BASE + index,
                    intent,
                    PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_UPDATE_CURRENT or
                        PendingIntent.FLAG_IMMUTABLE
                )
                alarmManager.set(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    SystemClock.elapsedRealtime() + delayMs,
                    pending
                )
                HiCarDiagnosticLog.d("HiCarBoot", "Scheduled boot retry alarm #${index + 1} in ${delayMs}ms")
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val validActions = listOf(
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_REBOOT,
            Intent.ACTION_USER_UNLOCKED,
            Intent.ACTION_USER_PRESENT,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON"
        )

        if (intent.action !in validActions) return

        HiCarDiagnosticLog.init(context)
        HiCarDiagnosticLog.markBootSession()

        val prefs = getAvailablePrefs(context)
        val connectionMode = prefs.getString("flutter.connection_mode", "android_screen_mode") ?: "android_screen_mode"

        if (connectionMode != "android_box_mode") {
            HiCarDiagnosticLog.d("HiCarBoot", "Boot skip – mode=$connectionMode (not box)")
            return
        }

        if (!prefs.contains("flutter.auth_token")) {
            HiCarDiagnosticLog.e("HiCarBoot", "Boot skip – no auth_token in prefs")
            return
        }

        if (!hasGreetingAudio(context, prefs)) {
            HiCarDiagnosticLog.e("HiCarBoot", "Boot skip – no greeting audio file")
            return
        }

        // USER_UNLOCKED / USER_PRESENT: retry nếu boot sớm thất bại (audio subsystem cần unlock).
        val isUnlockRetry = intent.action == Intent.ACTION_USER_UNLOCKED ||
            intent.action == Intent.ACTION_USER_PRESENT

        val isRealBoot = !isUnlockRetry
        val bootSessionId = if (isRealBoot) {
            BootSessionManager.incrementSessionOnBoot(context)
        } else {
            BootSessionManager.getCurrentSession(context)
        }

        if (isUnlockRetry && BootSessionManager.isSessionCompleted(context, bootSessionId)) {
            HiCarDiagnosticLog.d("HiCarBoot", "Unlock retry skip – boot session $bootSessionId đã hoàn tất")
            return
        }

        if (isUnlockRetry && BootSessionManager.hasPlaybackStarted(context, bootSessionId)) {
            HiCarDiagnosticLog.d("HiCarBoot", "Unlock retry skip – boot session $bootSessionId đã bắt đầu phát")
            return
        }

        HiCarDiagnosticLog.d("HiCarBoot", "Boot trigger OK – connectionMode=$connectionMode, action=${intent.action}, session=$bootSessionId")

        val serviceIntent = Intent(context, AudioForegroundService::class.java).apply {
            action = AudioForegroundService.ACTION_PLAY_GREETING_DELAYED
            putExtra(AudioForegroundService.EXTRA_PREFER_BOOT_AUDIO, true)
            putExtra(AudioForegroundService.EXTRA_BOOT_SESSION_ID, bootSessionId)
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
            // Chỉ lên lịch alarm retry cho boot thật (không phải unlock retry).
            if (!isUnlockRetry) {
                scheduleBootRetryAlarms(context)
            }
        } catch (e: Exception) {
            HiCarDiagnosticLog.e("HiCarBoot", "startForegroundService failed: ${e.message}")
            e.printStackTrace()
        }
    }

    private fun getAvailablePrefs(context: Context): SharedPreferences {
        // ⚠️ Direct Boot: trước khi user unlock lần đầu, vùng credential-encrypted KHÔNG truy cập
        //    được — chỉ cần GỌI getSharedPreferences trên context thường cũng ném
        //    IllegalStateException và làm CRASH receiver. Vì vậy phải kiểm tra trạng thái unlock
        //    và ưu tiên vùng device-protected khi chưa unlock.
        val deviceContext = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            context.createDeviceProtectedStorageContext()
        } else {
            context
        }
        val protectedPrefs = deviceContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        val userUnlocked = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            (context.getSystemService(Context.USER_SERVICE) as? UserManager)?.isUserUnlocked ?: false
        } else {
            true
        }

        // Chỉ chạm vào credential storage khi đã unlock (để lấy dữ liệu mới nhất từ UI).
        if (userUnlocked) {
            try {
                val regularPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                if (regularPrefs.all.isNotEmpty()) return regularPrefs
            } catch (e: Exception) {
                HiCarDiagnosticLog.w("HiCarBoot", "getAvailablePrefs: credential storage không đọc được – ${e.message}")
            }
        }

        return protectedPrefs
    }

    private fun hasGreetingAudio(context: Context, prefs: SharedPreferences): Boolean {
        val configuredPath = prefs.getString("flutter.greeting_audio_path", "") ?: ""
        HiCarDiagnosticLog.d("HiCarBoot", "hasGreetingAudio: flutter.greeting_audio_path=$configuredPath")

        if (configuredPath.isNotEmpty()) {
            val exists = File(configuredPath).exists()
            HiCarDiagnosticLog.d("HiCarBoot", "hasGreetingAudio: regular path exists=$exists")
            if (exists) return true
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            HiCarDiagnosticLog.w("HiCarBoot", "hasGreetingAudio: API < N, no boot_greeting fallback → SKIP")
            return false
        }

        val protectedContext = context.createDeviceProtectedStorageContext()
        val bootFile = File(protectedContext.filesDir, "boot_greeting.mp3")
        HiCarDiagnosticLog.d("HiCarBoot", "hasGreetingAudio: boot_greeting.mp3 path=${bootFile.absolutePath}, exists=${bootFile.exists()}, size=${if (bootFile.exists()) bootFile.length() else 0}")
        return bootFile.exists()
    }
}