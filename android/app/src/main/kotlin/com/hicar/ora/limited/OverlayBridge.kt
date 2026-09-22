package com.hicar.ora.limited

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * OverlayBridge — cầu nối TRỰC TIẾP giữa engine của nút nổi (overlay) và native.
 *
 * Vì sao cần:
 *   Nút nổi chạy trong 1 FlutterEngine/isolate RIÊNG. Trước đây nó gửi lệnh phát nhạc
 *   qua IsolateNameServer → isolate CHÍNH → MethodChannel → service. Chuỗi này phụ thuộc
 *   isolate chính còn sống; khi app ở nền lâu (đặc biệt Android 6–9) isolate chính bị OS
 *   treo/giết nên bấm nút KHÔNG tới được native → không phát nhạc, phải kill app.
 *
 * Giải pháp:
 *   Đăng ký 1 MethodChannel TRỰC TIẾP trên messenger của overlay engine. Overlay gọi thẳng
 *   xuống đây; native tự đọc path lời chào/tạm biệt (đã có fallback boot file) rồi khởi động
 *   AudioForegroundService để phát. Không cần isolate chính. App có quyền SYSTEM_ALERT_WINDOW
 *   (bắt buộc để hiện nút nổi) nên được miễn trừ giới hạn khởi động service/activity ở nền.
 */
object OverlayBridge {

    const val CHANNEL = "com.hicar.ora.limited/overlay_bridge"

    // Tag engine cache mà flutter_overlay_window dùng (OverlayConstants.CACHED_TAG).
    const val OVERLAY_ENGINE_TAG = "myCachedEngine"

    @Volatile
    private var channel: MethodChannel? = null

    @Volatile
    private var registeredEngineHash: Int = 0

    private val mainHandler = Handler(Looper.getMainLooper())

    /** Đăng ký handler lên overlay engine. Idempotent theo từng engine instance. */
    fun register(engine: FlutterEngine, appContext: Context) {
        val hash = System.identityHashCode(engine)
        if (registeredEngineHash == hash && channel != null) return
        val ctx = appContext.applicationContext
        HiCarDiagnosticLog.init(ctx)
        val ch = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        ch.setMethodCallHandler { call, result -> handle(call, result, ctx) }
        channel = ch
        registeredEngineHash = hash
        HiCarDiagnosticLog.d("OverlayBridge", "registered on overlay engine #$hash")
    }

    // ── Overlay (Dart) → Native ──────────────────────────────────────────────

    private fun handle(call: MethodCall, result: MethodChannel.Result, ctx: Context) {
        when (call.method) {
            "playGreeting" -> playType(ctx, "greeting", result)
            "playGoodbye" -> playType(ctx, "goodbye", result)
            "stopAudio" -> {
                startAudioService(ctx, AudioForegroundService.ACTION_STOP_AUDIO, null)
                result.success(true)
            }
            "openApp" -> {
                openApp(ctx)
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Phát lời chào/tạm biệt. Trả về:
     *  - true  : đã có file hợp lệ và đã gửi lệnh phát.
     *  - false : CHƯA CẤU HÌNH (không có path hợp lệ) → đồng thời hiện Toast báo khách.
     */
    private fun playType(ctx: Context, type: String, result: MethodChannel.Result) {
        val path = resolvePath(ctx, type)
        if (path == null) {
            val msg = if (type == "greeting") "Chưa cấu hình lời chào" else "Chưa cấu hình lời tạm biệt"
            mainHandler.post {
                try {
                    Toast.makeText(ctx, msg, Toast.LENGTH_LONG).show()
                } catch (_: Exception) {
                }
            }
            HiCarDiagnosticLog.e("OverlayBridge", "playType($type): no valid audio path → not configured")
            HiCarPlugin.instance?.invokeServiceMethod(
                "onNativeError",
                "Overlay không tìm thấy file audio $type hợp lệ"
            )
            result.success(false)
            return
        }
        val action = if (type == "greeting") AudioForegroundService.ACTION_PLAY_GREETING
        else AudioForegroundService.ACTION_PLAY_GOODBYE
        startAudioService(ctx, action, path)
        result.success(true)
    }

    /** Đọc path từ prefs (ưu tiên vùng thường, fallback device-protected), rồi fallback boot file. */
    private fun resolvePath(ctx: Context, type: String): String? {
        val prefKey = if (type == "greeting") "flutter.greeting_audio_path" else "flutter.goodbye_audio_path"
        val bootName = if (type == "greeting") "boot_greeting.mp3" else "boot_goodbye.mp3"

        val prefPath = readPref(ctx, prefKey)
        if (!prefPath.isNullOrEmpty() && AudioFileValidator.isUsable(File(prefPath))) return prefPath

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                val bootFile = File(ctx.createDeviceProtectedStorageContext().filesDir, bootName)
                if (AudioFileValidator.isUsable(bootFile)) return bootFile.absolutePath
            } catch (_: Exception) {
            }
        }
        return null
    }

    private fun readPref(ctx: Context, key: String): String? {
        try {
            val regular = ctx.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val v = regular.getString(key, null)
            if (!v.isNullOrEmpty()) return v
        } catch (_: Exception) {
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                val dp = ctx.createDeviceProtectedStorageContext()
                    .getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                return dp.getString(key, null)
            } catch (_: Exception) {
            }
        }
        return null
    }

    private fun startAudioService(ctx: Context, action: String, path: String?) {
        val intent = Intent(ctx, AudioForegroundService::class.java).apply {
            this.action = action
            if (path != null) putExtra("audioPath", path)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) ctx.startForegroundService(intent)
            else ctx.startService(intent)
        } catch (e: Exception) {
            HiCarDiagnosticLog.e("OverlayBridge", "startAudioService error: ${e.message}")
            HiCarPlugin.instance?.invokeServiceMethod(
                "onNativeError",
                "Overlay không khởi động được AudioForegroundService: ${e.message}"
            )
        }
    }

    private fun openApp(ctx: Context) {
        try {
            val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName) ?: return
            launch.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
            )
            ctx.startActivity(launch)
        } catch (e: Exception) {
            HiCarDiagnosticLog.e("OverlayBridge", "openApp error: ${e.message}")
        }
    }

    // ── Native → Overlay (cập nhật trạng thái pulse) ──────────────────────────

    fun notifyPlaybackStarted(type: String) {
        mainHandler.post {
            try {
                channel?.invokeMethod("onPlaybackStarted", type)
            } catch (_: Exception) {
            }
        }
    }

    fun notifyPlaybackComplete() {
        mainHandler.post {
            try {
                channel?.invokeMethod("onPlaybackComplete", null)
            } catch (_: Exception) {
            }
        }
    }
}
