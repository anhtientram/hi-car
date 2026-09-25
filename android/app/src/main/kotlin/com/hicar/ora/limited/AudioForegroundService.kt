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
        @Volatile var instance: AudioForegroundService? = null
            private set
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

        // Retry xin audio focus theo chu kỳ; không chốt fail chỉ vì head unit/OS cũ phản hồi chậm.
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
        private const val ROUTE_WAIT_LOG_INTERVAL_MS = 10_000L

        // 🟢 BOOT READINESS POLL (Box): thay vì CHỜ CỨNG 8s rồi mới phát, ta thăm dò audio
        //    subsystem sớm và PHÁT NGAY khi sẵn sàng → box warm-restart phát sau ~2s thay vì 8s.
        //    - Bắt đầu thăm dò sau BOOT_POLL_START_MS (cho service + audio init kịp tối thiểu).
        //    - Playback job đợi focus qua FOCUS_RETRY_MS rồi chuẩn bị player.
        //    - Nếu chưa được thì tiếp tục poll; alarm chỉ là đường dự phòng khi process bị kill.
        private const val BOOT_POLL_START_MS = 2_000L
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
    }

    private var mediaPlayer: MediaPlayer? = null
    @Volatile private var mediaPlayerPrepared: Boolean = false
    private var mediaSession: MediaSessionCompat? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var audioManager: AudioManager? = null
    private val handler = Handler(Looper.getMainLooper())
    private var delayedRunnable: Runnable? = null
    private var pendingFocusPlaybackRunnable: Runnable? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var focusRecoveryRunnable: Runnable? = null

    // CarConnection (Android Auto) observer + trạng thái gần nhất.
    private var carConnectionObserver: ContentObserver? = null
    private var carConnectionReceiver: android.content.BroadcastReceiver? = null
    private val connectionExecutor = java.util.concurrent.Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "HiCarCarConnection").apply { isDaemon = true }
    }
    private var carQueryPending = false
    private var cachedCarConnectionState = -1
    private var lastCarQueryAt = 0L
    private var lastCarQueryWarningAt = 0L
    @Volatile private var lastCarConnectionState: Int = CAR_CONNECTION_NOT_CONNECTED
    private var aaProjectionWatchRunnable: Runnable? = null
    private var aaProjectionWatchStartedAtMs: Long = 0L
    private var btA2dpWatchRunnable: Runnable? = null
    private var btA2dpWatchStartedAtMs: Long = 0L
    private var btA2dpWatchAddress: String = ""
    private var bootGreetingWatchRunnable: Runnable? = null
    private var activeBootSessionId: Long = -1L
    private var bootMissWatchdogRunnable: Runnable? = null
    private var bootMissWatchdogScheduledForSession: Long = -1L
    private var completingBootSessionId: Long = -1L
    private var bootPlaybackEverStartedForSession: Long = -1L
    private var bootAudioFocusRequest: AudioFocusRequest? = null

    // ==============================
    // Lifecycle
    // ==============================

    override fun onCreate() {
        instance = this
        bootGreetingHandled = false
        aaGreetingPlayedThisConnection = false
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
            // Start monitoring only after startForeground (Android 15 focus rules).
            
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
                HiCarDiagnosticLog.w("HiCarService", "loadPrefs: credential storage không đọc được – ${e.message}")
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
        if (greetingAudioPath.isEmpty() || !AudioFileValidator.isUsable(File(greetingAudioPath))) {
            getBootAudioPath("boot_greeting.mp3")?.let {
                greetingAudioPath = it
            }
        }
        
        if (goodbyeAudioPath.isEmpty() || !AudioFileValidator.isUsable(File(goodbyeAudioPath))) {
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
            refreshConfiguration()
            if (carConnectionObserver == null) setupCarConnectionMonitor()
        } catch (e: Exception) {
            HiCarDiagnosticLog.e("HiCarService", "Error in onStartCommand: ${e.message}")
            // Even if it fails, we must call startForeground on Android 8+ to avoid ANR/Crash
            try {
                startForegroundCompat(fromBoot)
            } catch (e2: Exception) {
                HiCarDiagnosticLog.e("HiCarService", "FGS_START_DENIED mode=$connectionMode api=${Build.VERSION.SDK_INT} ${e2.stackTraceToString()}")
                HiCarPlugin.instance?.invokeServiceMethod("onNativeError", "FGS_START_DENIED mode=$connectionMode ${e2.message}")
                stopSelf()
                return START_NOT_STICKY
            }
        }

        val requestedSession = intent?.getLongExtra(EXTRA_BOOT_SESSION_ID, -1L) ?: -1L
        if (fromBoot && (connectionMode != "android_box_mode" ||
                (requestedSession > 0L && requestedSession != BootSessionManager.getCurrentSession(this)))) {
            HiCarDiagnosticLog.w("HiCarService", "Ignored stale boot action mode=$connectionMode session=$requestedSession")
            return START_STICKY
        }

        when (intent?.action) {
            ACTION_START -> { /* Keep alive */ }
            ACTION_STOP -> { stopPlayback(); stopSelf() }

            ACTION_PLAY_GREETING -> {
                pendingAutomatic = intent.getBooleanExtra("automatic", false)
                val path = if (intent.getBooleanExtra(EXTRA_PREFER_BOOT_AUDIO, false)) {
                    getBootAudioPath("boot_greeting.mp3") ?: greetingAudioPath
                } else {
                    intent.getStringExtra("audioPath") ?: greetingAudioPath
                }
                playAudio(path.ifEmpty { greetingAudioPath }, "greeting")
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
            ACTION_STOP_AUDIO -> stopPlayback()
            ACTION_BLUETOOTH_DISCONNECTED -> {
                loadPrefs()
                if (connectionMode != "phone_bluetooth") return START_STICKY
                btGreetingHandled = false
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
                    if (aaGreetingPlayedThisConnection || pendingAaAutoGreeting || aaProjectionWatchRunnable != null) return START_STICKY
                    HiCarDiagnosticLog.d("HiCarAA", "BT connected (AA mode) → bắt đầu watch projection")
                    startAaProjectionWatch()
                }
            }
            ACTION_BT_WATCH_A2DP -> {
                loadPrefs()
                val address = intent.getStringExtra("deviceAddress") ?: targetDeviceAddress
                if (connectionMode == "phone_bluetooth" && autoPlayEnabled && address.isNotEmpty()) {
                    if (btGreetingHandled || btA2dpWatchRunnable != null) return START_STICKY
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

        if (intent == null || action == ACTION_START) restorePendingBoot()

        return START_STICKY
    }

    private var btGreetingHandled = false

    fun refreshConfiguration() {
        loadPrefs()
        if (connectionMode != "phone_bluetooth" || !autoPlayEnabled) {
            cancelBtA2dpWatch()
            btGreetingHandled = false
        }
        if (connectionMode != "phone_android_auto" || !autoPlayEnabled) {
            cancelAaProjectionWatch()
            aaGreetingPlayedThisConnection = false
        }
        if (connectionMode != "android_box_mode" || !autoPlayEnabled) {
            cancelBootGreetingWatch()
            cancelBootMissWatchdog()
            BootSessionManager.cancelBootRetryAlarms(this)
        }
        playbackJob?.let { if (!jobIsValid(it) && !it.cancelled) stopPlayback() }
    }

    private fun restorePendingBoot() {
        if (connectionMode != "android_box_mode" || !autoPlayEnabled) return
        val session = BootSessionManager.getCurrentSession(this)
        if (session <= 0 || BootSessionManager.isSessionCompleted(this, session) ||
            BootSessionManager.isSessionFailed(this, session)) return
        activeBootSessionId = session
        BootSessionManager.clearPlaybackStarted(this, session)
        triggerGreetingDebounced(true, "sticky_restart")
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
            if (carConnectionReceiver == null) {
                val receiver = object : android.content.BroadcastReceiver() {
                    override fun onReceive(context: Context, intent: Intent) {
                        // Broadcast is a notification only. Query the provider; never trust extras.
                        lastCarQueryAt = 0L
                        queryCarConnectionType()
                    }
                }
                androidx.core.content.ContextCompat.registerReceiver(this, receiver,
                    android.content.IntentFilter("androidx.car.app.connection.action.CAR_CONNECTION_UPDATED"),
                    androidx.core.content.ContextCompat.RECEIVER_EXPORTED)
                carConnectionReceiver = receiver
            }
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
            HiCarDiagnosticLog.d("HiCarAA", "CarConnection monitor registered")
        } catch (e: Exception) {
            HiCarDiagnosticLog.w("HiCarAA", "setupCarConnectionMonitor failed: ${e.message}")
        }
    }

    /** The AA provider may be slow/broken on vendor ROMs. Never do its Binder query on main. */
    private fun queryCarConnectionType(): Int {
        val now = SystemClock.elapsedRealtime()
        if (!carQueryPending && now - lastCarQueryAt >= 500L && !connectionExecutor.isShutdown) {
            carQueryPending = true
            lastCarQueryAt = now
            connectionExecutor.execute {
                var warning: String? = null
                val state = try {
                    contentResolver.query(Uri.parse("content://$CAR_CONNECTION_AUTHORITY"),
                        arrayOf(CAR_CONNECTION_STATE_COLUMN), null, null, null)?.use { cursor ->
                        val index = cursor.getColumnIndex(CAR_CONNECTION_STATE_COLUMN)
                        if (index >= 0 && cursor.moveToFirst()) cursor.getInt(index) else -1
                    } ?: -1
                } catch (e: Exception) {
                    warning = e.toString()
                    -1
                }
                handler.post {
                    if (instance !== this) return@post
                    carQueryPending = false
                    cachedCarConnectionState = state
                    if (state >= 0) handleCarConnectionState(state)
                    else if (connectionMode == "phone_android_auto" &&
                        SystemClock.elapsedRealtime() - lastCarQueryWarningAt > ROUTE_WAIT_LOG_INTERVAL_MS) {
                        lastCarQueryWarningAt = SystemClock.elapsedRealtime()
                        HiCarDiagnosticLog.w("HiCarAA", "mode=phone_android_auto CarConnection unavailable; waiting reason=$warning")
                    }
                }
            }
        }
        return cachedCarConnectionState
    }

    private fun triggerAaGreetingOnce(source: String) {
        cancelAaProjectionWatch()
        lastCarConnectionState = CAR_CONNECTION_PROJECTION
        loadPrefs()
        if (connectionMode != "phone_android_auto" || !autoPlayEnabled) return
        HiCarDiagnosticLog.d("HiCarAA", "AA ready ($source) → trigger greeting")
        triggerGreetingDebounced(useBootAudio = false, source = source)
    }

    /** Poll CarConnection khi ContentObserver không báo (một số máy/AA không dây). */
    private fun startAaProjectionWatch() {
        cancelAaProjectionWatch()
        aaProjectionWatchStartedAtMs = SystemClock.elapsedRealtime()
        var lastWaitLogAtMs = 0L
        HiCarDiagnosticLog.d("HiCarAA", "AA projection watch started (timeout=none)")
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
                    HiCarDiagnosticLog.d("HiCarAA", "AA projection watch: PROJECTION detected")
                    triggerAaGreetingOnce("carconnection_poll")
                    return
                }
                // A visible gearhead process alone does not prove projection/audio routing.
                if (elapsed - lastWaitLogAtMs >= ROUTE_WAIT_LOG_INTERVAL_MS) {
                    lastWaitLogAtMs = elapsed
                    HiCarDiagnosticLog.w(
                        "HiCarAA",
                        "AA projection chưa sẵn sàng; tiếp tục chờ elapsed=${elapsed}ms state=$state"
                    )
                }
                handler.postDelayed(this, AA_PROJECTION_POLL_MS)
            }
        }
        handler.post(aaProjectionWatchRunnable!!)
    }

    private fun cancelAaProjectionWatch() {
        if (aaProjectionWatchRunnable != null) {
            HiCarDiagnosticLog.d("HiCarAA", "AA projection watch cancelled")
        }
        aaProjectionWatchRunnable?.let { handler.removeCallbacks(it) }
        aaProjectionWatchRunnable = null
        aaProjectionWatchStartedAtMs = 0L
    }

    /** Poll A2DP profile cho đến khi màn hình xe sẵn sàng nhận audio. */
    private fun startBtA2dpWatch(address: String) {
        cancelBtA2dpWatch()
        btA2dpWatchAddress = address
        btA2dpWatchStartedAtMs = SystemClock.elapsedRealtime()
        var lastWaitLogAtMs = 0L
        HiCarDiagnosticLog.d("HiCarBT", "A2DP watch started address=$address (timeout=none)")
        btA2dpWatchRunnable = object : Runnable {
            override fun run() {
                loadPrefs()
                if (connectionMode != "phone_bluetooth" || !autoPlayEnabled ||
                    !address.equals(targetDeviceAddress, true)) {
                    cancelBtA2dpWatch()
                    return
                }
                val elapsed = SystemClock.elapsedRealtime() - btA2dpWatchStartedAtMs
                if (BluetoothReceiver.isA2dpConnected(this@AudioForegroundService, address)) {
                    HiCarDiagnosticLog.d("HiCarBT", "A2DP ready after ${elapsed}ms → trigger greeting (loa xe đã sẵn sàng)")
                    cancelBtA2dpWatch()
                    btGreetingHandled = true
                    triggerGreetingDebounced(useBootAudio = false, source = "a2dp_ready")
                    return
                }
                if (elapsed - lastWaitLogAtMs >= ROUTE_WAIT_LOG_INTERVAL_MS) {
                    lastWaitLogAtMs = elapsed
                    HiCarDiagnosticLog.w(
                        "HiCarBT",
                        "A2DP chưa sẵn sàng; tiếp tục chờ elapsed=${elapsed}ms address=$address"
                    )
                }
                handler.postDelayed(this, BT_A2DP_POLL_MS)
            }
        }
        handler.post(btA2dpWatchRunnable!!)
    }

    private fun cancelBtA2dpWatch() {
        if (btA2dpWatchRunnable != null) {
            HiCarDiagnosticLog.d("HiCarBT", "A2DP watch cancelled address=$btA2dpWatchAddress")
        }
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
            bootPlaybackEverStartedForSession = -1L
            cancelBootMissWatchdog()
            bootMissWatchdogScheduledForSession = -1L
            HiCarDiagnosticLog.d("HiCarService", "Active boot session → $activeBootSessionId")
        }
    }

    private fun resolveBootSessionId(): Long {
        if (activeBootSessionId > 0L) return activeBootSessionId
        return BootSessionManager.getCurrentSession(this)
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
            if (connectionMode != "android_box_mode" || !autoPlayEnabled) return@Runnable
            if (!BootSessionManager.isSessionCompleted(this, sessionId) && !BootSessionManager.isSessionFailed(this, sessionId)) {
                if (bootGreetingWatchRunnable != null || playbackJob?.state in setOf("preparing", "playing", "retrying", "waiting_focus", "waiting_route")) {
                    // Route/focus vẫn đang được chờ hợp lệ. Đây chưa phải incident bị hủy;
                    // dời health check để không hiện popup giả cho box chậm.
                    HiCarDiagnosticLog.w(
                        "HiCarService",
                        "Boot miss watchdog: session=$sessionId vẫn đang chờ readiness → gia hạn"
                    )
                    bootMissWatchdogScheduledForSession = -1L
                    scheduleBootMissWatchdogIfNeeded()
                    return@Runnable
                }
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
        bootMissWatchdogScheduledForSession = -1L
    }

    /** Started is a checkpoint, never proof of completion. Keep restart alarms until completion. */
    private fun onBoxBootPlaybackStarted(sessionId: Long, hadFocus: Boolean) {
        if (sessionId <= 0L || !hadFocus) return
        bootGreetingHandled = true
        bootPlaybackEverStartedForSession = sessionId
        if (!BootSessionManager.hasPlaybackStarted(this, sessionId)) {
            BootSessionManager.markPlaybackStarted(this, sessionId)
            HiCarDiagnosticLog.d("HiCarService", "Box started session=$sessionId; recovery alarms retained")
        }
    }

    private fun tryTriggerAaIfProjected(source: String) {
        when {
            queryCarConnectionType() == CAR_CONNECTION_PROJECTION ->
                triggerAaGreetingOnce(source)
            else ->
                HiCarDiagnosticLog.d("HiCarAA", "tryTriggerAaIfProjected($source): chưa sẵn sàng")
        }
    }

    private fun handleCarConnectionState(state: Int) {
        if (state < 0) return
        val previous = lastCarConnectionState
        lastCarConnectionState = state
        if (state == previous) return
        HiCarDiagnosticLog.d("HiCarAA", "CarConnection state: $previous → $state")

        when (state) {
            CAR_CONNECTION_PROJECTION -> {
                loadPrefs()
                if (connectionMode == "phone_android_auto" && autoPlayEnabled) {
                    HiCarDiagnosticLog.d("HiCarAA", "Projection started → trigger greeting")
                    triggerAaGreetingOnce("carconnection_observer")
                } else {
                    HiCarDiagnosticLog.d("HiCarAA", "Projection started but mode=$connectionMode, autoPlay=$autoPlayEnabled → skip")
                }
            }
            CAR_CONNECTION_NOT_CONNECTED -> {
                loadPrefs()
                if (connectionMode == "phone_android_auto") {
                    HiCarDiagnosticLog.d("HiCarAA", "Projection ended → stop playback")
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
            if (BootSessionManager.isSessionFailed(this, sessionId)) return
            if (playbackJob?.bootSession == sessionId && playbackJob?.state !in setOf("completed", "failed", "cancelled")) return
            if (BootSessionManager.isSessionCompleted(this, sessionId)) {
                HiCarDiagnosticLog.d(
                    "HiCarService",
                    "Boot greeting ($source) bỏ qua – session $sessionId đã hoàn tất"
                )
                return
            }
            // Persisted start alone is not completion. A new process resumes its checkpoint.
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
                HiCarDiagnosticLog.d("HiCarService", "AA greeting ($source) bỏ qua – đã phát trong phiên kết nối này")
                return
            }
        }

        val now = SystemClock.elapsedRealtime()
        val elapsed = now - lastGreetingTriggerAtMs
        if (lastGreetingTriggerAtMs != 0L && elapsed < GREETING_DEDUP_WINDOW_MS) {
            HiCarDiagnosticLog.d("HiCarService", "Greeting trigger ($source) bỏ qua – trùng trong ${elapsed}ms")
            return
        }
        lastGreetingTriggerAtMs = now

        if (connectionMode == "phone_android_auto") {
            pendingAaAutoGreeting = true
        }

        HiCarDiagnosticLog.d("HiCarService", "Greeting trigger ($source) → scheduleDelayedGreeting")
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
        val storageContext = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            applicationContext.createDeviceProtectedStorageContext()
        } else applicationContext
        val bootAudio = File(storageContext.filesDir, fileName)
        val result = if (AudioFileValidator.isUsable(bootAudio)) bootAudio.absolutePath else null
        Log.d("HiCarAudio", "getBootAudioPath($fileName): exists=${bootAudio.exists()}, size=${if (bootAudio.exists()) bootAudio.length() else 0}, path=${bootAudio.absolutePath}")
        return result
    }

    override fun onDestroy() {
        instance = null
        BluetoothReceiver.releaseProfile(this)
        stopPlayback(releaseOnly = true, preserveBootForRestart = true)
        mediaSession?.release()
        wakeLock?.let { if (it.isHeld) it.release() }
        carConnectionObserver?.let {
            try { contentResolver.unregisterContentObserver(it) } catch (_: Exception) {}
        }
        carConnectionObserver = null
        carConnectionReceiver?.let { try { unregisterReceiver(it) } catch (_: Exception) {} }
        carConnectionReceiver = null
        connectionExecutor.shutdownNow()
        cancelAaProjectionWatch()
        cancelBtA2dpWatch()
        cancelBootGreetingWatch()
        cancelBootMissWatchdog()
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        // Auto-restart when app is swiped away
        val restartIntent = Intent(applicationContext, AudioForegroundService::class.java).apply {
            action = ACTION_START
        }
        val flags = PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
        val pending = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            PendingIntent.getForegroundService(applicationContext, 1, restartIntent, flags)
        } else PendingIntent.getService(applicationContext, 1, restartIntent, flags)
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
        HiCarDiagnosticLog.d("HiCarAA", "onGetRoot called by: $clientPackageName")
        
        // 🟢 ẨN APP KHỎI MÀN HÌNH XE NẾU KHÔNG PHẢI MODE ANDROID AUTO
        if (connectionMode != "phone_android_auto") {
            HiCarDiagnosticLog.d("HiCarAA", "Not in AA mode, returning null")
            return null
        }

        // Nếu là Android Auto (gearhead), kích hoạt phát lời chào. Đi qua debounce chung để
        // KHÔNG phát đôi khi CarConnection/Bluetooth đã trigger cùng đợt kết nối.
        if (clientPackageName.contains("gearhead") || clientPackageName.contains("com.google.android.projection.gearhead")) {
            if (autoPlayEnabled) {
                HiCarDiagnosticLog.d("HiCarAA", "Android Auto bound (onGetRoot) → trigger greeting")
                try {
                    startForegroundCompat(false)
                    if (carConnectionObserver == null) setupCarConnectionMonitor()
                    startAaProjectionWatch()
                } catch (e: Exception) {
                    HiCarDiagnosticLog.e("HiCarAA", "AA foreground start rejected: ${e.stackTraceToString()}")
                }
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

        val scheduledMode = connectionMode
        delayedRunnable = Runnable {
            loadPrefs()
            if (!autoPlayEnabled || connectionMode != scheduledMode) return@Runnable
            if (mediaPlayer?.isPlaying == true) {
                HiCarDiagnosticLog.d("HiCarService", "scheduleDelayedGreeting: đang phát → bỏ qua")
                return@Runnable
            }
            val path = greetingAudioPath
            if (path.isNotEmpty()) {
                pendingAutomatic = true
                playAudio(path, "greeting", isBootAutoPlay = false)
            } else {
                val message = "mode=$connectionMode FILE_INVALID no configured greeting audio"
                HiCarDiagnosticLog.e("HiCarService", message)
                HiCarPlugin.instance?.invokeServiceMethod("onNativeError", message)
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

    /** Hand boot ownership to the common job after the initial startup grace period.
     * Route/focus retry then uses the same cancellation and error policy as other modes. */
    private fun startBootGreetingWatch() {
        cancelBootGreetingWatch()
        val session = resolveBootSessionId()
        bootGreetingWatchRunnable = Runnable {
            bootGreetingWatchRunnable = null
            loadPrefs()
            if (connectionMode != "android_box_mode" || !autoPlayEnabled ||
                BootSessionManager.isSessionCompleted(this, session) ||
                BootSessionManager.isSessionFailed(this, session)) return@Runnable
            playAudio(getBootAudioPath("boot_greeting.mp3") ?: greetingAudioPath, "greeting",
                isBootAutoPlay = true)
        }
        handler.postDelayed(bootGreetingWatchRunnable!!, BOOT_POLL_START_MS)
    }

    private fun cancelBootGreetingWatch() {
        bootGreetingWatchRunnable?.let { handler.removeCallbacks(it) }
        bootGreetingWatchRunnable = null
    }

    private fun cancelDelayedPlay() {
        cancelPendingFocusPlayback()
        cancelBootGreetingWatch()
        delayedRunnable?.let { handler.removeCallbacks(it) }
        delayedRunnable = null
    }

    private var playbackJob: PlaybackJob? = null
    private var playerHealthCheck: Runnable? = null
    private var playerRetry: Runnable? = null
    private var focusHeld = false
    private var pendingAutomatic = false
    private var jobSequence = 0L
    private var lastPlaybackWaitLog = 0L

    fun playbackStatus(): Map<String, Any> = mapOf(
        "jobId" to (playbackJob?.id ?: ""),
        "state" to (playbackJob?.state ?: "idle"),
        "type" to (playbackJob?.type ?: ""),
        "positionMs" to (playbackJob?.positionMs ?: 0),
        "durationMs" to (playbackJob?.durationMs ?: 0)
    )

    private fun audioSnapshot(): String {
        return try {
            val routes = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                audioManager?.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                    ?.joinToString(",") { "${it.id}:${it.type}" } ?: "unknown"
            } else "legacy"
            "api=${Build.VERSION.SDK_INT} model=${Build.MANUFACTURER}/${Build.MODEL} " +
                "routes=[$routes] focus=$focusHeld volume=${audioManager?.getStreamVolume(AudioManager.STREAM_MUSIC)}"
        } catch (e: Exception) { "snapshot_error=${e.javaClass.simpleName}:${e.message}" }
    }

    private fun jobLog(job: PlaybackJob, event: String, error: Boolean = false) {
        val message = "job=${job.id} mode=${job.mode} state=${job.state} " +
            "attempt=${job.attempt} retry=${job.retries} position=${job.positionMs}/${job.durationMs} " +
            "type=${job.type} boot=${job.bootSession > 0} $event"
        if (error) HiCarDiagnosticLog.e("HiCarAudio", "$message ${audioSnapshot()}")
        else HiCarDiagnosticLog.d("HiCarAudio", message)
    }

    private fun jobIsValid(job: PlaybackJob): Boolean {
        loadPrefs()
        val prefs = availablePlaybackPrefs()
        return playbackJob === job && job.valid(
            connectionMode, autoPlayEnabled,
            !prefs.getString("flutter.auth_token", "").isNullOrEmpty(), targetDeviceAddress
        )
    }

    private fun availablePlaybackPrefs(): android.content.SharedPreferences {
        val locked = Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
            (getSystemService(Context.USER_SERVICE) as? UserManager)?.isUserUnlocked != true
        val ctx = if (locked) createDeviceProtectedStorageContext() else this
        return ctx.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    }

    private fun playAudio(path: String, type: String, isBootAutoPlay: Boolean = false) {
        loadPrefs()
        val automatic = isBootAutoPlay || pendingAutomatic
        pendingAutomatic = false
        val current = playbackJob
        if (type == "greeting" && current != null && current.type == type &&
            current.path == path && jobIsValid(current) &&
            current.state !in setOf("failed", "completed", "cancelled")) {
            jobLog(current, "duplicate_trigger_ignored")
            return
        }
        stopPlayback(releaseOnly = true)
        val job = PlaybackJob(
            "${android.os.Process.myPid()}-${SystemClock.elapsedRealtime()}-${++jobSequence}",
            connectionMode, path, type, automatic,
            if (isBootAutoPlay) resolveBootSessionId() else -1L, targetDeviceAddress
        )
        playbackJob = job
        if (job.bootSession > 0) {
            job.positionMs = BootSessionManager.playbackPosition(this, job.bootSession)
        }
        jobLog(job, "trigger path=$path bytes=${File(path).let { if (it.exists()) it.length() else 0 }} ${audioSnapshot()}")
        HiCarPlugin.instance?.invokeServiceMethod("onPlaybackPending", type)
        attemptPlayback(job)
    }

    private fun routeReady(job: PlaybackJob): Boolean {
        if (!job.automatic) return true
        return when (job.mode) {
            "phone_bluetooth" -> BluetoothReceiver.isA2dpConnected(this, job.target)
            "phone_android_auto" -> queryCarConnectionType() == CAR_CONNECTION_PROJECTION
            else -> true
        }
    }

    private fun attemptPlayback(job: PlaybackJob) {
        if (!jobIsValid(job)) {
            if (playbackJob === job) stopPlayback()
            return
        }
        if (!AudioFileValidator.isUsable(File(job.path))) {
            failJob(job, "FILE_INVALID path=${job.path}")
            return
        }
        if (!routeReady(job)) {
            job.state = "waiting_route"
            waitForPlayback(job)
            return
        }
        val granted = if (job.bootSession > 0) requestBootAudioFocus() else requestAudioFocus()
        focusHeld = granted
        if (!granted) {
            job.state = "waiting_focus"
            waitForPlayback(job)
            return
        }
        cancelPendingFocusPlayback()
        doPlayAudio(job.path, job.type, job.bootSession > 0)
    }

    private fun waitForPlayback(job: PlaybackJob) {
        if (pendingFocusPlaybackRunnable != null) return
        val now = SystemClock.elapsedRealtime()
        if (now - lastPlaybackWaitLog >= ROUTE_WAIT_LOG_INTERVAL_MS) {
            lastPlaybackWaitLog = now
            jobLog(job, "waiting ${audioSnapshot()}")
        }
        val retry = Runnable {
            pendingFocusPlaybackRunnable = null
            attemptPlayback(job)
        }
        pendingFocusPlaybackRunnable = retry
        handler.postDelayed(retry, FOCUS_RETRY_MS)
    }

    private fun cancelPendingFocusPlayback() {
        pendingFocusPlaybackRunnable?.let { handler.removeCallbacks(it) }
        pendingFocusPlaybackRunnable = null
    }

    private fun releasePlayerOnly() {
        playerHealthCheck?.let { handler.removeCallbacks(it) }
        playerHealthCheck = null
        val old = mediaPlayer
        mediaPlayer = null
        mediaPlayerPrepared = false
        try { old?.release() } catch (e: Exception) {
            HiCarDiagnosticLog.w("HiCarAudio", "release failed: ${e.stackTraceToString()}")
        }
    }

    private fun failJob(job: PlaybackJob, reason: String) {
        if (playbackJob !== job || job.cancelled) return
        releasePlayerOnly()
        releaseAudioFocus()
        releaseBootAudioFocus()
        focusHeld = false
        job.state = "failed"
        jobLog(job, "PLAYBACK_FAILED $reason", error = true)
        if (job.bootSession > 0) {
            BootSessionManager.markSessionFailed(this, job.bootSession)
            cancelBootMissWatchdog()
        }
        HiCarPlugin.instance?.invokeServiceMethod("onPlaybackFailed")
        HiCarPlugin.instance?.invokeServiceMethod("onNativeError",
            "PLAYBACK_FAILED job=${job.id} mode=${job.mode} type=${job.type} $reason")
        updatePlaybackState(PlaybackStateCompat.STATE_ERROR)
        OverlayBridge.notifyPlaybackComplete()
    }

    private fun recoverPlayer(job: PlaybackJob, attempt: Int, what: Int, extra: Int, reason: String) {
        if (playbackJob !== job || !job.owns(attempt) || job.state == "retrying" || job.state == "failed") return
        // Release on the handler, outside MediaPlayer's callback. A stale callback is inert.
        handler.post {
            if (playbackJob !== job || !job.owns(attempt) || job.state == "retrying" || job.state == "failed") return@post
            val delay = job.retryDelay(what, extra)
            jobLog(job, "MediaPlayer error what=$what extra=$extra reason=$reason", error = true)
            releasePlayerOnly()
            releaseAudioFocus()
            releaseBootAudioFocus()
            focusHeld = false
            if (delay == null) {
                failJob(job, "what=$what extra=$extra $reason")
                return@post
            }
            if (job.bootSession > 0) BootSessionManager.clearPlaybackStarted(this, job.bootSession)
            HiCarPlugin.instance?.invokeServiceMethod("onPlaybackPending", job.type)
            jobLog(job, "retry_scheduled delayMs=$delay")
            playerRetry = Runnable {
                playerRetry = null
                if (playbackJob === job && job.owns(attempt)) attemptPlayback(job)
            }
            handler.postDelayed(playerRetry!!, delay)
        }
    }

    private fun doPlayAudio(path: String, type: String, isBootAutoPlay: Boolean = false) {
        // The boot watcher hands ownership to the same job/recovery path as other modes.
        var job = playbackJob
        if (job == null || job.cancelled || job.state in setOf("completed", "failed") ||
            job.path != path || job.type != type) {
            pendingAutomatic = isBootAutoPlay
            playAudio(path, type, isBootAutoPlay = isBootAutoPlay)
            return
        }
        val active = job
        val attempt = active.beginAttempt()
        releasePlayerOnly()
        completingBootSessionId = active.bootSession
        try {
            val player = MediaPlayer()
            mediaPlayer = player
            player.setWakeMode(applicationContext, PowerManager.PARTIAL_WAKE_LOCK)
            player.setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
            player.setDataSource(path)
            player.setVolume(1f, 1f)
            player.setOnErrorListener { failed, what, extra ->
                if (mediaPlayer === failed) recoverPlayer(active, attempt, what, extra, "native_callback")
                true
            }
            player.setOnCompletionListener { completed ->
                handler.post {
                    if (mediaPlayer !== completed || playbackJob !== active || !active.owns(attempt) ||
                        active.state in setOf("retrying", "failed")) return@post
                    active.state = "completed"
                    active.positionMs = active.durationMs
                    jobLog(active, "onCompletion")
                    if (active.bootSession > 0) completeBootSessionIfNeeded("onCompletion")
                    releasePlayerOnly()
                    releaseAudioFocus()
                    releaseBootAudioFocus()
                    focusHeld = false
                    HiCarPlugin.instance?.invokeServiceMethod("onPlaybackResolved", active.id)
                    updatePlaybackState(PlaybackStateCompat.STATE_STOPPED)
                }
            }
            fun startPrepared() {
                if (mediaPlayer !== player || playbackJob !== active || !active.owns(attempt)) return
                if (!jobIsValid(active)) { stopPlayback(); return }
                if (!focusHeld || !routeReady(active)) {
                    // Keep the prepared player. Health/focus recovery waits instead of playing on a wrong route.
                    active.state = "waiting_focus"
                    scheduleFocusRecovery("prepared_wait", active.bootSession > 0)
                    return
                }
                player.start()
                active.state = "playing"
                if (active.bootSession > 0) {
                    onBoxBootPlaybackStarted(active.bootSession, true)
                }
                if (active.automatic && active.mode == "phone_android_auto") {
                    aaGreetingPlayedThisConnection = true
                    pendingAaAutoGreeting = false
                }
                jobLog(active, "playAudio OK ${audioSnapshot()}")
                HiCarPlugin.instance?.invokeServiceMethod("onPlaybackStarted", type)
                OverlayBridge.notifyPlaybackStarted(type)
                updatePlaybackState(PlaybackStateCompat.STATE_PLAYING)
            }
            player.setOnPreparedListener { prepared ->
                if (mediaPlayer !== prepared || playbackJob !== active || !active.owns(attempt)) return@setOnPreparedListener
                try {
                    mediaPlayerPrepared = true
                    active.durationMs = prepared.duration.coerceAtLeast(0)
                    if (active.positionMs > 0 && active.positionMs < active.durationMs) {
                        prepared.setOnSeekCompleteListener {
                            try { startPrepared() } catch (e: Exception) {
                                recoverPlayer(active, attempt, 1, -32, "seek_start ${e.stackTraceToString()}")
                            }
                        }
                        prepared.seekTo(active.positionMs)
                    } else startPrepared()
                } catch (e: Exception) {
                    recoverPlayer(active, attempt, 1, -32, "prepare_start ${e.stackTraceToString()}")
                }
            }
            jobLog(active, "prepareAsync")
            player.prepareAsync()
            startPlayerHealthCheck(active, player, attempt)
        } catch (e: Exception) {
            recoverPlayer(active, attempt, 1, if (e is java.io.IOException) -1004 else -32, e.stackTraceToString())
        }
    }

    private fun startPlayerHealthCheck(job: PlaybackJob, player: MediaPlayer, attempt: Int) {
        var lastProgressAt = SystemClock.elapsedRealtime()
        var lastPosition = job.positionMs
        val check = object : Runnable {
            override fun run() {
                if (mediaPlayer !== player || playbackJob !== job || !job.owns(attempt)) return
                if (!jobIsValid(job)) { stopPlayback(); return }
                val now = SystemClock.elapsedRealtime()
                try {
                    if (mediaPlayerPrepared) {
                        val position = player.currentPosition
                        if (position > lastPosition) {
                            job.positionMs = position
                            lastPosition = position
                            lastProgressAt = now
                            if (job.bootSession > 0) BootSessionManager.savePlaybackPosition(this@AudioForegroundService, job.bootSession, position)
                        }
                        if (!focusHeld || !routeReady(job)) {
                            if (player.isPlaying) player.pause()
                            job.state = "waiting_focus"
                            lastProgressAt = now
                            if (focusRecoveryRunnable == null) scheduleFocusRecovery("health_wait", job.bootSession > 0)
                        }
                    }
                    // A hung decoder is distinct from a slow route/focus: only rebuild the former.
                    if (now - lastProgressAt >= 60_000L && job.state in setOf("preparing", "playing")) {
                        recoverPlayer(job, attempt, 1, -110, "player_no_progress_60s")
                        return
                    }
                    jobLog(job, "health prepared=$mediaPlayerPrepared ${audioSnapshot()}")
                } catch (e: Exception) {
                    recoverPlayer(job, attempt, 1, -32, "health ${e.stackTraceToString()}")
                    return
                }
                handler.postDelayed(this, 5_000L)
            }
        }
        playerHealthCheck = check
        handler.postDelayed(check, 5_000L)
    }

    private fun stopPlayback(releaseOnly: Boolean = false, preserveBootForRestart: Boolean = false) {
        playbackJob?.let { job ->
            if (job.state !in setOf("completed", "failed", "cancelled")) {
                job.cancel()
                jobLog(job, "stop replacement=$releaseOnly preserveBootForRestart=$preserveBootForRestart")
                HiCarPlugin.instance?.invokeServiceMethod("onPlaybackResolved", job.id)
                if (!preserveBootForRestart && job.bootSession > 0 &&
                    job.bootSession == BootSessionManager.getCurrentSession(this)) {
                    BootSessionManager.markSessionFailed(this, job.bootSession)
                }
            }
        }
        playerRetry?.let { handler.removeCallbacks(it) }
        playerRetry = null
        cancelFocusRecovery()
        cancelPendingFocusPlayback()
        cancelDelayedPlay()
        pendingAaAutoGreeting = false
        releasePlayerOnly()
        releaseAudioFocus()
        releaseBootAudioFocus()
        focusHeld = false
        if (!releaseOnly) {
            HiCarPlugin.instance?.invokeServiceMethod("onPlaybackFailed")
            // A user stop/cancel is not successful completion (must not minimize Flutter).
            updatePlaybackState(PlaybackStateCompat.STATE_NONE)
            OverlayBridge.notifyPlaybackComplete()
        }
    }

    // ==============================
    // Audio Focus
    // ==============================

    private val legacyFocusListener = AudioManager.OnAudioFocusChangeListener { change ->
        handler.post { handleFocusChange(change, false) }
    }

    private fun buildAudioFocusRequest() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                .setOnAudioFocusChangeListener(legacyFocusListener, handler).build()
        }
    }

    private fun buildBootAudioFocusRequest() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            bootAudioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                .setOnAudioFocusChangeListener({ change ->
                    handler.post { handleFocusChange(change, true) }
                }, handler).build()
        }
    }

    private fun handleFocusChange(change: Int, boot: Boolean) {
        val job = playbackJob ?: return
        if (job.cancelled || job.state in setOf("completed", "failed", "retrying")) return
        if ((job.bootSession > 0) != boot && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) return
        jobLog(job, "focus_change=$change")
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS, AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                focusHeld = false
                try { if (mediaPlayerPrepared) mediaPlayer?.pause() } catch (e: Exception) {
                    recoverPlayer(job, job.attempt, 1, -32, "focus_pause ${e.stackTraceToString()}")
                }
                // If still preparing, leave that state so the decoder health timer remains active.
                if (mediaPlayerPrepared) job.state = "waiting_focus"
                scheduleFocusRecovery("focus_change", boot)
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                try { mediaPlayer?.setVolume(0.2f, 0.2f) } catch (_: Exception) {}
            }
            AudioManager.AUDIOFOCUS_GAIN -> {
                focusHeld = true
                try { mediaPlayer?.setVolume(1f, 1f) } catch (_: Exception) {}
                scheduleFocusRecovery("focus_gain", boot)
            }
        }
    }

    private var lastFocusExceptionAt = 0L

    private fun requestBootAudioFocus() = requestFocusSafely(true)
    private fun requestAudioFocus() = requestFocusSafely(false)

    private fun requestFocusSafely(boot: Boolean): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                (if (boot) bootAudioFocusRequest else audioFocusRequest)?.let {
                    audioManager?.requestAudioFocus(it) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
                } ?: false
            } else {
                @Suppress("DEPRECATION")
                audioManager?.requestAudioFocus(legacyFocusListener, AudioManager.STREAM_MUSIC,
                    if (boot) AudioManager.AUDIOFOCUS_GAIN else AudioManager.AUDIOFOCUS_GAIN_TRANSIENT
                ) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            }
        } catch (e: Exception) {
            val now = SystemClock.elapsedRealtime()
            if (lastFocusExceptionAt == 0L || now - lastFocusExceptionAt >= 30_000L) {
                lastFocusExceptionAt = now
                val message = "AUDIO_FOCUS_EXCEPTION mode=$connectionMode api=${Build.VERSION.SDK_INT} ${e.stackTraceToString()}"
                HiCarDiagnosticLog.e("HiCarAudio", message)
                HiCarPlugin.instance?.invokeServiceMethod("onNativeError", message)
            }
            false
        }
    }

    private fun releaseBootAudioFocus() = releaseFocusSafely(true)
    private fun releaseAudioFocus() = releaseFocusSafely(false)

    private fun releaseFocusSafely(boot: Boolean) {
        cancelFocusRecovery()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                (if (boot) bootAudioFocusRequest else audioFocusRequest)?.let {
                    audioManager?.abandonAudioFocusRequest(it)
                }
            } else {
                @Suppress("DEPRECATION")
                audioManager?.abandonAudioFocus(legacyFocusListener)
            }
        } catch (e: Exception) {
            HiCarDiagnosticLog.w("HiCarAudio", "focus release mode=$connectionMode ${e.stackTraceToString()}")
        }
    }

    /** Giữ pending playback khi focus bị mất; request lại trên Handler, không gọi trong callback. */
    private fun scheduleFocusRecovery(reason: String, useBootFocus: Boolean = false) {
        if (focusRecoveryRunnable != null) return
        val owner = playbackJob ?: return
        val attempt = owner.attempt
        var lastLog = 0L
        val recovery = object : Runnable {
            override fun run() {
                if (playbackJob !== owner || !owner.owns(attempt)) { cancelFocusRecovery(); return }
                if (!jobIsValid(owner)) { stopPlayback(); return }
                val player = mediaPlayer ?: run { cancelFocusRecovery(); return }
                try {
                    if (mediaPlayerPrepared && routeReady(owner) &&
                        (focusHeld || if (useBootFocus) requestBootAudioFocus() else requestAudioFocus())) {
                        focusHeld = true
                        player.start()
                        owner.state = "playing"
                        if (owner.bootSession > 0) onBoxBootPlaybackStarted(owner.bootSession, true)
                        if (owner.automatic && owner.mode == "phone_android_auto") {
                            aaGreetingPlayedThisConnection = true
                            pendingAaAutoGreeting = false
                        }
                        jobLog(owner, "focus_resumed reason=$reason")
                        HiCarPlugin.instance?.invokeServiceMethod("onPlaybackStarted", owner.type)
                        updatePlaybackState(PlaybackStateCompat.STATE_PLAYING)
                        cancelFocusRecovery()
                        return
                    }
                } catch (e: Exception) {
                    cancelFocusRecovery()
                    recoverPlayer(owner, attempt, 1, -32, "focus_resume ${e.stackTraceToString()}")
                    return
                }
                val now = SystemClock.elapsedRealtime()
                if (now - lastLog >= ROUTE_WAIT_LOG_INTERVAL_MS) {
                    lastLog = now
                    jobLog(owner, "focus_pending reason=$reason ${audioSnapshot()}")
                }
                handler.postDelayed(this, FOCUS_RETRY_MS)
            }
        }
        focusRecoveryRunnable = recovery
        handler.postDelayed(recovery, FOCUS_RETRY_MS)
    }

    private fun cancelFocusRecovery() {
        focusRecoveryRunnable?.let { handler.removeCallbacks(it) }
        focusRecoveryRunnable = null
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
            // Loại bỏ độ trễ 1s để UI cập nhật tức thì, tránh bị nháy khi phát bản tiếp theo
            HiCarPlugin.instance?.invokeServiceMethod("onPlaybackComplete")
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
