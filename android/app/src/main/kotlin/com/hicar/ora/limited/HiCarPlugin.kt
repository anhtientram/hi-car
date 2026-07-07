package com.hicar.ora.limited

import android.content.Context
import android.content.Intent
import android.content.ComponentName
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * HiCarPlugin — custom native plugin.
 *
 * Dùng FlutterPlugin interface chuẩn + đăng ký trong GeneratedPluginRegistrant
 * để đảm bảo được re-register đúng thời điểm khi Dart VM khởi động.
 *
 * Không clear handler trong onDetachedFromEngine vì engine được cache.
 */
class HiCarPlugin : FlutterPlugin, MethodCallHandler {

    companion object {
        @Volatile
        var instance: HiCarPlugin? = null

        const val SERVICE_CHANNEL   = "com.hicar.ora.limited/service"
        const val BLUETOOTH_CHANNEL = "com.hicar.ora.limited/bluetooth"

        /**
         * Đăng ký channels TRỰC TIẾP trên messenger của 1 engine cụ thể.
         * Gọi từ MainActivity.configureFlutterEngine với dartExecutor của engine HIỂN THỊ
         * → đảm bảo cả 2 chiều (Flutter→Native và Native→Flutter) đều dùng đúng messenger,
         *   KHÔNG phụ thuộc GeneratedPluginRegistrant (file tự sinh) hay thứ tự attach của
         *   các engine phụ (overlay, audio_service).
         */
        fun registerWith(messenger: BinaryMessenger, appContext: Context): HiCarPlugin {
            val plugin = instance ?: HiCarPlugin()
            plugin.attach(messenger, appContext)
            instance = plugin
            return plugin
        }
    }

    private lateinit var serviceChannel: MethodChannel
    private lateinit var bluetoothChannel: MethodChannel
    private lateinit var context: Context
    private val mainHandler = Handler(Looper.getMainLooper())

    /** (Re)tạo channels + handlers trên messenger được cung cấp. Idempotent. */
    fun attach(messenger: BinaryMessenger, appContext: Context) {
        context = appContext
        serviceChannel   = MethodChannel(messenger, SERVICE_CHANNEL)
        bluetoothChannel = MethodChannel(messenger, BLUETOOTH_CHANNEL)
        serviceChannel.setMethodCallHandler(this)
        bluetoothChannel.setMethodCallHandler { call, result -> handleBluetoothCall(call, result) }
        android.util.Log.i(
            "HiCarPlugin",
            "attach ✓ messenger#${System.identityHashCode(messenger)} plugin#${System.identityHashCode(this)}"
        )
    }

