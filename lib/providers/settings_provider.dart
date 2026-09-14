import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../native/bluetooth_channel.dart';
import '../native/service_channel.dart';
import '../core/logger.dart';

class SettingsProvider extends ChangeNotifier {
  bool _autoPlayEnabled = true;
  int _delaySeconds = AppConstants.defaultDelaySeconds;
  bool _bluetoothAutoPlay = true;
  bool _androidAutoEnabled = true;
  bool _showNotification = true;
  // 'android_screen_mode' | 'android_box_mode' | 'phone_bluetooth' | 'phone_android_auto'
  String _connectionMode = AppConstants.defaultConnectionMode;
  bool _playOnOpen = true;
  String? _pendingConnectionMode;
  bool _isBetaMode = false;

  bool get autoPlayEnabled => _autoPlayEnabled;
  bool get playOnOpen => _playOnOpen;
  int get delaySeconds => _delaySeconds;
  bool get bluetoothAutoPlay => _bluetoothAutoPlay;
  bool get androidAutoEnabled => _androidAutoEnabled;
  bool get showNotification => _showNotification;
  String get connectionMode => _connectionMode;
  String? get pendingConnectionMode => _pendingConnectionMode;
  bool get isBetaMode => _isBetaMode;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _autoPlayEnabled = prefs.getBool(AppConstants.keyAutoPlayEnabled) ?? true;
    _delaySeconds = prefs.getInt(AppConstants.keyDelaySeconds) ??
        AppConstants.defaultDelaySeconds;
    _bluetoothAutoPlay = prefs.getBool('bluetooth_auto_play') ?? true;
    _androidAutoEnabled = prefs.getBool('android_auto_enabled') ?? true;
    _showNotification = prefs.getBool('show_notification') ?? true;
    // iOS chỉ có duy nhất chế độ CarPlay; Android giữ mặc định màn hình độ.
    if (Platform.isIOS) {
      _connectionMode = AppConstants.iosCarplayMode;
    } else {
      _connectionMode =
          prefs.getString('connection_mode') ?? AppConstants.defaultConnectionMode;
    }
    // Ghi lại ngay cả khi chỉ là giá trị mặc định: native (Service / BootReceiver /
    // BluetoothReceiver) đọc thẳng key này từ SharedPreferences. Thiếu key thì mỗi nơi
    // rơi về mặc định riêng và có thể tự phát nhạc ở chế độ người dùng không hề chọn.
    if (prefs.getString('connection_mode') != _connectionMode) {
      await prefs.setString('connection_mode', _connectionMode);
    }
    _playOnOpen = prefs.getBool('play_on_open') ?? true;
    _isBetaMode = prefs.getBool('is_beta_mode') ?? false;

    // Sync connection mode with native on startup
    try {
      await BluetoothChannel.instance.setConnectionMode(_connectionMode);
    } catch (e) {
      debugPrint('Native BluetoothChannel error on init: $e');
    }
    notifyListeners();
  }

  Future<void> setAutoPlay(bool value) async {
    _autoPlayEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyAutoPlayEnabled, value);
    notifyListeners();
  }

  Future<void> setDelay(int seconds) async {
    _delaySeconds = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.keyDelaySeconds, seconds);
    notifyListeners();
  }

  Future<void> setBluetoothAutoPlay(bool value) async {
    _bluetoothAutoPlay = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bluetooth_auto_play', value);
    notifyListeners();
  }

  Future<void> setAndroidAutoEnabled(bool value) async {
    _androidAutoEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('android_auto_enabled', value);
    notifyListeners();
  }

  Future<void> setShowNotification(bool value) async {
    _showNotification = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_notification', value);
    notifyListeners();
  }

  Future<void> setPlayOnOpen(bool value) async {
    _playOnOpen = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('play_on_open', value);
    notifyListeners();
  }

  Future<void> setConnectionMode(String mode) async {
    _pendingConnectionMode = mode;
    notifyListeners();
  }

  Future<void> commitSettings() async {
    if (_pendingConnectionMode != null) {
      final oldMode = _connectionMode;
      _connectionMode = _pendingConnectionMode!;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('connection_mode', _connectionMode);
      _pendingConnectionMode = null;

      debugPrint('SettingsProvider: mode changed $oldMode → $_connectionMode');

      // 🧹 DỌN DẸP KHI ĐỔI MODE
      if (oldMode == 'phone_bluetooth' &&
          _connectionMode != 'phone_bluetooth') {
        try {
          // Ngắt kết nối tuyệt đối với thiết bị đã ghép nối
          final targetAddress =
              prefs.getString(AppConstants.keyTargetDeviceAddress) ?? '';
          if (targetAddress.isNotEmpty) {
            await BluetoothChannel.instance.disconnectDevice(targetAddress);
          }
          await BluetoothChannel.instance.stopDiscovery();
          await BluetoothChannel.instance.clearTargetDevice();
        } catch (e) {
          debugPrint('Clean up phone_bluetooth error: $e');
        }
      }

      if (oldMode == 'phone_android_auto' &&
          _connectionMode != 'phone_android_auto') {
        try {
          // Ngắt kết nối tuyệt đối với Android Auto bằng cách dừng Service
          await ServiceChannel.instance.stopService();
        } catch (e) {
          debugPrint('Clean up phone_android_auto error: $e');
        }
      }

      // Đồng bộ Mode mới sang Native
      try {
        await BluetoothChannel.instance.setConnectionMode(_connectionMode);
      } catch (e) {
        debugPrint('Sync new mode error: $e');
        AppLogger.instance.log(
          'Lỗi đồng bộ mode sang Native: $e',
          type: 'native_error',
          details: {'mode': _connectionMode, 'error': e.toString()},
        );
      }
    }

    // 🟢 Đồng bộ sang vùng nhớ an toàn cho khởi động (Direct Boot)
    await ServiceChannel.instance.syncPrefs();

    notifyListeners();
  }

  void cancelPendingSettings() {
    _pendingConnectionMode = null;
    notifyListeners();
  }

  Future<void> setBetaMode(bool value) async {
    _isBetaMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_beta_mode', value);
    notifyListeners();
  }
}
