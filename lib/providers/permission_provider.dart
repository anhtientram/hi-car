import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import '../native/service_channel.dart';
import '../core/logger.dart';

class PermissionStatus {
  final bool bluetooth;
  final bool bluetoothScan;
  final bool bluetoothConnect;
  final bool notification;
  final bool overlay;
  final bool batteryOptimization;
  final bool bootComplete;
  final bool backgroundPersistence;

  const PermissionStatus({
    this.bluetooth = false,
    this.bluetoothScan = false,
    this.bluetoothConnect = false,
    this.notification = false,
    this.overlay = false,
    this.batteryOptimization = false,
    this.bootComplete = false,
    this.backgroundPersistence = false,
  });

  bool isGrantedForMode(String mode) {
    if (mode == 'phone_bluetooth' || mode == 'phone_android_auto') {
      // Android Auto không dây cũng cần Bluetooth để bắt sự kiện kết nối tự phát.
      return bluetoothConnect && notification;
    } else if (mode == 'android_box_mode' || mode == 'android_screen_mode') {
      return notification && batteryOptimization;
    }
    return false;
  }

  int getGrantedCountForMode(String mode) {
    int count = 0;
    if (mode == 'phone_bluetooth' || mode == 'phone_android_auto') {
      if (bluetoothConnect) count++;
      if (notification) count++;
    } else if (mode == 'android_box_mode' || mode == 'android_screen_mode') {
      if (notification) count++;
      if (batteryOptimization) count++;
    }
    return count;
  }

  int getTotalCountForMode(String mode) {
    if (mode == 'phone_bluetooth' || mode == 'phone_android_auto') return 2;
    if (mode == 'android_box_mode' || mode == 'android_screen_mode') return 2;
    return 0;
  }
}

class PermissionProvider extends ChangeNotifier {
  PermissionStatus _status = const PermissionStatus();
  bool _isChecking = false;
  bool _isXiaomi = false;

  PermissionStatus get status => _status;
  bool get isChecking => _isChecking;
  bool get isXiaomi => _isXiaomi;

  Future<void> checkAllPermissions() async {
    _isChecking = true;
    notifyListeners();

    try {
      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        _isXiaomi = androidInfo.manufacturer.toLowerCase().contains('xiaomi') ||
            androidInfo.manufacturer.toLowerCase().contains('poco') ||
            androidInfo.manufacturer.toLowerCase().contains('redmi');
      }
      // Small delay to ensure system settings are synchronized
      await Future.delayed(const Duration(milliseconds: 300));

      final btStatus = await Permission.bluetooth.status;
      final btScanStatus = await Permission.bluetoothScan.status;
      final btConnectStatus = await Permission.bluetoothConnect.status;
      final notifStatus = await Permission.notification.status;
      final overlayGranted = await FlutterOverlayWindow.isPermissionGranted();
      var batteryGranted = false;
      if (Platform.isAndroid) {
        batteryGranted =
            await ServiceChannel.instance.isIgnoringBatteryOptimizations();
      }

      _status = PermissionStatus(
        bluetooth: btStatus.isGranted,
        bluetoothScan: btScanStatus.isGranted,
        bluetoothConnect: btConnectStatus.isGranted,
        notification: notifStatus.isGranted,
        overlay: overlayGranted,
        batteryOptimization: batteryGranted,
        bootComplete:
            true, // System permission usually, we just track if we should show it
        backgroundPersistence: true,
      );
    } catch (e, stack) {
      AppLogger.instance.log(
        'Không kiểm tra được đầy đủ quyền hệ thống: $e',
        type: 'permission_error',
        userMessage:
            'Không thể kiểm tra một số quyền của thiết bị. Hãy mở phần Quyền hệ thống để kiểm tra lại.',
        details: {'error': e.toString(), 'stack': stack.toString()},
      );
    }

    _isChecking = false;
    notifyListeners();
  }

  Future<bool> requestBluetoothPermissions() async {
    final result = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final allGranted = result.values.every((s) => s.isGranted);
    await checkAllPermissions();
    return allGranted;
  }

  Future<bool> requestNotificationPermission() async {
    final result = await Permission.notification.request();
    await checkAllPermissions();
    return result.isGranted;
  }

  Future<bool> requestOverlayPermission() async {
    await FlutterOverlayWindow.requestPermission();
    await checkAllPermissions();
    return _status.overlay;
  }

  /// Mở màn hình Cài đặt "Tối ưu hoá pin" để người dùng tự tắt cho app.
  /// ⚠️ TUÂN THỦ CHÍNH SÁCH PLAY: không dùng hộp thoại cấp quyền trực tiếp
  ///    (Permission.ignoreBatteryOptimizations.request) vì Google hạn chế. App
  ///    vẫn ĐỌC được trạng thái qua Permission.ignoreBatteryOptimizations.status.
  Future<bool> requestBatteryOptimizationPermission() async {
    if (Platform.isAndroid) {
      await ServiceChannel.instance.showBatteryOptimizationSettings();
    }
    await checkAllPermissions();
    return _status.batteryOptimization;
  }

  Future<bool> requestBackgroundExecutionPermissions() async {
    // 1. Notification
    await requestNotificationPermission();
    // 2. Battery
    await requestBatteryOptimizationPermission();

    await checkAllPermissions();
    return _status.notification && _status.batteryOptimization;
  }

  Future<void> requestAllPermissionsForMode(String mode) async {
    if (mode == 'phone_bluetooth') {
      await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
        Permission.notification,
      ].request();
      if (!_status.overlay) {
        await FlutterOverlayWindow.requestPermission();
      }
    } else if (mode == 'phone_android_auto') {
      // 🟢 Android Auto KHÔNG DÂY bắt tay qua Bluetooth → cần BLUETOOTH_CONNECT/SCAN để
      //    BluetoothReceiver nhận được ACL_CONNECTED và đọc thiết bị (Android 12+). Thiếu
      //    quyền này khiến auto-play khi kết nối AA không hoạt động.
      await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.notification,
      ].request();
      if (!_status.overlay) {
        await FlutterOverlayWindow.requestPermission();
      }
    } else if (mode == 'android_box_mode') {
      await Permission.notification.request();
      // ⚠️ Mở Cài đặt tối ưu pin thay vì hộp thoại cấp trực tiếp (chính sách Play).
      await ServiceChannel.instance.showBatteryOptimizationSettings();
      if (!_status.overlay) {
        await FlutterOverlayWindow.requestPermission();
      }
    }
    await checkAllPermissions();
  }

  Future<void> openSettings() async {
    if (Platform.isAndroid) {
      final ServiceChannel sc = ServiceChannel.instance;
      await sc.showAutostartSettings();
    } else {
      await openAppSettings();
    }
  }
}
