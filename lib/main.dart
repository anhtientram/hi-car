import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:hi_car/core/app_colors.dart';
import 'package:hi_car/overlay/overlay_main.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/app_theme.dart';
import 'core/app_router.dart';
import 'core/constants.dart';
import 'core/utils/ui_utils.dart';
import 'native/service_channel.dart';
import 'data/services/remote_config_service.dart';
import 'providers/auth_provider.dart';
import 'providers/audio_provider.dart';
import 'providers/bluetooth_provider.dart';
import 'providers/overlay_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/permission_provider.dart';
import 'providers/studio_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Lấy Base URL động từ remote config TRƯỚC khi dựng app để mọi request dùng
  // đúng domain (domain cũ đã ngừng hoạt động).
  await RemoteConfigService.instance.load();
  _setupEasyLoading();
  runApp(const MyApp());
}

void _setupEasyLoading() {
  EasyLoading.instance
    ..displayDuration = const Duration(milliseconds: 2000)
    ..indicatorType = EasyLoadingIndicatorType.fadingCircle
    ..loadingStyle = EasyLoadingStyle.custom
    ..indicatorSize = 45.0
    ..radius = 16.0
    ..progressColor = AppColors.primary
    ..backgroundColor = AppColors.surface
    ..indicatorColor = AppColors.primary
    ..textColor = AppColors.textPrimary
    ..maskColor = Colors.black.withOpacity(0.5)
    ..userInteractions = false
    ..dismissOnTap = false;
}