    // ── FlutterPlugin lifecycle ────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        android.util.Log.i(
            "HiCarPlugin",
            "onAttachedToEngine (auto) messenger#${System.identityHashCode(binding.binaryMessenger)}"
        )
        // Không tự gán instance ở đây để tránh engine phụ (overlay/audio_service) ghi đè
        // instance của engine hiển thị. Engine hiển thị đăng ký qua registerWith() trong
        // MainActivity. Chỉ attach nếu chưa có instance nào (trường hợp hiếm).
        if (instance == null) {
            registerWith(binding.binaryMessenger, binding.applicationContext)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        android.util.Log.d("HiCarPlugin", "onDetachedFromEngine — handlers kept alive")
        // Không null handler: engine được cache và sẽ tái sử dụng.
    }

    // ── Native → Flutter helpers ───────────────────────────────────────────────

    fun invokeServiceMethod(method: String, arguments: Any? = null) {
        mainHandler.post {
            try {
                serviceChannel.invokeMethod(method, arguments)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    fun invokeBluetoothMethod(method: String, arguments: Any? = null) {
        mainHandler.post {
            try {
                bluetoothChannel.invokeMethod(method, arguments)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    // ── Flutter → Native ───────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: Result) {
        android.util.Log.i("HiCarPlugin", "onMethodCall: ${call.method}")
        when (call.method) {
            "startService" -> {
                startAudioService(AudioForegroundService.ACTION_START)
                result.success(true)
            }
            "stopService" -> {
                startAudioService(AudioForegroundService.ACTION_STOP)
                result.success(true)
            }
            "playGreeting" -> {
                val audioPath = call.argument<String>("audioPath") ?: ""
                if (audioPath.isNotEmpty()) autoSyncBootFile(audioPath, "boot_greeting.mp3")
                val intent = buildServiceIntent(AudioForegroundService.ACTION_PLAY_GREETING)
                intent.putExtra("audioPath", audioPath)
                startServiceSafe(intent)
                result.success(true)
            }
            "playGoodbye" -> {
                val audioPath = call.argument<String>("audioPath") ?: ""
                if (audioPath.isNotEmpty()) autoSyncBootFile(audioPath, "boot_goodbye.mp3")
                val intent = buildServiceIntent(AudioForegroundService.ACTION_PLAY_GOODBYE)
                intent.putExtra("audioPath", audioPath)
                startServiceSafe(intent)
                result.success(true)
            }
            "stopAudio" -> {
                startAudioService(AudioForegroundService.ACTION_STOP_AUDIO)
                result.success(true)
            }
            "minimizeApp" -> {
                minimizeApp()
                result.success(true)
            }
            "showAutostartSettings" -> {
                showAutostartSettings()
                result.success(true)
            }
            "showBatteryOptimizationSettings" -> {
                showBatteryOptimizationSettings()
                result.success(true)
            }
            "isIgnoringBatteryOptimizations" -> {
                result.success(isIgnoringBatteryOptimizations())
            }
            "syncPrefs" -> {
                syncPrefsToDeviceProtected()
                syncFilesToDeviceProtected()
                result.success(true)
            }
            "clearAuthState" -> {
                clearAuthState()
                result.success(true)
            }
            "clearGreetingConfig" -> {
                clearAudioConfig("greeting")
                result.success(true)
            }
            "clearGoodbyeConfig" -> {
                clearAudioConfig("goodbye")
                result.success(true)
            }
            "getDiagnosticLogErrors" -> {
                HiCarDiagnosticLog.init(context)
                result.success(HiCarDiagnosticLog.getErrorLog(context))
            }
            "getDiagnosticLogFull" -> {
                HiCarDiagnosticLog.init(context)
                result.success(HiCarDiagnosticLog.getFullLog())
            }
            "hasDiagnosticErrors" -> {
                HiCarDiagnosticLog.init(context)
                result.success(HiCarDiagnosticLog.hasErrorLines(context))
            }
            "clearDiagnosticLog" -> {
                HiCarDiagnosticLog.init(context)
                HiCarDiagnosticLog.clear()
                result.success(true)
            }
            "appendDiagnosticDemo" -> {
                HiCarDiagnosticLog.init(context)
                val scenario = call.argument<String>("scenario") ?: "boot"
                appendDiagnosticDemo(scenario)
                result.success(true)
            }
            "openApp" -> openApp(result)
            else -> result.notImplemented()
        }
    }

    // ── Boot file sync ─────────────────────────────────────────────────────────

    private fun autoSyncBootFile(sourcePath: String, destName: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        try {
            val src = java.io.File(sourcePath)
            if (!src.exists()) return
            val destDir = context.createDeviceProtectedStorageContext().filesDir
            val dest = java.io.File(destDir, destName)
            if (dest.exists() && dest.length() == src.length()) return
            src.copyTo(dest, overwrite = true)
            android.util.Log.i("HiCarPlugin", "autoSyncBootFile: $destName updated (${dest.length()} bytes)")
        } catch (e: Exception) {
            android.util.Log.e("HiCarPlugin", "autoSyncBootFile: error – ${e.message}")
        }
    }

    // ── Clear auth state (đăng xuất) ──────────────────────────────────────────

    /**
     * Xoá token đăng nhập khỏi prefs thường VÀ device-protected. syncPrefs chỉ ghi đè
     * (không xoá), nên sau khi Flutter remove key ở prefs thường thì vùng device-protected
     * vẫn còn token cũ → BootReceiver sau reboot vẫn tưởng đã đăng nhập và tự phát nhạc.
     * Hàm này xoá thủ công ở cả 2 nơi để chặn triệt để.
     */
    private fun clearAuthState() {
        val authKeys = listOf("flutter.auth_token", "flutter.user_data")

        try {
            val editor = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit()
            authKeys.forEach { editor.remove(it) }
            editor.apply()
        } catch (e: Exception) {
            android.util.Log.w("HiCarPlugin", "clearAuthState: regular prefs – ${e.message}")
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                val deviceContext = context.createDeviceProtectedStorageContext()
                val editor = deviceContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit()
                authKeys.forEach { editor.remove(it) }
                editor.commit()
            } catch (e: Exception) {
                android.util.Log.w("HiCarPlugin", "clearAuthState: device-protected – ${e.message}")
            }
        }
        android.util.Log.i("HiCarPlugin", "clearAuthState done")
    }

    // ── Clear audio config (bỏ đặt lời chào / tạm biệt) ───────────────────────

    /**
     * Xoá hoàn toàn cấu hình audio cho [type] ("greeting"/"goodbye"):
     * - Xoá key path ở prefs thường VÀ device-protected (syncPrefs chỉ ghi đè, không xoá,
     *   nên phải xoá thủ công ở cả 2 nơi).
     * - Xoá file boot (boot_greeting.mp3 / boot_goodbye.mp3) để nút nổi/boot không phát lại.
     */
    private fun clearAudioConfig(type: String) {
        val prefKey = if (type == "greeting") "flutter.greeting_audio_path" else "flutter.goodbye_audio_path"
        val bootName = if (type == "greeting") "boot_greeting.mp3" else "boot_goodbye.mp3"

        try {
            context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .edit().remove(prefKey).apply()
        } catch (e: Exception) {
            android.util.Log.w("HiCarPlugin", "clearAudioConfig: regular prefs – ${e.message}")
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                val deviceContext = context.createDeviceProtectedStorageContext()
                deviceContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    .edit().remove(prefKey).commit()
                val bootFile = java.io.File(deviceContext.filesDir, bootName)
                if (bootFile.exists()) bootFile.delete()
            } catch (e: Exception) {
                android.util.Log.w("HiCarPlugin", "clearAudioConfig: device-protected – ${e.message}")
            }
        }
        android.util.Log.i("HiCarPlugin", "clearAudioConfig($type) done")
    }

    // ── SharedPreferences → Device Protected sync ─────────────────────────────

    private fun syncPrefsToDeviceProtected() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val deviceContext = context.createDeviceProtectedStorageContext()
            val sourcePrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val destPrefs   = deviceContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val editor = destPrefs.edit()
            for ((key, value) in sourcePrefs.all) {
                when (value) {
                    is String  -> editor.putString(key, value)
                    is Boolean -> editor.putBoolean(key, value)
                    is Float   -> editor.putFloat(key, value)
                    is Int     -> editor.putInt(key, value)
                    is Long    -> editor.putLong(key, value)
                }
            }
            editor.commit()
        }
    }

    private fun syncFilesToDeviceProtected() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        val deviceContext = context.createDeviceProtectedStorageContext()
        val prefs = deviceContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val greetingPath = prefs.getString("flutter.greeting_audio_path", "") ?: ""
        val goodbyePath  = prefs.getString("flutter.goodbye_audio_path",  "") ?: ""
        if (greetingPath.isNotEmpty()) copyFileToProtected(greetingPath, "boot_greeting.mp3", deviceContext)
        if (goodbyePath.isNotEmpty())  copyFileToProtected(goodbyePath,  "boot_goodbye.mp3",  deviceContext)
        val bg = java.io.File(deviceContext.filesDir, "boot_greeting.mp3")
        android.util.Log.i("HiCarSync", "boot_greeting.mp3 exists=${bg.exists()}, size=${if (bg.exists()) bg.length() else 0} bytes")
    }

    private fun copyFileToProtected(sourcePath: String, destName: String, deviceContext: android.content.Context) {
        try {
            val src = java.io.File(sourcePath)
            if (!src.exists()) { android.util.Log.e("HiCarSync", "source NOT found: $sourcePath"); return }
            val dest = java.io.File(deviceContext.filesDir, destName)
            src.inputStream().use { i -> dest.outputStream().use { o -> i.copyTo(o) } }
            android.util.Log.i("HiCarSync", "copyFileToProtected OK → ${dest.absolutePath} (${dest.length()} bytes)")
        } catch (e: Exception) {
            android.util.Log.e("HiCarSync", "copyFileToProtected ERROR $destName – ${e.message}")
        }
    }

    // ── App / Settings ─────────────────────────────────────────────────────────

    private fun showAutostartSettings() {
        val manufacturer = Build.MANUFACTURER.lowercase()
        val intent = Intent()
        try {
            when {
                manufacturer.contains("xiaomi") ->
                    intent.component = ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity")
                manufacturer.contains("oppo") ->
                    intent.component = ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity")
                manufacturer.contains("vivo") ->
                    intent.component = ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity")
                else -> {
                    intent.action = android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS
                    intent.data   = android.net.Uri.fromParts("package", context.packageName, null)
                }
            }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        } catch (e: Exception) {
            val fallback = Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            fallback.data = android.net.Uri.fromParts("package", context.packageName, null)
            fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(fallback)
        }
    }

    private fun minimizeApp() {
        val intent = Intent(Intent.ACTION_MAIN)
        intent.addCategory(Intent.CATEGORY_HOME)
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        context.startActivity(intent)
    }

    /**
     * Mở màn hình "Tối ưu hoá pin" của hệ thống (danh sách app) để người dùng TỰ tắt
     * tối ưu pin cho app. Dùng ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS — KHÔNG cần
     * quyền REQUEST_IGNORE_BATTERY_OPTIMIZATIONS và hợp lệ với chính sách Google Play
     * (khác với hộp thoại cấp trực tiếp ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).
     */
    private fun showBatteryOptimizationSettings() {
        try {
            val intent = Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        } catch (e: Exception) {
            // Fallback: mở trang chi tiết ứng dụng nếu thiết bị không có màn hình trên.
            val fallback = Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            fallback.data = android.net.Uri.fromParts("package", context.packageName, null)
            fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try { context.startActivity(fallback) } catch (_: Exception) {}
        }
    }

    /** Đọc trạng thái "Không hạn chế" từ hệ thống — không phụ thuộc manifest permission. */
    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return false
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    private fun handleBluetoothCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getPairedDevices" -> result.success(BluetoothReceiver.getPairedDevices(context))
            "setTargetDevice" -> {
                AudioForegroundService.targetDeviceAddress = call.argument<String>("address") ?: ""
                AudioForegroundService.delaySeconds = call.argument<Int>("delay") ?: 5
                result.success(true)
            }
            "clearTargetDevice" -> { AudioForegroundService.targetDeviceAddress = ""; result.success(true) }
            "connectDevice" -> BluetoothReceiver.connectDevice(context, call.argument<String>("address") ?: "") { result.success(it) }
            "disconnectDevice" -> BluetoothReceiver.disconnectDevice(context, call.argument<String>("address") ?: "") { result.success(it) }
            "startDiscovery" -> result.success(BluetoothReceiver.startDiscovery(context))
            "stopDiscovery"  -> result.success(BluetoothReceiver.stopDiscovery(context))
            "setConnectionMode" -> {
                val mode = call.argument<String>("mode") ?: "phone_bluetooth"
                AudioForegroundService.connectionMode = mode
                context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    .edit().putString("flutter.connection_mode", mode).apply()
                result.success(true)
            }
            "openApp" -> openApp(result)
            else -> result.notImplemented()
        }
    }

    private fun openApp(result: Result) {
        try {
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launchIntent != null) {
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                launchIntent.action = Intent.ACTION_MAIN
                launchIntent.addCategory(Intent.CATEGORY_LAUNCHER)
                context.startActivity(launchIntent)
                result.success(true)
            } else result.success(false)
        } catch (e: Exception) {
            e.printStackTrace(); result.success(false)
        }
    }

    private fun startAudioService(action: String) = startServiceSafe(buildServiceIntent(action))

    private fun buildServiceIntent(action: String) =
        Intent(context, AudioForegroundService::class.java).apply { this.action = action }

    private fun startServiceSafe(intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent)
        else context.startService(intent)
    }

    /** Demo adb-style lines for testing bug report UI (Settings → Báo cáo lỗi). */
    private fun appendDiagnosticDemo(scenario: String) {
        HiCarDiagnosticLog.markBootSession()
        when (scenario) {
            "boot" -> {
                HiCarDiagnosticLog.d("HiCarBoot", "Boot trigger OK – connectionMode=android_box_mode, action=BOOT_COMPLETED")
                HiCarDiagnosticLog.d("HiCarService", "scheduleDelayedGreeting: delay=5000ms, useBootAudio=true")
                HiCarDiagnosticLog.w("HiCarAudio", "playAudio: focus denied, retry 1/4 in 2500ms...")
                HiCarDiagnosticLog.e("HiCarService", "Boot greeting (intent) bỏ qua – đã phát thành công trong tiến trình này")
            }
            "boot_fail" -> {
                HiCarDiagnosticLog.d("HiCarBoot", "Boot trigger OK – connectionMode=android_box_mode, action=LOCKED_BOOT_COMPLETED")
                HiCarDiagnosticLog.w("HiCarAudio", "playAudio: focus denied, retry 4/4 in 2500ms...")
                HiCarDiagnosticLog.e("HiCarAudio", "playAudio: file does NOT exist at path=/data/.../missing.mp3")
            }
            "sync" -> {
                HiCarDiagnosticLog.d("HiCarSync", "syncPrefsToDeviceProtected OK")
                HiCarDiagnosticLog.e("HiCarSync", "copyFileToProtected ERROR boot_greeting.mp3 – source NOT found")
            }
            else -> {
                HiCarDiagnosticLog.w("HiCarService", "Demo scenario: $scenario")
                HiCarDiagnosticLog.e("HiCarAudio", "Error playing audio: demo MediaPlayer failure")
            }
        }
    }
}
