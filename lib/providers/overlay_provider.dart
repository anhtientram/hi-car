import 'dart:ui' as ui;

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
  static const double _overlayWindowWidth = 80.0;
  // 2 nút (chào + tạm biệt), không còn nút mở app.
  static const double _overlayWindowHeight = 170.0;

  static const String _kBubbleWantedKey = 'is_bubble_enabled';

  bool _isOverlayShowing = false;
  bool _hasPermission = false;

  /// Ý MUỐN của người dùng (bật/tắt nút nổi). Chỉ thay đổi khi người dùng tự bấm.
  ///
  /// ⚠️ Trước đây trạng thái này bị ghi `false` mỗi khi `isPermissionGranted()` trả về
  /// false — kể cả khi đó chỉ là trục trặc nhất thời (plugin chưa attach xong lúc máy
  /// vừa khởi động, head unit trả lời chậm). Một lần lỗi như vậy là nút nổi bị TẮT VĨNH
  /// VIỄN trong prefs: lần khởi động xe sau chỉ còn lời chào, không thấy bong bóng nữa.
  bool _bubbleWanted = true;
  bool _enableAfterPermissionGrant = false;

  bool get isOverlayShowing => _isOverlayShowing;
  bool get hasPermission => _hasPermission;

  /// Người dùng muốn bật nút nổi hay không (không phụ thuộc trạng thái quyền).
  bool get isBubbleWanted => _bubbleWanted;

  /// Nút nổi thực sự dùng được: người dùng muốn bật VÀ đã có quyền hiển thị trên ứng dụng khác.
  bool get isBubbleEnabled => _bubbleWanted && _hasPermission;

  int _toInitialOverlayPixels(double logicalSize) {
    final views = ui.PlatformDispatcher.instance.views;
    final ratio = views.isNotEmpty ? views.first.devicePixelRatio : 3.0;
    return (logicalSize * ratio).round();
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    await OverlayDebugStore.load();
    _bubbleWanted = prefs.getBool(_kBubbleWantedKey) ?? true;
    await checkPermission();
    notifyListeners();
    await syncOverlayState();
  }

  Future<void> checkPermission() async {
    try {
      _hasPermission = await FlutterOverlayWindow.isPermissionGranted();
    } catch (_) {
      _hasPermission = false;
    }
    // Vừa cấp quyền xong sau khi người dùng bấm bật → chốt lại ý muốn "bật".
    if (_hasPermission && _enableAfterPermissionGrant) {
      _enableAfterPermissionGrant = false;
      await _setBubbleWanted(true);
    }
    notifyListeners();
  }

  Future<void> _setBubbleWanted(bool value) async {
    _bubbleWanted = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBubbleWantedKey, value);
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
          await _setBubbleWanted(false);
          notifyListeners();
          return false;
        }
      }
    } else {
      _enableAfterPermissionGrant = false;
    }

    await _setBubbleWanted(value);
    notifyListeners();

    if (!value) await hideOverlay();
    return true;
  }

  Future<void> showOverlay() async {
    if (!_bubbleWanted) return;
    // Quyền có thể vừa được cấp ở màn hình hệ thống → đọc lại trước khi bỏ cuộc.
    if (!_hasPermission) await checkPermission();
    if (!_hasPermission) return;

    try {
      final active = await FlutterOverlayWindow.isActive();
      if (!active) {
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
      await syncOverlayState();
    } catch (_) {}
  }

  Future<void> hideOverlay() async {
    try {
      await FlutterOverlayWindow.closeOverlay();
      await syncOverlayState();
    } catch (_) {}
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
