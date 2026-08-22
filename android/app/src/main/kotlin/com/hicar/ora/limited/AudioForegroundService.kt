package com.hicar.ora.limited

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.database.ContentObserver
import android.media.*
import android.net.Uri
import android.os.*
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.media.MediaBrowserServiceCompat
import android.util.Log
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.FlutterEngine
import java.io.File

/**
 * AudioForegroundService - Extends MediaBrowserServiceCompat for Android Auto support.
 *
 * Responsibilities:
 * - Foreground service to keep app alive
 * - WakeLock to prevent CPU sleep
 * - MediaSession for Android Auto / lock screen integration
 * - Audio focus management (grabs & releases properly)
 * - Delayed auto-play on Bluetooth connection
 * - Restarts itself if killed (START_STICKY)
 * - Nạp tĩnh MethodChannel để tránh lỗi MissingPluginException ở bản Release
 */
class AudioForegroundService : MediaBrowserServiceCompat() {

    companion object {
        const val ACTION_START = "ACTION_START"
        const val ACTION_STOP = "ACTION_STOP"
        const val ACTION_PLAY_GREETING = "ACTION_PLAY_GREETING"
        const val ACTION_PLAY_GOODBYE = "ACTION_PLAY_GOODBYE"
        const val ACTION_PLAY_GREETING_DELAYED = "ACTION_PLAY_GREETING_DELAYED"
        const val ACTION_STOP_AUDIO = "ACTION_STOP_AUDIO"
        const val ACTION_BLUETOOTH_DISCONNECTED = "ACTION_BLUETOOTH_DISCONNECTED"
        /** AA không dây: BT vừa nối → poll CarConnection đến khi projection sẵn sàng (không phát sớm qua BT). */
        const val ACTION_AA_WATCH_PROJECTION = "ACTION_AA_WATCH_PROJECTION"
        /** BT màn hình xe: đợi profile A2DP sẵn sàng trước khi phát (ACL connect quá sớm). */
        const val ACTION_BT_WATCH_A2DP = "ACTION_BT_WATCH_A2DP"
        /** Box: retry phát nhạc boot nếu lần đầu thất bại hoặc box khởi động chậm. */
        const val ACTION_BOOT_RETRY_GREETING = "ACTION_BOOT_RETRY_GREETING"
        const val EXTRA_PREFER_BOOT_AUDIO = "EXTRA_PREFER_BOOT_AUDIO"
        const val EXTRA_BOOT_SESSION_ID = "EXTRA_BOOT_SESSION_ID"

        const val NOTIFICATION_CHANNEL_ID = "hicar_service_channel"
        const val NOTIFICATION_ID = 1001

        // Retry xin audio focus khi boot/màn hình khóa trước khi phát best-effort.
        private const val MAX_FOCUS_ATTEMPTS = 4
        private const val FOCUS_RETRY_MS = 2500L

        @Volatile var connectionMode: String = "phone_bluetooth"
        @Volatile var targetDeviceAddress: String = ""
        @Volatile var delaySeconds: Int = 5
        @Volatile var autoPlayEnabled: Boolean = true
        @Volatile var greetingAudioPath: String = ""
        @Volatile var goodbyeAudioPath: String = ""

        // 🟢 BOOT (Box): nhiều broadcast cách nhau >8s (LOCKED_BOOT → BOOT_COMPLETED sau unlock).
        //    Cần cờ một-lần/tiến-trình — debounce theo thời gian KHÔNG đủ cho boot.
        @Volatile var bootGreetingHandled: Boolean = false

        private const val GREETING_DEDUP_WINDOW_MS = 8000L
        // Delay sau khi A2DP sẵn sàng — tối thiểu 3s, user có thể tăng qua delay_seconds.
        private const val BT_MIN_DELAY_SEC = 3
        private const val BT_A2DP_POLL_MS = 500L
        private const val BT_A2DP_WATCH_TIMEOUT_MS = 90_000L
        // Box boot: tối thiểu đã phát bao lâu thì coi là thành công (focus loss / stop giữa chừng).
        private const val BOOT_MIN_PLAYED_TO_COMPLETE_MS = 5_000L

        // 🟢 BOOT READINESS POLL (Box): thay vì CHỜ CỨNG 8s rồi mới phát, ta thăm dò audio
        //    subsystem sớm và PHÁT NGAY khi sẵn sàng → box warm-restart phát sau ~2s thay vì 8s.
        //    - Bắt đầu thăm dò sau BOOT_POLL_START_MS (cho service + audio init kịp tối thiểu).
        //    - Mỗi BOOT_POLL_INTERVAL_MS thử xin audio focus: được = loa đã sẵn sàng → phát ngay.
        //    - Quá BOOT_READY_TIMEOUT_MS vẫn chưa được → phát best-effort + để retry alarm lo tiếp
        //      (cold boot qua đêm: subsystem chưa sẵn sàng thì KHÔNG chốt, tránh phát "ảo").
        private const val BOOT_POLL_START_MS = 2_000L
        private const val BOOT_POLL_INTERVAL_MS = 700L
        private const val BOOT_READY_TIMEOUT_MS = 12_000L
        private const val BOOT_MISS_WATCHDOG_MS = 120_000L
        @Volatile var lastGreetingTriggerAtMs: Long = 0L

        // 🟢 ANDROID AUTO: chỉ tự phát đúng MỘT lần mỗi phiên kết nối (có dây/không dây).
        @Volatile var aaGreetingPlayedThisConnection: Boolean = false
        // Chỉ bật cờ trên khi lời chào do AUTO (không phải bấm nút thủ công).
        @Volatile var pendingAaAutoGreeting: Boolean = false

        // CarConnection (androidx.car.app) – contract CÔNG KHAI để phát hiện Android Auto
        // (cả CÓ DÂY lẫn KHÔNG DÂY) mà không cần thêm dependency / nâng minSdk:
        //   content://androidx.car.app.connection , cột "CarConnectionState".
        // Giá trị: 0 = chưa kết nối, 1 = Automotive OS (native), 2 = đang chiếu (projection/AA).
        private const val CAR_CONNECTION_AUTHORITY = "androidx.car.app.connection"
        private const val CAR_CONNECTION_STATE_COLUMN = "CarConnectionState"
        const val CAR_CONNECTION_NOT_CONNECTED = 0
        const val CAR_CONNECTION_NATIVE = 1
        const val CAR_CONNECTION_PROJECTION = 2

        private const val AA_PROJECTION_POLL_MS = 1000L
        private const val AA_PROJECTION_WATCH_TIMEOUT_MS = 90_000L
        // AA không dây: sau BT connect, gearhead thường sẵn sàng sau ~12–20s (CarConnection có thể lỗi).
        private const val AA_GEARHEAD_FALLBACK_MS = 12_000L
        private const val GEARHEAD_PACKAGE = "com.google.android.projection.gearhead"
    }

    private var mediaPlayer: MediaPlayer? = null
    private var mediaSession: MediaSessionCompat? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var audioManager: AudioManager? = null
    private val handler = Handler(Looper.getMainLooper())
    private var delayedRunnable: Runnable? = null
    private var audioFocusRequest: AudioFocusRequest? = null

