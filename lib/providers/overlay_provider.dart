import 'dart:ui' as ui;
import 'dart:io';
import '../core/logger.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OverlayDebugStore {
  OverlayDebugStore._();

  static const String _prefsKey = 'overlay_last_error';
  static final ValueNotifier<String?> notifier = ValueNotifier<String?>(null);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    notifier.value = prefs.getString(_prefsKey);
  }

  static Future<void> record(String message) async {
    final stamped = '[${DateTime.now().toIso8601String()}] $message';
    notifier.value = stamped;
    AppLogger.instance.log(message,
        type: 'overlay_error',
        userMessage:
            'Bong bóng nổi chưa hoạt động. Kiểm tra quyền hiển thị trên ứng dụng khác.',
        requiresAction: true,
        details: {'mode': 'android_screen_mode'});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, stamped);
  }

  static Future<void> clear() async {
    notifier.value = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}

class OverlayProvider extends ChangeNotifier {
  OverlayProvider() : _isAndroid = Platform.isAndroid;
  @visibleForTesting
  OverlayProvider.forTest() : _isAndroid = true;
  final bool _isAndroid;
  static const double _overlayWindowWidth = 80.0;
  // 2 nút (chào + tạm biệt), không còn nút mở app.
  static const double _overlayWindowHeight = 170.0;

  bool _isOverlayShowing = false;
  bool _hasPermission = false;
  bool _isBubbleEnabled = false;
  bool _enableAfterPermissionGrant = false;
  bool _desiredVisible = false;
  Future<void> _visibilityQueue = Future.value();
  Future<void>? _initialization;

  bool get isOverlayShowing => _isOverlayShowing;
  bool get hasPermission => _hasPermission;
  bool get isBubbleEnabled => _isBubbleEnabled;

  int _toInitialOverlayPixels(double logicalSize) {
    final views = ui.PlatformDispatcher.instance.views;
    final ratio = views.isNotEmpty ? views.first.devicePixelRatio : 3.0;
    return (logicalSize * ratio).round();
  }

  Future<void> init() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    if (!_isAndroid) return;
    final prefs = await SharedPreferences.getInstance();
    await OverlayDebugStore.load();
    _isBubbleEnabled = prefs.getBool('is_bubble_enabled') ?? true;
    await checkPermission();
    notifyListeners();
    await syncOverlayState();
  }

  Future<void> checkPermission() async {
    if (!_isAndroid) return;
    try {
      _hasPermission = await FlutterOverlayWindow.isPermissionGranted();
    } catch (e) {
      _hasPermission = false;
      await OverlayDebugStore.record('Không đọc được quyền overlay: $e');
    }
    if (_hasPermission && _enableAfterPermissionGrant) {
      _enableAfterPermissionGrant = false;
      _isBubbleEnabled = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_bubble_enabled', true);
    }
    // A permission check is capability, not the user's saved preference.
    notifyListeners();
  }

  Future<void> syncOverlayState() async {
    try {
      _isOverlayShowing = await FlutterOverlayWindow.isActive();
    } catch (_) {
      _isOverlayShowing = false;
    }
    notifyListeners();
  }

  Future<bool> requestPermission() async {
    try {
      await FlutterOverlayWindow.requestPermission();
      await checkPermission();
    } catch (_) {
      _hasPermission = false;
      notifyListeners();
    }
    return _hasPermission;
  }

  Future<bool> setBubbleEnabled(bool value) async {
    if (value) {
      await checkPermission();
      if (!_hasPermission) {
        _enableAfterPermissionGrant = true;
        final granted = await requestPermission();
        if (!granted) {
          _isBubbleEnabled = false;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('is_bubble_enabled', false);
          notifyListeners();
          return false;
        }
      }

      if (!_hasPermission) {
        _isBubbleEnabled = false;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_bubble_enabled', false);
        notifyListeners();
        return false;
      }
    } else {
      _enableAfterPermissionGrant = false;
    }

    _isBubbleEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_bubble_enabled', value);
    notifyListeners();

    if (value) {
      // If enabled and app is in background, it will show automatically.
    } else {
      await hideOverlay();
    }
    return true;
  }

  Future<void> showOverlay() {
    _desiredVisible = true;
    return _queueVisibility();
  }

  Future<void> hideOverlay() {
    _desiredVisible = false;
    return _queueVisibility();
  }

  Future<void> _queueVisibility() {
    _visibilityQueue = _visibilityQueue.then((_) async {
      if (!_isAndroid) return;
      await init();
      final prefs = await SharedPreferences.getInstance();
      final allowed = _desiredVisible &&
          _isBubbleEnabled &&
          prefs.getString('connection_mode') == 'android_screen_mode' &&
          (prefs.getString('auth_token') ?? '').isNotEmpty;
      if (!allowed) {
        await FlutterOverlayWindow.closeOverlay();
      } else {
        await checkPermission();
        if (!_hasPermission) {
          await OverlayDebugStore.record(
              'Thiếu quyền SYSTEM_ALERT_WINDOW để hiển thị bong bóng.');
          return;
        }
        if (!_desiredVisible)
          return; // Resumed while permission check was pending.
        if (!await FlutterOverlayWindow.isActive()) {
          await FlutterOverlayWindow.showOverlay(
            enableDrag: true,
            flag: OverlayFlag.defaultFlag,
            alignment: OverlayAlignment.topLeft,
            visibility: NotificationVisibility.visibilityPublic,
            positionGravity: PositionGravity.none,
            height: _toInitialOverlayPixels(_overlayWindowHeight),
            width: _toInitialOverlayPixels(_overlayWindowWidth),
          );
        }
      }
      await syncOverlayState();
    }).catchError((Object e) async {
      await OverlayDebugStore.record('Overlay show/hide thất bại: $e');
    });
    return _visibilityQueue;
  }

  Future<void> updateOverlayState({
    bool? isGreetingPlaying,
    bool? isGoodbyePlaying,
    String? errorMessage,
  }) async {
    try {
      final active = await FlutterOverlayWindow.isActive();
      if (!active) return;

      await FlutterOverlayWindow.shareData({
        'type': 'state_update',
        'isGreetingPlaying': isGreetingPlaying,
        'isGoodbyePlaying': isGoodbyePlaying,
        'errorMessage': errorMessage,
      });
    } catch (_) {}
  }
}