// ⚠️ QUAN TRỌNG: entry point của nút nổi PHẢI nằm trong library gốc (cùng file với main()).
//    flutter_overlay_window tạo engine với DartEntrypoint("overlayMain") KHÔNG kèm library URI,
//    nên ở chế độ release (AOT) engine chỉ tìm hàm này trong library chứa main(). Nếu đặt ở
//    file khác, release build sẽ KHÔNG tìm thấy → nút nổi biến mất.
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  runApp(const OverlayApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late final AudioProvider _audioProvider;
  late final OverlayProvider _overlayProvider;
  late final SettingsProvider _settingsProvider;
  late final BluetoothProvider _bluetoothProvider;

  @override
  void initState() {
    super.initState();
    _audioProvider = AudioProvider()..init();
    _overlayProvider = OverlayProvider()..init();
    _settingsProvider = SettingsProvider()..init();
    _bluetoothProvider = BluetoothProvider();

    // ⚠️ Gán callback TRƯỚC init() — tránh race: BT connect sớm khiến MATCH FOUND
    //    nhưng onTargetConnected còn null hoặc chưa sẵn sàng.
    _bluetoothProvider.onTargetConnected = () async {
      if (!await _isLoggedIn()) {
        debugPrint('Main: BT connect skip – chưa đăng nhập');
        return false;
      }

      // Đọc trực tiếp từ prefs — SettingsProvider.init() async có thể chưa xong.
      final prefs = await SharedPreferences.getInstance();
      final mode = prefs.getString('connection_mode') ?? '';
      final autoPlay = prefs.getBool(AppConstants.keyAutoPlayEnabled) ?? true;

      if (mode != 'phone_bluetooth') {
        debugPrint(
            'Main: BT connect skip – mode=$mode (Flutter chỉ phát cho phone_bluetooth)');
        return false;
      }
      if (!autoPlay) {
        debugPrint('Main: BT connect skip – autoPlay tắt');
        return false;
      }

      // 🟢 KHÔNG phát từ Flutter nữa cho phone_bluetooth.
      // BluetoothReceiver (native) đã bật ACTION_BT_WATCH_A2DP: đợi route A2DP của màn hình
      // xe sẵn sàng rồi mới phát. Nếu Flutter cũng gọi playGreetingViaNative ở đây thì phát
      // NGAY khi ACL connect (chưa có A2DP) → tiếng ra loa điện thoại + phát chồng. Để native
      // làm chủ toàn bộ giúp tiếng luôn ra loa xe và chỉ phát một lần.
      debugPrint(
          'Main: BT connected → native A2DP watch sở hữu playback, Flutter bỏ qua');
      return false;
    };

    _bluetoothProvider.init();

    // Listen to audio provider to sync state to overlay
    _audioProvider.addListener(_updateOverlayState);

    // 🟢 Chế độ Android Màn Độ: Khi phát xong thì thu nhỏ app
    _audioProvider.onNativePlaybackComplete = (isManual) {
      if (_settingsProvider.connectionMode == 'android_screen_mode' &&
          !isManual) {
        debugPrint(
            'Main: Audio finished in android_screen_mode, minimizing app...');
        ServiceChannel.instance.minimizeApp();
      }
    };

    _initOverlayListener();
    _initIsolateListener();
    WidgetsBinding.instance.addObserver(this);

    // 🟢 Chế độ Mở App là Chào: Phát nhạc ngay khi khởi động
    _initPlayOnOpen();

    // Ensure overlay is hidden on startup
    _overlayProvider.hideOverlay();
  }

  void _updateOverlayState() {
    _overlayProvider.updateOverlayState(
      isGreetingPlaying: _audioProvider.isNativeGreetingPlaying,
      isGoodbyePlaying: _audioProvider.isNativeGoodbyePlaying,
    );
  }

  @override
  void dispose() {
    _audioProvider.removeListener(_updateOverlayState);
    IsolateNameServer.removePortNameMapping('overlay_action_port');
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 🟢 Đánh dấu app từng bị đẩy xuống nền, để phân biệt "mở lại app" với lần khởi động đầu.
  bool _wasPaused = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 🟢 CHỈ ẩn overlay khi app THỰC SỰ ra tiền cảnh (resumed). Không ẩn ở 'inactive'
    //    vì trạng thái này xảy ra thoáng qua (kéo thanh thông báo, dialog hệ thống,
    //    đang chuyển cảnh...) khiến nút nổi bị tắt sớm/giật và đóng/mở liên tục.
    if (state == AppLifecycleState.resumed) {
      _overlayProvider.hideOverlay();
      ServiceChannel.instance.importNativeDiagnostics().catchError((_) {});

      // 🟢 Chế độ Màn Độ: mỗi lần MỞ LẠI app (resume từ nền) thì phát lại lời chào.
      //    Vì sau khi phát xong app chỉ bị thu nhỏ (moveToHome) chứ không bị kill,
      //    nên initState/_initPlayOnOpen không chạy lại — phải tự kích hoạt ở đây.
      if (_wasPaused) {
        _wasPaused = false;
        _maybePlayGreetingOnResume();
      }
    } else if (state == AppLifecycleState.paused) {
      _wasPaused = true;
      _overlayProvider.showOverlay().then((_) {
        _updateOverlayState();
      });
    }
  }

  /// Kiểm tra đã đăng nhập chưa (đọc trực tiếp từ prefs để không phụ thuộc context).
  Future<bool> _isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(AppConstants.keyAuthToken);
    return token != null && token.isNotEmpty;
  }

  /// Phát lại lời chào khi app được mở lại (chỉ áp dụng chế độ Màn Độ + bật "phát khi mở app").
  Future<void> _maybePlayGreetingOnResume() async {
    if (_settingsProvider.connectionMode != 'android_screen_mode') return;
    if (!_settingsProvider.playOnOpen) return;
    // 🟢 Chưa đăng nhập thì không phát (vd: vừa đăng xuất, đang ở màn Login).
    if (!await _isLoggedIn()) return;
    if (_audioProvider.isNativeGreetingPlaying ||
        _audioProvider.isNativeGoodbyePlaying) {
      return;
    }

    // Chờ một nhịp để hệ thống ổn định (audio focus, UI) sau khi resume.
    await Future.delayed(const Duration(milliseconds: 600));
    if (_audioProvider.isNativeGreetingPlaying ||
        _audioProvider.isNativeGoodbyePlaying) {
      return;
    }

    debugPrint('Main: App resumed in screen mode → phát lại lời chào');
    await _audioProvider.playGreetingViaNative(allowAutostartRetry: true);
  }

  void _initIsolateListener() {
    final receivePort = ReceivePort();
    IsolateNameServer.removePortNameMapping('overlay_action_port');
    IsolateNameServer.registerPortWithName(
        receivePort.sendPort, 'overlay_action_port');

    receivePort.listen((message) {
      debugPrint('Isolate listener received: $message');
      if (message is Map && message.containsKey('action')) {
        _handleOverlayAction(message['action']);
      }
    });
  }

  Future<void> _handleOverlayAction(dynamic action) async {
    OverlayDebugStore.record('Action received: $action');
    bool success = true;
    String? errorMsg;

    switch (action) {
      case 'play_greeting':
        success = await _audioProvider.playGreetingViaNative();
        if (!success) errorMsg = 'Chưa chọn nhạc chào';
        break;
      case 'play_goodbye':
        success = await _audioProvider.playGoodbyeViaNative();
        if (!success) errorMsg = 'Chưa chọn nhạc tạm biệt';
        break;
      case 'stop_audio':
        await _audioProvider.stopNativeAudio();
        break;
      case 'open_app':
        debugPrint('Main: Triggering openApp');
        await _openAppDirect();
        break;
    }

    if (!success && errorMsg != null) {
      _overlayProvider.updateOverlayState(errorMessage: errorMsg);
    }
  }

  /// Bring the app to the foreground.
  Future<void> _openAppDirect() async {
    try {
      await _overlayProvider.hideOverlay();
    } catch (_) {}

    for (final channelName in [
      AppConstants.serviceChannel,
      AppConstants.bluetoothChannel,
    ]) {
      try {
        final channel = MethodChannel(channelName);
        final result = await channel.invokeMethod('openApp');
        debugPrint('Main: openApp via $channelName → $result');
        return;
      } on MissingPluginException {
        debugPrint('Main: openApp – $channelName unavailable');
      } catch (e) {
        debugPrint('Main: openApp – $channelName error: $e');
      }
    }

    try {
      ServiceChannel.instance.init();
      await ServiceChannel.instance.openApp();
    } catch (e) {
      debugPrint('Main: openApp final fallback failed: $e');
    }
  }

  // Listen for actions sent from overlay bubble
  void _initOverlayListener() {
    try {
      FlutterOverlayWindow.overlayListener.listen((data) {
        debugPrint('Overlay listener received: $data');
        if (data is Map) {
          final type = data['type'];

          if (type == 'overlay_error') {
            final message =
                (data['message'] ?? 'Unknown overlay error').toString();
            OverlayDebugStore.record(message);
            debugPrint('Overlay error: $message');
            return;
          }

          if (data.containsKey('action')) {
            _handleOverlayAction(data['action']);
          }
        }
      });
    } catch (_) {}
  }

  // 🟢 Logic phát nhạc khi vừa mở app
  bool _hasTriggeredOpenGreeting = false;

  Future<void> _initPlayOnOpen() async {
    if (_hasTriggeredOpenGreeting) return;

    await Future.delayed(const Duration(milliseconds: 1000));

    if (!_settingsProvider.playOnOpen) return;

    // 🟢 Chưa đăng nhập thì KHÔNG phát nhạc khi mở app (vd: vừa đăng xuất).
    if (!await _isLoggedIn()) {
      debugPrint('Main: Not logged in → skip play greeting on open');
      return;
    }

    // 🟢 Chế độ Android Box do BootReceiver/Service tự phát ngầm khi Box khởi động.
    //    Không phát thêm từ Flutter để tránh bị ngắt/phát lại từ đầu hoặc phát lặp.
    if (_settingsProvider.connectionMode == 'android_box_mode') {
      debugPrint('Main: Box mode → boot service owns playback, skip on open');
      return;
    }

    // Chờ danh sách nhạc đồng bộ (tối đa ~10s) để chọn đúng lời chào đang đặt.
    int retryCount = 0;
    while (_audioProvider.audioList.isEmpty && retryCount < 10) {
      debugPrint('Main: Audio list empty, waiting... ($retryCount)');
      await Future.delayed(const Duration(milliseconds: 1000));
      retryCount++;
    }

    // Vẫn thử phát kể cả khi danh sách còn trống (offline / sync chậm):
    // playGreetingViaNative tự fallback sang path đã lưu / file boot. Trước đây nhánh
    // else chặn hẳn nên máy chưa sync kịp là KHÔNG tự phát → "lúc được lúc không".
    _hasTriggeredOpenGreeting = true;
    debugPrint(
        'Main: Triggering play greeting on open (listEmpty=${_audioProvider.audioList.isEmpty})...');
    final ok =
        await _audioProvider.playGreetingViaNative(allowAutostartRetry: true);
    if (!ok) {
      debugPrint(
          'Main: play greeting on open chưa phát được (chưa cấu hình lời chào?)');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider.value(value: _audioProvider),
        ChangeNotifierProvider.value(value: _bluetoothProvider),
        ChangeNotifierProvider.value(value: _overlayProvider),
        ChangeNotifierProvider.value(value: _settingsProvider),
        ChangeNotifierProvider(
            create: (_) => PermissionProvider()..checkAllPermissions()),
        ChangeNotifierProvider(create: (_) => StudioProvider()),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final Size dynamicDesignSize =
              width > 600 ? Size(width, height) : const Size(390, 844);
          return ScreenUtilInit(
            designSize: dynamicDesignSize,
            minTextAdapt: true,
            splitScreenMode: true,
            useInheritedMediaQuery: true,
            builder: (context, child) {
              return MaterialApp.router(
                title: 'Giọng Thương Gia',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.dark,
                scaffoldMessengerKey: rootScaffoldMessengerKey,
                routerConfig: AppRouter.router,
                builder: EasyLoading.init(),
              );
            },
          );
        },
      ),
    );
  }
}