    // CarConnection (Android Auto) observer + trạng thái gần nhất.
    private var carConnectionObserver: ContentObserver? = null
    @Volatile private var lastCarConnectionState: Int = CAR_CONNECTION_NOT_CONNECTED
    private var aaProjectionWatchRunnable: Runnable? = null
    private var aaProjectionWatchStartedAtMs: Long = 0L
    private var btA2dpWatchRunnable: Runnable? = null
    private var btA2dpWatchStartedAtMs: Long = 0L
    private var btA2dpWatchAddress: String = ""
    private var bootGreetingWatchRunnable: Runnable? = null
    private var bootGreetingWatchStartedAtMs: Long = 0L
    private var activeBootSessionId: Long = -1L
    private var bootMissWatchdogRunnable: Runnable? = null
    private var bootMissWatchdogScheduledForSession: Long = -1L
    private var completingBootSessionId: Long = -1L
    private var bootPlaybackStartedAtMs: Long = 0L
    private var bootPlaybackDurationMs: Long = 0L
    private var bootPlaybackEverStartedForSession: Long = -1L
    private var bootCompletionFallbackRunnable: Runnable? = null
    private var bootAudioFocusRequest: AudioFocusRequest? = null
    private var bootPlaybackUsesBootFocus: Boolean = false
    // Chỉ mở lại alarm retry MỘT lần mỗi phiên khi MediaPlayer lỗi (chống loop lỗi liên tục).
    private var bootErrorRetryScheduledForSession: Long = -1L

    // true khi lần dừng sắp tới là do người dùng bấm STOP (nút nổi) — để báo Flutter là dừng
    // thủ công, tránh chế độ Màn Độ minimizeApp làm "văng" app đang dùng (YouTube...).
    @Volatile private var userInitiatedStop: Boolean = false

    // ==============================
    // Lifecycle
    // ==============================

    override fun onCreate() {
        super.onCreate()
        HiCarDiagnosticLog.init(this)
        HiCarDiagnosticLog.d("HiCarService", "Service onCreate started")
        
        try {
            // 1. Initialize core managers safely
            audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            
            // 2. Setup Notification & MediaSession FIRST
            setupNotificationChannel()
            setupMediaSession()
            
            // 3. Load preferences (this will trigger updateMediaSessionState if session exists)
            loadPrefs()
            
            acquireWakeLock()
            buildAudioFocusRequest()
            buildBootAudioFocusRequest()

            // 4. Theo dõi kết nối Android Auto (cả có dây lẫn không dây) để tự phát lời chào.
            setupCarConnectionMonitor()
            
            HiCarDiagnosticLog.d("HiCarService", "Service onCreate finished successfully")
        } catch (e: Exception) {
            HiCarDiagnosticLog.e("HiCarService", "CRITICAL ERROR in onCreate: ${e.message}")
            e.printStackTrace()
        }
    }


    private fun loadPrefs() {
        // ⚠️ Direct Boot: trước khi user unlock, vùng credential-encrypted không truy cập được
        //    (gọi getSharedPreferences cũng ném IllegalStateException). Ưu tiên device-protected
        //    khi chưa unlock; chỉ đọc credential storage (dữ liệu mới nhất từ UI) khi đã unlock.
        val storageContext = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            applicationContext.createDeviceProtectedStorageContext()
        } else {
            applicationContext
        }
        val protectedPrefs = storageContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        val userUnlocked = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            (getSystemService(Context.USER_SERVICE) as? UserManager)?.isUserUnlocked ?: false
        } else {
            true
        }

        // Priority: Regular prefs (latest from UI, nếu đã unlock) -> Protected prefs (boot sequence)
        var prefs = protectedPrefs
        if (userUnlocked) {
            try {
                val regularPrefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                if (regularPrefs.all.isNotEmpty()) prefs = regularPrefs
            } catch (e: Exception) {
                Log.w("HiCarService", "loadPrefs: credential storage không đọc được – ${e.message}")
            }
        }
        
        connectionMode = prefs.getString("flutter.connection_mode", "phone_bluetooth") ?: "phone_bluetooth"
        targetDeviceAddress = prefs.getString("flutter.target_device_address", "") ?: ""
        
        val allPrefs = prefs.all
        val delayVal = allPrefs["flutter.delay_seconds"]
        delaySeconds = when (delayVal) {
            is Long -> delayVal.toInt()
            is Int -> delayVal
            is Number -> delayVal.toInt()
            is String -> delayVal.toIntOrNull() ?: 5
            else -> 5
        }
        
        autoPlayEnabled = prefs.getBoolean("flutter.auto_play_enabled", true)
        
        greetingAudioPath = prefs.getString("flutter.greeting_audio_path", "") ?: ""
        goodbyeAudioPath = prefs.getString("flutter.goodbye_audio_path", "") ?: ""

        // 🟢 ƯU TIÊN: Dùng file Boot nếu path chính chưa có hoặc chưa truy cập được sau restart
        if (greetingAudioPath.isEmpty() || !File(greetingAudioPath).exists()) {
            getBootAudioPath("boot_greeting.mp3")?.let {
                greetingAudioPath = it
            }
        }
        
        if (goodbyeAudioPath.isEmpty() || !File(goodbyeAudioPath).exists()) {
            getBootAudioPath("boot_goodbye.mp3")?.let {
                goodbyeAudioPath = it
            }
        }

        // 🟢 CẬP NHẬT TRẠNG THÁI MEDIA SESSION: Nếu không phải mode AA, ngắt kết nối với màn hình xe
        updateMediaSessionState()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: "NONE"
        HiCarDiagnosticLog.d("HiCarService", "onStartCommand: action=$action")

        // 🟢 Android 15 (API 35) CẤM start FGS type mediaPlayback từ BOOT_COMPLETED.
        //    → Khi service được khởi động từ luồng BOOT (ACTION_PLAY_GREETING_DELAYED do
        //      BootReceiver gửi), ta lên foreground bằng type specialUse (được phép từ boot).
        //    → Mọi luồng còn lại (app mở, Android Auto, Bluetooth...) vẫn dùng mediaPlayback
        //      như cũ để KHÔNG ảnh hưởng tới Android Auto đang hoạt động tốt.
        // Luồng boot (Box): cả lần phát đầu (PLAY_GREETING_DELAYED) lẫn các lần retry
        // (BOOT_RETRY_GREETING do AlarmManager bắn khi process có thể đã bị kill) đều cần
        // start FGS bằng type specialUse — mediaPlayback bị CẤM start từ nền/boot trên API 35.
        val fromBoot = action == ACTION_PLAY_GREETING_DELAYED ||
            action == ACTION_BOOT_RETRY_GREETING

        try {
            loadPrefs()
            applyBootSessionFromIntent(intent)
            startForegroundCompat(fromBoot)
        } catch (e: Exception) {
            Log.e("HiCarService", "Error in onStartCommand: ${e.message}")
            // Even if it fails, we must call startForeground on Android 8+ to avoid ANR/Crash
            try {
                startForegroundCompat(fromBoot)
            } catch (e2: Exception) {
                Log.e("HiCarService", "startForeground retry failed: ${e2.message}")
            }
        }

        when (intent?.action) {
            ACTION_START -> { /* Keep alive */ }
            ACTION_STOP -> stopSelf()

            ACTION_PLAY_GREETING -> {
                val path = if (intent.getBooleanExtra(EXTRA_PREFER_BOOT_AUDIO, false)) {
                    getBootAudioPath("boot_greeting.mp3") ?: greetingAudioPath
                } else {
                    intent.getStringExtra("audioPath") ?: greetingAudioPath
                }
                playAudio(path, "greeting")
            }
            ACTION_PLAY_GOODBYE -> {
                val path = intent.getStringExtra("audioPath") ?: goodbyeAudioPath
                playAudio(path, "goodbye")
            }
            ACTION_PLAY_GREETING_DELAYED -> {
                // 🟢 Gộp các trigger trùng trong cùng "đợt kết nối" (boot nhiều broadcast,
                //    hoặc AA không dây = CarConnection + Bluetooth) thành MỘT lần phát.
                val preferBootAudio = intent.getBooleanExtra(EXTRA_PREFER_BOOT_AUDIO, false)
                triggerGreetingDebounced(useBootAudio = preferBootAudio, source = "intent")
            }
            ACTION_STOP_AUDIO -> {
                // Người dùng bấm STOP (nút nổi) → đánh dấu để báo về Flutter là dừng THỦ CÔNG,
                // tránh chế độ Màn Độ hiểu nhầm "phát xong" rồi minimizeApp (đá app ngoài ra).
                userInitiatedStop = true
                stopPlayback()
            }
            ACTION_BLUETOOTH_DISCONNECTED -> {
                loadPrefs()
                cancelDelayedPlay()
                cancelAaProjectionWatch()
                cancelBtA2dpWatch()
                stopPlayback()
                lastGreetingTriggerAtMs = 0L
            }
            ACTION_AA_WATCH_PROJECTION -> {
                loadPrefs()
                if (connectionMode == "phone_android_auto" && autoPlayEnabled) {
                    // Phiên kết nối AA mới (BT vừa nối) → reset cờ để không bị kẹt từ lần phát cũ/thủ công.
                    aaGreetingPlayedThisConnection = false
                    pendingAaAutoGreeting = false
                    lastGreetingTriggerAtMs = 0L
                    Log.d("HiCarAA", "BT connected (AA mode) → bắt đầu watch projection")
                    startAaProjectionWatch()
                }
            }
            ACTION_BT_WATCH_A2DP -> {
                loadPrefs()
                val address = intent.getStringExtra("deviceAddress") ?: targetDeviceAddress
                if (connectionMode == "phone_bluetooth" && autoPlayEnabled && address.isNotEmpty()) {
                    lastGreetingTriggerAtMs = 0L
                    val alreadyReady = BluetoothReceiver.isA2dpConnected(this, address)
                    HiCarDiagnosticLog.d("HiCarBT", "BT ACL → watch A2DP for $address (a2dpReady=$alreadyReady)")
                    startBtA2dpWatch(address)
                } else {
                    HiCarDiagnosticLog.w("HiCarBT", "BT watch bỏ qua: mode=$connectionMode, autoPlay=$autoPlayEnabled, addr='$address'")
                }
            }
            ACTION_BOOT_RETRY_GREETING -> {
                loadPrefs()
                val preferBootAudio = intent.getBooleanExtra(EXTRA_PREFER_BOOT_AUDIO, true)
                if (connectionMode == "android_box_mode" && autoPlayEnabled) {
                    HiCarDiagnosticLog.d("HiCarService", "Boot retry alarm → schedule greeting")
                    triggerGreetingDebounced(useBootAudio = preferBootAudio, source = "boot_retry")
                }
            }
        }

        return START_STICKY
    }

    // ==============================
    // Android Auto connection (CarConnection)
    // ==============================

    /**
     * Đăng ký theo dõi trạng thái CarConnection (Android Auto) qua ContentProvider công khai
     * `content://androidx.car.app.connection`. Hoạt động cho CẢ Android Auto có dây lẫn không dây.
     * Khi chuyển sang trạng thái PROJECTION (đang chiếu) → tự phát lời chào (nếu đang ở mode AA).
     */
    private fun setupCarConnectionMonitor() {
        try {
            val uri = Uri.parse("content://$CAR_CONNECTION_AUTHORITY")
            val observer = object : ContentObserver(handler) {
                override fun onChange(selfChange: Boolean) {
                    handleCarConnectionState(queryCarConnectionType())
                }
            }
            contentResolver.registerContentObserver(uri, true, observer)
            carConnectionObserver = observer
            // Đọc trạng thái hiện tại ngay (phòng khi đã kết nối sẵn lúc service khởi động).
            handleCarConnectionState(queryCarConnectionType())
            loadPrefs()
            if (connectionMode == "phone_android_auto") {
                tryTriggerAaIfProjected("service_init")
            }
            Log.d("HiCarAA", "CarConnection monitor registered")
        } catch (e: Exception) {
            Log.w("HiCarAA", "setupCarConnectionMonitor failed: ${e.message}")
        }
    }

    private fun queryCarConnectionType(): Int {
        return try {
            val uri = Uri.parse("content://$CAR_CONNECTION_AUTHORITY")
            // ⚠️ Phải truyền projection (như androidx.car.app.connection.CarConnection) — query(..., null, ...)
            //    gây NPE trên một số thiết bị: "getClass() on a null object reference".
            val projection = arrayOf(CAR_CONNECTION_STATE_COLUMN)
            contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val idx = cursor.getColumnIndex(CAR_CONNECTION_STATE_COLUMN)
                    if (idx >= 0) {
                        val state = cursor.getInt(idx)
                        Log.d("HiCarAA", "queryCarConnectionType=$state")
                        return state
                    }
                }
                Log.w("HiCarAA", "queryCarConnectionType: empty cursor")
                CAR_CONNECTION_NOT_CONNECTED
            } ?: run {
                Log.w("HiCarAA", "queryCarConnectionType: cursor null")
                CAR_CONNECTION_NOT_CONNECTED
            }
        } catch (e: Exception) {
            Log.w("HiCarAA", "queryCarConnectionType failed: ${e.message}")
            CAR_CONNECTION_NOT_CONNECTED
        }
    }

    /** Fallback khi CarConnection provider lỗi: gearhead (app Android Auto) đang chạy. */
    private fun isGearheadRunning(): Boolean {
        return try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager ?: return false
            @Suppress("DEPRECATION")
            am.runningAppProcesses?.any { proc ->
                proc.importance <= ActivityManager.RunningAppProcessInfo.IMPORTANCE_VISIBLE &&
                    (proc.processName.contains("gearhead") ||
                        proc.processName.contains(GEARHEAD_PACKAGE))
            } == true
        } catch (e: Exception) {
            Log.w("HiCarAA", "isGearheadRunning failed: ${e.message}")
            false
        }
    }

    private fun triggerAaGreetingOnce(source: String) {
        cancelAaProjectionWatch()
        lastCarConnectionState = CAR_CONNECTION_PROJECTION
        loadPrefs()
        if (connectionMode != "phone_android_auto" || !autoPlayEnabled) return
        Log.d("HiCarAA", "AA ready ($source) → trigger greeting")
        triggerGreetingDebounced(useBootAudio = false, source = source)
    }

    /** Poll CarConnection khi ContentObserver không báo (một số máy/AA không dây). */
    private fun startAaProjectionWatch() {
        cancelAaProjectionWatch()
        aaProjectionWatchStartedAtMs = SystemClock.elapsedRealtime()
        aaProjectionWatchRunnable = object : Runnable {
            override fun run() {
                loadPrefs()
                if (connectionMode != "phone_android_auto" || !autoPlayEnabled) {
                    cancelAaProjectionWatch()
                    return
                }
                val state = queryCarConnectionType()
                val elapsed = SystemClock.elapsedRealtime() - aaProjectionWatchStartedAtMs
                if (state == CAR_CONNECTION_PROJECTION) {
                    Log.d("HiCarAA", "AA projection watch: PROJECTION detected")
                    triggerAaGreetingOnce("carconnection_poll")
                    return
                }
                if (isGearheadRunning() && elapsed >= AA_GEARHEAD_FALLBACK_MS) {
                    Log.d("HiCarAA", "AA projection watch: gearhead fallback (elapsed=${elapsed}ms)")
                    triggerAaGreetingOnce("gearhead_fallback")
                    return
                }
                if (elapsed > AA_PROJECTION_WATCH_TIMEOUT_MS) {
                    Log.w("HiCarAA", "AA projection watch timeout (${AA_PROJECTION_WATCH_TIMEOUT_MS}ms)")
                    cancelAaProjectionWatch()
                    return
                }
                handler.postDelayed(this, AA_PROJECTION_POLL_MS)
            }
        }
        handler.post(aaProjectionWatchRunnable!!)
    }

    private fun cancelAaProjectionWatch() {
        aaProjectionWatchRunnable?.let { handler.removeCallbacks(it) }
        aaProjectionWatchRunnable = null
        aaProjectionWatchStartedAtMs = 0L
    }

    /** Poll A2DP profile cho đến khi màn hình xe sẵn sàng nhận audio. */
    private fun startBtA2dpWatch(address: String) {
        cancelBtA2dpWatch()
        btA2dpWatchAddress = address
        btA2dpWatchStartedAtMs = SystemClock.elapsedRealtime()
        btA2dpWatchRunnable = object : Runnable {
            override fun run() {
                loadPrefs()
                if (connectionMode != "phone_bluetooth" || !autoPlayEnabled) {
                    cancelBtA2dpWatch()
                    return
                }
                val elapsed = SystemClock.elapsedRealtime() - btA2dpWatchStartedAtMs
                if (BluetoothReceiver.isA2dpConnected(this@AudioForegroundService, address)) {
                    HiCarDiagnosticLog.d("HiCarBT", "A2DP ready after ${elapsed}ms → trigger greeting (loa xe đã sẵn sàng)")
                    cancelBtA2dpWatch()
                    triggerGreetingDebounced(useBootAudio = false, source = "a2dp_ready")
                    return
                }
                if (elapsed > BT_A2DP_WATCH_TIMEOUT_MS) {
                    HiCarDiagnosticLog.w("HiCarBT", "A2DP watch timeout (${BT_A2DP_WATCH_TIMEOUT_MS}ms) → skip (màn xe không sẵn sàng?)")
                    cancelBtA2dpWatch()
                    return
                }
                handler.postDelayed(this, BT_A2DP_POLL_MS)
            }
        }
        handler.post(btA2dpWatchRunnable!!)
    }

    private fun cancelBtA2dpWatch() {
        btA2dpWatchRunnable?.let { handler.removeCallbacks(it) }
        btA2dpWatchRunnable = null
        btA2dpWatchStartedAtMs = 0L
        btA2dpWatchAddress = ""
    }

    private fun applyBootSessionFromIntent(intent: Intent?) {
        val sessionFromIntent = intent?.getLongExtra(EXTRA_BOOT_SESSION_ID, -1L) ?: -1L
        if (sessionFromIntent <= 0L) return
        loadPrefs()
        if (connectionMode != "android_box_mode") return

        val currentSession = BootSessionManager.getCurrentSession(this)
        if (sessionFromIntent < currentSession) {
            HiCarDiagnosticLog.d(
                "HiCarService",
                "Stale boot session $sessionFromIntent < current $currentSession → ignore"
            )
            return
        }
        if (sessionFromIntent != activeBootSessionId) {
            activeBootSessionId = sessionFromIntent
            bootGreetingHandled = false
            bootErrorRetryScheduledForSession = -1L
            bootPlaybackEverStartedForSession = -1L
            bootPlaybackStartedAtMs = 0L
            bootPlaybackDurationMs = 0L
            cancelBootCompletionFallback()
            cancelBootMissWatchdog()
            bootMissWatchdogScheduledForSession = -1L
            HiCarDiagnosticLog.d("HiCarService", "Active boot session → $activeBootSessionId")
        }
    }

    private fun resolveBootSessionId(): Long {
        if (activeBootSessionId > 0L) return activeBootSessionId
        return BootSessionManager.getCurrentSession(this)
    }

    private fun isActiveBootSessionComplete(): Boolean {
        return BootSessionManager.isSessionCompleted(this, resolveBootSessionId())
    }

    private fun scheduleBootMissWatchdogIfNeeded() {
        loadPrefs()
        if (connectionMode != "android_box_mode") return
        val sessionId = resolveBootSessionId()
        if (sessionId <= 0L) return
        if (bootMissWatchdogScheduledForSession == sessionId) return
        bootMissWatchdogScheduledForSession = sessionId
        cancelBootMissWatchdog()
        bootMissWatchdogRunnable = Runnable {
            if (!BootSessionManager.isSessionCompleted(this, sessionId)) {
                val reason = if (bootPlaybackEverStartedForSession == sessionId) {
                    "timeout_playback_not_completed"
                } else {
                    "timeout_no_playback"
                }
                BootSessionManager.reportMissIfNeeded(this, sessionId, reason)
            }
        }
        handler.postDelayed(bootMissWatchdogRunnable!!, BOOT_MISS_WATCHDOG_MS)
        HiCarDiagnosticLog.d("HiCarService", "Boot miss watchdog scheduled ${BOOT_MISS_WATCHDOG_MS}ms for session=$sessionId")
    }

    private fun cancelBootMissWatchdog() {
        bootMissWatchdogRunnable?.let { handler.removeCallbacks(it) }
        bootMissWatchdogRunnable = null
    }

    private fun completeBootSessionIfNeeded(reason: String) {
        loadPrefs()
        if (connectionMode != "android_box_mode") return
        val sessionId = completingBootSessionId.takeIf { it > 0L } ?: resolveBootSessionId()
        if (sessionId <= 0L || BootSessionManager.isSessionCompleted(this, sessionId)) return
        BootSessionManager.markSessionCompleted(this, sessionId, reason)
        bootGreetingHandled = true
        completingBootSessionId = -1L
        cancelBootMissWatchdog()
        cancelBootCompletionFallback()
        bootMissWatchdogScheduledForSession = -1L
    }

    private fun cancelBootCompletionFallback() {
        bootCompletionFallbackRunnable?.let { handler.removeCallbacks(it) }
        bootCompletionFallbackRunnable = null
    }

    private fun scheduleBootCompletionFallback(durationMs: Long) {
        cancelBootCompletionFallback()
        val delayMs = (durationMs + 3_000L).coerceAtLeast(15_000L)
        bootCompletionFallbackRunnable = Runnable {
            loadPrefs()
            if (connectionMode != "android_box_mode") return@Runnable
            if (isActiveBootSessionComplete() || completingBootSessionId <= 0L) return@Runnable
            val playedMs = SystemClock.elapsedRealtime() - bootPlaybackStartedAtMs
            val thresholdMs = (bootPlaybackDurationMs * 0.8)
                .toLong()
                .coerceAtLeast(BOOT_MIN_PLAYED_TO_COMPLETE_MS)
            if (playedMs >= thresholdMs) {
                HiCarDiagnosticLog.d("HiCarService", "Boot completion fallback sau ${playedMs}ms")
                completeBootSessionIfNeeded("played_duration_fallback")
                stopPlayback(releaseOnly = false)
            }
        }
        handler.postDelayed(bootCompletionFallbackRunnable!!, delayMs)
    }

    private fun maybeCompleteBootSessionOnInterrupt() {
        loadPrefs()
        if (connectionMode != "android_box_mode" || completingBootSessionId <= 0L) return
        // Bị ngắt chủ động (bấm dừng / focus loss / BT disconnect) sau khi đã phát ≥5s →
        // chốt phiên luôn (kể cả best-effort) để alarm retry KHÔNG phát lại lần nữa gây lặp.
        // Nguồn ngắt chủ động ngụ ý hệ thống audio đang hoạt động → lần phát này có ra tiếng.
        val playedMs = if (bootPlaybackStartedAtMs > 0L) {
            SystemClock.elapsedRealtime() - bootPlaybackStartedAtMs
        } else {
            0L
        }
        if (playedMs >= BOOT_MIN_PLAYED_TO_COMPLETE_MS) {
            completeBootSessionIfNeeded("stop_after_played")
        }
    }

    /**
     * Box boot: MediaPlayer.start() thành công → hủy alarm retry, persist trạng thái,
     * chặn trigger trùng (process hiện tại + sau kill process). Không đụng luồng BT/AA.
     */
    private fun onBoxBootPlaybackStarted(sessionId: Long, hadFocus: Boolean) {
        if (sessionId <= 0L) return
        loadPrefs()
        if (connectionMode != "android_box_mode") return

        bootPlaybackEverStartedForSession = sessionId

        if (hadFocus) {
            // ✅ Có audio focus = loa/route đã sẵn sàng → coi là phát THẬT: chốt trạng thái,
            //    hủy alarm retry để KHÔNG phát lại (chống lặp).
            bootGreetingHandled = true
            BootSessionManager.markPlaybackStarted(this, sessionId)
            BootSessionManager.cancelBootRetryAlarms(this)
            HiCarDiagnosticLog.d(
                "HiCarService",
                "Box boot playback started (session=$sessionId, focus=true) → alarms cancelled"
            )
        } else {
            // ⚠️ Best-effort (chưa xin được audio focus): rất có thể phát vào "hư không"
            //    (audio HAL chưa sẵn sàng lúc cold boot). Mặc định KHÔNG chốt & GIỮ alarm retry
            //    để lần sau (khi có focus) phát lại cho chắc ra tiếng → tránh boot "không phát".
            //    NHƯNG giới hạn số lần: box không bao giờ cấp focus thì sau vài lần ta chốt luôn
            //    để tránh phát lặp nhiều lần.
            val attempts = BootSessionManager.incrementBestEffortAttempt(this, sessionId)
            if (attempts >= BootSessionManager.MAX_BEST_EFFORT_ATTEMPTS) {
                bootGreetingHandled = true
                BootSessionManager.markPlaybackStarted(this, sessionId)
                BootSessionManager.cancelBootRetryAlarms(this)
                HiCarDiagnosticLog.w(
                    "HiCarService",
                    "Box boot best-effort (session=$sessionId) lần $attempts → chốt để chống lặp"
                )
            } else {
                HiCarDiagnosticLog.w(
                    "HiCarService",
                    "Box boot best-effort (session=$sessionId) lần $attempts → GIỮ alarm retry"
                )
            }
        }
    }

    private fun tryTriggerAaIfProjected(source: String) {
        when {
            queryCarConnectionType() == CAR_CONNECTION_PROJECTION ->
                triggerAaGreetingOnce(source)
            isGearheadRunning() ->
                triggerAaGreetingOnce("$source+gearhead")
            else ->
                Log.d("HiCarAA", "tryTriggerAaIfProjected($source): chưa sẵn sàng")
        }
    }

    private fun handleCarConnectionState(state: Int) {
        val previous = lastCarConnectionState
        lastCarConnectionState = state
        if (state == previous) return
        Log.d("HiCarAA", "CarConnection state: $previous → $state")

        when (state) {
            CAR_CONNECTION_PROJECTION -> {
                loadPrefs()
                if (connectionMode == "phone_android_auto" && autoPlayEnabled) {
                    Log.d("HiCarAA", "Projection started → trigger greeting")
                    triggerAaGreetingOnce("carconnection_observer")
                } else {
                    Log.d("HiCarAA", "Projection started but mode=$connectionMode, autoPlay=$autoPlayEnabled → skip")
                }
            }
            CAR_CONNECTION_NOT_CONNECTED -> {
                loadPrefs()
                if (connectionMode == "phone_android_auto") {
                    Log.d("HiCarAA", "Projection ended → stop playback")
                    cancelAaProjectionWatch()
                    cancelDelayedPlay()
                    stopPlayback()
                    lastGreetingTriggerAtMs = 0L
                    aaGreetingPlayedThisConnection = false
                }
            }
        }
    }

    /**
     * Lên lịch phát lời chào với chống lặp theo ngữ cảnh:
     * - Boot (Box): cờ một-lần/tiến-trình khi phát THÀNH CÔNG — broadcast boot có thể cách nhau hàng chục giây.
     * - Android Auto: cờ một-lần/phiên — chỉ bật khi nhạc THỰC SỰ bắt đầu phát (CarConnection=PROJECTION).
     * - Bluetooth: debounce theo thời gian, reset khi ngắt kết nối.
     */
    private fun triggerGreetingDebounced(useBootAudio: Boolean, source: String) {
        if (useBootAudio) {
            loadPrefs()
            if (connectionMode != "android_box_mode") return
            val sessionId = resolveBootSessionId()
            if (BootSessionManager.isSessionCompleted(this, sessionId)) {
                HiCarDiagnosticLog.d(
                    "HiCarService",
                    "Boot greeting ($source) bỏ qua – session $sessionId đã hoàn tất"
                )
                return
            }
            if (BootSessionManager.hasPlaybackStarted(this, sessionId)) {
                HiCarDiagnosticLog.d(
                    "HiCarService",
                    "Boot greeting ($source) bỏ qua – session $sessionId đã bắt đầu phát"
                )
                return
            }
            if (bootGreetingHandled) {
                HiCarDiagnosticLog.d(
                    "HiCarService",
                    "Boot greeting ($source) bỏ qua – đã xử lý trong tiến trình này"
                )
                return
            }
            if (mediaPlayer?.isPlaying == true) {
                HiCarDiagnosticLog.d("HiCarService", "Boot greeting ($source) bỏ qua – đang phát")
                return
            }
            scheduleBootMissWatchdogIfNeeded()
            HiCarDiagnosticLog.d("HiCarService", "Boot greeting ($source) → scheduleDelayedGreeting")
            scheduleDelayedGreeting(useBootAudio = true)
            return
        }

        loadPrefs()

        if (connectionMode == "phone_android_auto") {
            if (aaGreetingPlayedThisConnection) {
                Log.d("HiCarService", "AA greeting ($source) bỏ qua – đã phát trong phiên kết nối này")
                return
            }
        }

        val now = SystemClock.elapsedRealtime()
        val elapsed = now - lastGreetingTriggerAtMs
        if (lastGreetingTriggerAtMs != 0L && elapsed < GREETING_DEDUP_WINDOW_MS) {
            Log.d("HiCarService", "Greeting trigger ($source) bỏ qua – trùng trong ${elapsed}ms")
            return
        }
        lastGreetingTriggerAtMs = now

        if (connectionMode == "phone_android_auto") {
            pendingAaAutoGreeting = true
        }

        Log.d("HiCarService", "Greeting trigger ($source) → scheduleDelayedGreeting")
        scheduleDelayedGreeting(useBootAudio = false)
    }

    /**
     * Lên foreground với FGS type phù hợp ngữ cảnh.
     * - fromBoot=true  → FOREGROUND_SERVICE_TYPE_SPECIAL_USE (được phép start từ BOOT_COMPLETED).
     * - fromBoot=false → FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK (giữ nguyên cho app/Android Auto).
     */
    private fun startForegroundCompat(fromBoot: Boolean) {
        val notification = buildNotification()
        when {
            // API 34+ (Android 14/15): mediaPlayback BỊ CẤM start từ BOOT_COMPLETED, và type
            // specialUse chỉ tồn tại từ API 34 → luồng boot dùng specialUse, còn lại mediaPlayback.
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> {
                val type = if (fromBoot) ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                           else ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                startForeground(NOTIFICATION_ID, notification, type)
            }
            // API 29–33 (Android 10–13): CHƯA có giới hạn boot → luôn dùng mediaPlayback (kể cả luồng boot).
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q -> {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            }
            // API < 29 (Android 9 trở xuống): startForeground 2 tham số, không cần khai báo type.
            else -> startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun getBootAudioPath(fileName: String): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return null

        val storageContext = applicationContext.createDeviceProtectedStorageContext()
        val bootAudio = File(storageContext.filesDir, fileName)
        val result = if (bootAudio.exists()) bootAudio.absolutePath else null
        Log.d("HiCarAudio", "getBootAudioPath($fileName): exists=${bootAudio.exists()}, size=${if (bootAudio.exists()) bootAudio.length() else 0}, path=${bootAudio.absolutePath}")
        return result
    }

    override fun onDestroy() {
        stopPlayback()
        mediaSession?.release()
        wakeLock?.let { if (it.isHeld) it.release() }
        carConnectionObserver?.let {
            try { contentResolver.unregisterContentObserver(it) } catch (_: Exception) {}
        }
        carConnectionObserver = null
        cancelAaProjectionWatch()
        cancelBtA2dpWatch()
        cancelBootGreetingWatch()
        cancelBootMissWatchdog()
        cancelBootCompletionFallback()
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        // Auto-restart when app is swiped away
        val restartIntent = Intent(applicationContext, AudioForegroundService::class.java).apply {
            action = ACTION_START
        }
        val pending = PendingIntent.getService(
            applicationContext, 1, restartIntent,
            PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
        )
        (getSystemService(Context.ALARM_SERVICE) as AlarmManager).set(
            AlarmManager.ELAPSED_REALTIME,
            SystemClock.elapsedRealtime() + 1000,
            pending
        )
    }

    // ==============================
    // MediaBrowserService (Android Auto)
    // ==============================

    override fun onGetRoot(
        clientPackageName: String,
        clientUid: Int,
        rootHints: Bundle?
    ): BrowserRoot? {
        loadPrefs()
        Log.d("HiCarAA", "onGetRoot called by: $clientPackageName")
        
        // 🟢 ẨN APP KHỎI MÀN HÌNH XE NẾU KHÔNG PHẢI MODE ANDROID AUTO
        if (connectionMode != "phone_android_auto") {
            Log.d("HiCarAA", "Not in AA mode, returning null")
            return null
        }

        // Nếu là Android Auto (gearhead), kích hoạt phát lời chào. Đi qua debounce chung để
        // KHÔNG phát đôi khi CarConnection/Bluetooth đã trigger cùng đợt kết nối.
        if (clientPackageName.contains("gearhead") || clientPackageName.contains("com.google.android.projection.gearhead")) {
            if (autoPlayEnabled) {
                Log.d("HiCarAA", "Android Auto bound (onGetRoot) → trigger greeting")
                triggerGreetingDebounced(useBootAudio = false, source = "onGetRoot")
            }
        }
        return BrowserRoot("hicar_root", null)
    }

    override fun onLoadChildren(
        parentId: String,
        result: Result<List<MediaBrowserCompat.MediaItem>>
    ) {
        result.sendResult(emptyList())
    }

    // ==============================
    // Audio Playback
    // ==============================

    private fun scheduleDelayedGreeting(useBootAudio: Boolean = false) {
        cancelDelayedPlay()
        loadPrefs()

        // 🟢 BOOT (Box): KHÔNG chờ cứng 8s nữa — dùng poll readiness để phát NGAY khi audio sẵn
        //    sàng (warm restart phát sau ~2s). Cold boot vẫn đợi đến khi sẵn sàng / timeout.
        if (useBootAudio) {
            startBootGreetingWatch()
            return
        }

        delayedRunnable = Runnable {
            if (mediaPlayer?.isPlaying == true) {
                Log.d("HiCarService", "scheduleDelayedGreeting: đang phát → bỏ qua")
                return@Runnable
            }
            val path = greetingAudioPath
            if (path.isNotEmpty()) {
                playAudio(path, "greeting", isBootAutoPlay = false)
            } else {
                HiCarDiagnosticLog.e("HiCarService", "scheduleDelayedGreeting: no valid audio path found")
            }
        }
        // BT: dùng delay_seconds (tối thiểu 3s). AA: 1.5s.
        val effectiveDelay = when {
            connectionMode == "phone_bluetooth" -> maxOf(delaySeconds.toLong(), BT_MIN_DELAY_SEC.toLong()) * 1000L
            else -> 1500L
        }
        HiCarDiagnosticLog.d("HiCarService", "scheduleDelayedGreeting: delay=${effectiveDelay}ms, useBootAudio=$useBootAudio")
        handler.postDelayed(delayedRunnable!!, effectiveDelay)
    }

    /**
     * Poll audio readiness cho luồng boot Box và phát ngay khi sẵn sàng.
     *
     * Tín hiệu "sẵn sàng" = xin được AudioFocus (loa/route đã hoạt động). Khi được, ta GIỮ focus
     * và phát luôn qua doPlayAudio(hadFocus=true) → không xin lại, không nhả phí.
     *
     * - Box warm restart: focus thường được cấp ngay vòng đầu (~2s) → phát nhanh.
     * - Box cold boot qua đêm: poll tới khi sẵn sàng; quá BOOT_READY_TIMEOUT_MS thì phát best-effort
     *   (KHÔNG chốt bootGreetingHandled) và để retry alarm lo tiếp → ổn định, tránh phát "ảo".
     */
    private fun startBootGreetingWatch() {
        cancelBootGreetingWatch()
        bootGreetingWatchStartedAtMs = SystemClock.elapsedRealtime()

        fun resolveBootPath(): String {
            val bootPath = getBootAudioPath("boot_greeting.mp3")
            return if (!bootPath.isNullOrEmpty()) bootPath else greetingAudioPath
        }

        bootGreetingWatchRunnable = object : Runnable {
            override fun run() {
                val sessionId = resolveBootSessionId()
                if (BootSessionManager.isSessionCompleted(this@AudioForegroundService, sessionId)) {
                    cancelBootGreetingWatch()
                    return
                }
                if (BootSessionManager.hasPlaybackStarted(this@AudioForegroundService, sessionId)) {
                    cancelBootGreetingWatch()
                    return
                }
                if (mediaPlayer?.isPlaying == true) {
                    cancelBootGreetingWatch()
                    return
                }

                val path = resolveBootPath()
                if (path.isEmpty()) {
                    HiCarDiagnosticLog.e("HiCarService", "Boot watch: no valid audio path found")
                    cancelBootGreetingWatch()
                    return
                }

                val elapsed = SystemClock.elapsedRealtime() - bootGreetingWatchStartedAtMs

                // Thăm dò readiness bằng audio focus (Box boot dùng GAIN riêng).
                if (requestBootAudioFocus()) {
                    HiCarDiagnosticLog.d("HiCarService", "Boot watch: audio ready sau ${elapsed}ms → phát ngay")
                    cancelBootGreetingWatch()
                    bootPlaybackUsesBootFocus = true
                    doPlayAudio(path, "greeting", isBootAutoPlay = true, hadFocus = true)
                    return
                }

                if (elapsed >= BOOT_READY_TIMEOUT_MS) {
                    HiCarDiagnosticLog.w(
                        "HiCarService",
                        "Boot watch: timeout ${BOOT_READY_TIMEOUT_MS}ms chưa có focus → phát best-effort (alarm retry nếu thất bại)"
                    )
                    cancelBootGreetingWatch()
                    bootPlaybackUsesBootFocus = false
                    doPlayAudio(path, "greeting", isBootAutoPlay = true, hadFocus = false)
                    return
                }

                handler.postDelayed(this, BOOT_POLL_INTERVAL_MS)
            }
        }
        HiCarDiagnosticLog.d("HiCarService", "Boot watch: bắt đầu poll readiness (start=${BOOT_POLL_START_MS}ms, interval=${BOOT_POLL_INTERVAL_MS}ms, timeout=${BOOT_READY_TIMEOUT_MS}ms)")
        handler.postDelayed(bootGreetingWatchRunnable!!, BOOT_POLL_START_MS)
    }

    private fun cancelBootGreetingWatch() {
        bootGreetingWatchRunnable?.let { handler.removeCallbacks(it) }
        bootGreetingWatchRunnable = null
        bootGreetingWatchStartedAtMs = 0L
    }

    private fun cancelDelayedPlay() {
        cancelBootGreetingWatch()
        delayedRunnable?.let { handler.removeCallbacks(it) }
        delayedRunnable = null
    }

    private fun playAudio(path: String, type: String, focusAttempt: Int = 0, isBootAutoPlay: Boolean = false) {
        if (focusAttempt == 0) HiCarDiagnosticLog.d("HiCarAudio", "playAudio called: type=$type, path=$path, bootAuto=$isBootAutoPlay")
        if (type == "greeting" && mediaPlayer?.isPlaying == true) {
            HiCarDiagnosticLog.d("HiCarAudio", "playAudio: greeting đang phát → bỏ qua")
            return
        }
        if (path.isEmpty()) {
            HiCarDiagnosticLog.e("HiCarAudio", "playAudio: path is EMPTY – nothing to play")
            return
        }
        if (!java.io.File(path).exists()) {
            HiCarDiagnosticLog.e("HiCarAudio", "playAudio: file does NOT exist at path=$path")
            return
        }

        val granted = requestAudioFocus()
        HiCarDiagnosticLog.d("HiCarAudio", "playAudio: audioFocus granted=$granted (attempt=$focusAttempt)")
        if (granted) {
            doPlayAudio(path, type, isBootAutoPlay, hadFocus = true)
            return
        }

        if (focusAttempt < MAX_FOCUS_ATTEMPTS) {
            HiCarDiagnosticLog.w("HiCarAudio", "playAudio: focus denied, retry ${focusAttempt + 1}/$MAX_FOCUS_ATTEMPTS in ${FOCUS_RETRY_MS}ms...")
            handler.postDelayed({ playAudio(path, type, focusAttempt + 1, isBootAutoPlay) }, FOCUS_RETRY_MS)
        } else {
            HiCarDiagnosticLog.w("HiCarAudio", "playAudio: focus vẫn bị từ chối sau $MAX_FOCUS_ATTEMPTS lần → phát best-effort (không focus)")
            doPlayAudio(path, type, isBootAutoPlay, hadFocus = false)
        }
    }

    private fun doPlayAudio(path: String, type: String, isBootAutoPlay: Boolean = false, hadFocus: Boolean = true) {
        loadPrefs()
        val isBoxBoot = isBootAutoPlay && connectionMode == "android_box_mode"

        if (!isBoxBoot) {
            completingBootSessionId = -1L
        } else {
            cancelBootCompletionFallback()
        }

        try {
            if (mediaPlayer == null) {
                mediaPlayer = MediaPlayer()
            } else {
                mediaPlayer?.reset()
            }

            mediaPlayer?.apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                setDataSource(path)
                setVolume(1.0f, 1.0f)

                setOnCompletionListener {
                    // Phát TRỌN VẸN tới cuối file = đã phát thật (audio focus chỉ mang tính
                    // hợp tác — không có focus vẫn ra tiếng nếu pipeline hoạt động) → chốt
                    // phiên boot + hủy alarm retry để KHÔNG phát lặp lần hai.
                    // Trường hợp pipeline hỏng thật sẽ rơi vào onError/stall, không vào đây.
                    if (isBoxBoot) {
                        completeBootSessionIfNeeded("onCompletion")
                    }
                    if (isBoxBoot && bootPlaybackUsesBootFocus) {
                        releaseBootAudioFocus()
                        bootPlaybackUsesBootFocus = false
                    } else if (!isBoxBoot) {
                        releaseAudioFocus()
                    }
                    updatePlaybackState(PlaybackStateCompat.STATE_STOPPED)
                    mediaPlayer?.release()
                    mediaPlayer = null
                }

                setOnErrorListener { _, what, extra ->
                    HiCarDiagnosticLog.e("HiCarAudio", "MediaPlayer error what=$what extra=$extra")
                    if (isBoxBoot) {
                        // Boot bị LỖI giữa chừng: marker "đã phát" + alarm retry có thể đã bị
                        // hủy lúc start() → nếu không mở lại, boot này sẽ im lặng luôn.
                        // Chỉ mở lại 1 lần/phiên để tránh loop lỗi vô hạn.
                        val ctx = this@AudioForegroundService
                        val sessionId = completingBootSessionId.takeIf { it > 0L }
                            ?: resolveBootSessionId()
                        if (sessionId > 0L &&
                            !BootSessionManager.isSessionCompleted(ctx, sessionId) &&
                            bootErrorRetryScheduledForSession != sessionId
                        ) {
                            bootErrorRetryScheduledForSession = sessionId
                            bootGreetingHandled = false
                            BootSessionManager.clearPlaybackStarted(ctx, sessionId)
                            BootReceiver.scheduleBootRetryAlarms(ctx)
                            HiCarDiagnosticLog.w(
                                "HiCarService",
                                "Boot playback error → mở lại alarm retry cho session $sessionId"
                            )
                        }
                    }
                    if (isBoxBoot && bootPlaybackUsesBootFocus) {
                        releaseBootAudioFocus()
                        bootPlaybackUsesBootFocus = false
                    } else {
                        releaseAudioFocus()
                    }
                    updatePlaybackState(PlaybackStateCompat.STATE_ERROR)
                    OverlayBridge.notifyPlaybackComplete()
                    true
                }

                prepare()
                val durationMs = duration.toLong().coerceAtLeast(0L)

                if (isBoxBoot) {
                    completingBootSessionId = resolveBootSessionId()
                    bootPlaybackDurationMs = durationMs
                }

                start()

                if (type == "greeting") {
                    if (isBoxBoot) {
                        bootPlaybackStartedAtMs = SystemClock.elapsedRealtime()
                        onBoxBootPlaybackStarted(completingBootSessionId, hadFocus)
                        // Chỉ hẹn "chốt theo thời lượng đã phát" khi phát thật (có focus).
                        if (hadFocus) scheduleBootCompletionFallback(durationMs)
                        if (hadFocus) {
                            HiCarDiagnosticLog.d(
                                "HiCarService",
                                "Box boot greeting started (focus granted) → chờ onCompletion/fallback"
                            )
                        } else {
                            HiCarDiagnosticLog.d(
                                "HiCarService",
                                "Box boot greeting started best-effort → chờ onCompletion/fallback"
                            )
                        }
                    }
                    if (connectionMode == "phone_android_auto" && pendingAaAutoGreeting) {
                        aaGreetingPlayedThisConnection = true
                        pendingAaAutoGreeting = false
                        Log.d("HiCarAA", "AA auto-greeting started → session flag set")
                    }
                }

                HiCarDiagnosticLog.d("HiCarAudio", "playAudio OK: type=$type started")
                if (type == "greeting") {
                    updatePlaybackState(PlaybackStateCompat.STATE_PLAYING)
                } else if (type == "goodbye") {
                    updatePlaybackState(PlaybackStateCompat.STATE_SKIPPING_TO_NEXT)
                }

                HiCarPlugin.instance?.invokeServiceMethod("onPlaybackStarted", type)
                OverlayBridge.notifyPlaybackStarted(type)
            }
        } catch (e: Exception) {
            HiCarDiagnosticLog.e("HiCarAudio", "Error playing audio: ${e.message}")
            if (isBoxBoot && bootPlaybackUsesBootFocus) {
                releaseBootAudioFocus()
                bootPlaybackUsesBootFocus = false
            } else {
                releaseAudioFocus()
            }
            updatePlaybackState(PlaybackStateCompat.STATE_ERROR)
            OverlayBridge.notifyPlaybackComplete()
        }
    }

    private fun stopPlayback(releaseOnly: Boolean = false) {
        maybeCompleteBootSessionOnInterrupt()
        cancelBootCompletionFallback()
        cancelDelayedPlay()
        pendingAaAutoGreeting = false
        mediaPlayer?.let {
            try {
                if (it.isPlaying) it.stop()
                it.reset()
                it.release()
            } catch (_: Exception) {}
        }
        mediaPlayer = null
        if (!releaseOnly) {
            if (bootPlaybackUsesBootFocus) {
                releaseBootAudioFocus()
                bootPlaybackUsesBootFocus = false
            } else {
                releaseAudioFocus()
            }
            updatePlaybackState(PlaybackStateCompat.STATE_STOPPED)
        }
    }

    // ==============================
    // Audio Focus
    // ==============================

    private fun buildAudioFocusRequest() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // 🟢 DÙNG AUDIOFOCUS_GAIN_TRANSIENT: Để tạm dừng nhạc khác hoàn toàn thay vì chỉ giảm âm lượng (ducking)
            // Giúp âm thanh Bluetooth ổn định hơn trên một số đầu giải trí xe hơi
            audioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                .setOnAudioFocusChangeListener { change ->
                    when (change) {
                        AudioManager.AUDIOFOCUS_LOSS -> {
                            Log.d("HiCarAudio", "Focus Loss (-1)")
                            stopPlayback()
                        }
                        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                            Log.d("HiCarAudio", "Focus Loss Transient (-2)")
                            mediaPlayer?.pause()
                        }
                        AudioManager.AUDIOFOCUS_GAIN -> {
                            Log.d("HiCarAudio", "Focus Gain (1)")
                            mediaPlayer?.start()
                        }
                    }
                }
                .build()
        }
    }

    /** Audio focus riêng cho Box boot greeting (GAIN, không ảnh hưởng BT/AA). */
    private fun buildBootAudioFocusRequest() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            bootAudioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                .setOnAudioFocusChangeListener { change ->
                    loadPrefs()
                    if (connectionMode != "android_box_mode" || completingBootSessionId <= 0L) return@setOnAudioFocusChangeListener
                    when (change) {
                        AudioManager.AUDIOFOCUS_LOSS -> {
                            Log.d("HiCarAudio", "Boot focus Loss (-1)")
                            maybeCompleteBootSessionOnInterrupt()
                            stopPlayback(releaseOnly = false)
                        }
                        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                            Log.d("HiCarAudio", "Boot focus Loss Transient (-2)")
                            mediaPlayer?.pause()
                        }
                        AudioManager.AUDIOFOCUS_GAIN -> {
                            Log.d("HiCarAudio", "Boot focus Gain (1)")
                            mediaPlayer?.start()
                        }
                    }
                }
                .build()
        }
    }

    private fun requestBootAudioFocus(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            bootAudioFocusRequest?.let {
                audioManager?.requestAudioFocus(it) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            } ?: false
        } else {
            @Suppress("DEPRECATION")
            audioManager?.requestAudioFocus(
                null,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN
            ) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        }
    }

    private fun releaseBootAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            bootAudioFocusRequest?.let { audioManager?.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            audioManager?.abandonAudioFocus(null)
        }
    }

    private fun requestAudioFocus(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let {
                audioManager?.requestAudioFocus(it) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            } ?: false
        } else {
            @Suppress("DEPRECATION")
            audioManager?.requestAudioFocus(
                null,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT
            ) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        }
    }

    private fun releaseAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { audioManager?.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            audioManager?.abandonAudioFocus(null)
        }
    }

    // ==============================
    // MediaSession
    // ==============================

    private fun setupMediaSession() {
        mediaSession = MediaSessionCompat(this, "HiCarSession").apply {
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() { /* handled externally */ }
                override fun onPause() { stopPlayback() }
                override fun onStop() { stopPlayback() }
            })
        }
        // 🟢 QUAN TRỌNG: Chỉ set sessionToken 1 lần duy nhất trong vòng đời Service
        sessionToken = mediaSession?.sessionToken
        updateMediaSessionState()
    }

    private fun updateMediaSessionState() {
        mediaSession?.let { session ->
            // Chỉ chỉnh trạng thái Active thay vì thay đổi Token (tránh lỗi crash)
            session.isActive = (connectionMode == "phone_android_auto")
        }
    }

    private fun updatePlaybackState(state: Int) {
        val playbackState = PlaybackStateCompat.Builder()
            .setState(state, PlaybackStateCompat.PLAYBACK_POSITION_UNKNOWN, 1f)
            .setActions(
                PlaybackStateCompat.ACTION_PLAY_PAUSE or
                        PlaybackStateCompat.ACTION_STOP
            )
            .build()
        mediaSession?.setPlaybackState(playbackState)

        // Notify Flutter when playback completes via Plugin
        if (state == PlaybackStateCompat.STATE_STOPPED) {
            // isManual=true khi dừng do người dùng bấm STOP → Flutter không minimize app
            // (chế độ Màn Độ). Tiêu thụ cờ 1 lần rồi reset để lần phát xong tự nhiên tiếp theo
            // vẫn được coi là auto-complete.
            val manual = userInitiatedStop
            userInitiatedStop = false
            // Loại bỏ độ trễ 1s để UI cập nhật tức thì, tránh bị nháy khi phát bản tiếp theo
            HiCarPlugin.instance?.invokeServiceMethod("onPlaybackComplete", manual)
            OverlayBridge.notifyPlaybackComplete()
        }
    }

    // ==============================
    // Notification
    // ==============================

    private fun setupNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Giọng Thương Gia",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Automotive background audio service"
                setSound(null, null)
                enableVibration(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        // ⚠️ Direct Boot (trước khi unlock): getLaunchIntentForPackage() trả về null vì
        //    PackageManager chưa resolve được launcher activity cho user đang khóa. Khi đó
        //    PendingIntent bọc Intent null → startForeground ném NPE (Intent.resolveTypeIfNeeded).
        //    → Dùng Intent tường minh tới MainActivity làm fallback để luôn có Intent hợp lệ.
        val launchIntent = packageManager?.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java).apply {
                action = Intent.ACTION_MAIN
                addCategory(Intent.CATEGORY_LAUNCHER)
            }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("Giọng Thương Gia")
            .setContentText("Hệ thống trợ lý xe đang hoạt động")
            .setSmallIcon(R.drawable.ic_car)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    // ==============================
    // WakeLock
    // ==============================

    private fun acquireWakeLock() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "HiCar::AudioServiceWakeLock"
        ).apply {
            acquire(10 * 60 * 60 * 1000L) // Max 10 hours
        }
    }
}