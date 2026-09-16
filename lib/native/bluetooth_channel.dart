import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../core/logger.dart';

/// Flutter → Kotlin bridge for Bluetooth device management
class BluetoothChannel {
  BluetoothChannel._();
  static final BluetoothChannel instance = BluetoothChannel._();

  static const _channel = MethodChannel(AppConstants.bluetoothChannel);

  Future<dynamic> Function(String address, String action)? _connectionHandler;
  Future<dynamic> Function(Map<dynamic, dynamic> device)? _discoveryHandler;
  VoidCallback? _onDiscoveryFinished;

  void init() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onDeviceConnectionChanged':
          final args = call.arguments as Map<dynamic, dynamic>;
          final address = args['address'] as String;
          final action = args['action'] as String;
          AppLogger.instance
              .log('Bluetooth: $address -> $action', type: 'native_action');
          await _connectionHandler?.call(address, action);
          break;
        case 'onDeviceFound':
          await _discoveryHandler
              ?.call(call.arguments as Map<dynamic, dynamic>);
          break;
        case 'onDiscoveryFinished':
          _onDiscoveryFinished?.call();
          break;
        case 'onNativeError':
          final message = call.arguments?.toString() ?? 'Lỗi Bluetooth Native';
          AppLogger.instance
              .log('LỖI BLUETOOTH NATIVE: $message', type: 'native_error');
          break;
      }
    });
  }

  /// Returns list of paired Bluetooth devices from Android system
  Future<List<Map<dynamic, dynamic>>> getPairedDevices() async {
    try {
      final result =
          await _channel.invokeMethod<List<dynamic>>('getPairedDevices');
      return result?.map((e) => e as Map<dynamic, dynamic>).toList() ?? [];
    } on PlatformException catch (e) {
      AppLogger.instance
          .log('Lỗi Bluetooth getPaired: ${e.message}', type: 'native_error');
      return [];
    }
  }

  /// Starts scanning for nearby Bluetooth devices
  Future<bool> startDiscovery() async {
    try {
      final success = await _channel.invokeMethod<bool>('startDiscovery');
      return success ?? false;
    } on PlatformException catch (e) {
      AppLogger.instance.log('Lỗi Bluetooth startDiscovery: ${e.message}',
          type: 'native_error');
      return false;
    }
  }

  /// Stops scanning for nearby Bluetooth devices
  Future<bool> stopDiscovery() async {
    try {
      final success = await _channel.invokeMethod<bool>('stopDiscovery');
      return success ?? false;
    } on PlatformException catch (e) {
      AppLogger.instance.log('Lỗi Bluetooth stopDiscovery: ${e.message}',
          type: 'native_error');
      return false;
    }
  }

  /// Sets the target device address + delay in the native service
  Future<void> setTargetDevice({
    required String address,
    required int delay,
  }) async {
    try {
      await _channel.invokeMethod('setTargetDevice', {
        'address': address,
        'delay': delay,
      });
    } on PlatformException catch (e) {
      AppLogger.instance
          .log('Lỗi Bluetooth setTarget: ${e.message}', type: 'native_error');
    }
  }

  /// Clears the target device (disables auto-play)
  Future<void> clearTargetDevice() async {
    try {
      await _channel.invokeMethod('clearTargetDevice');
    } on PlatformException catch (e) {
      AppLogger.instance
          .log('Lỗi Bluetooth clearTarget: ${e.message}', type: 'native_error');
    }
  }

  /// Native đợi A2DP rồi phát lời chào (dùng khi vừa tự nhận xe nối từ ngoài app).
  Future<void> watchA2dp(String address) async {
    try {
      await _channel.invokeMethod('watchA2dp', {'address': address});
    } on PlatformException catch (e) {
      AppLogger.instance
          .log('Lỗi Bluetooth watchA2dp: ${e.message}', type: 'native_error');
    }
  }

  /// Initiates A2DP/Headset connection via reflection
  Future<bool> connectDevice(String address) async {
    try {
      final success = await _channel
          .invokeMethod<bool>('connectDevice', {'address': address});
      return success ?? false;
    } on PlatformException catch (e) {
      AppLogger.instance
          .log('Lỗi Bluetooth connect: ${e.message}', type: 'native_error');
      return false;
    }
  }

  /// Initiates A2DP/Headset disconnection via reflection
  Future<bool> disconnectDevice(String address) async {
    try {
      final success = await _channel
          .invokeMethod<bool>('disconnectDevice', {'address': address});
      return success ?? false;
    } on PlatformException catch (e) {
      AppLogger.instance
          .log('Lỗi Bluetooth disconnect: ${e.message}', type: 'native_error');
      return false;
    }
  }

  /// Updates connection mode on native side and SharedPreferences
  Future<void> setConnectionMode(String mode) async {
    try {
      await _channel.invokeMethod('setConnectionMode', {'mode': mode});
    } on PlatformException catch (e) {
      AppLogger.instance
          .log('Lỗi Bluetooth setMode: ${e.message}', type: 'native_error');
    }
  }

  void setConnectionChangeHandler(
      Future<dynamic> Function(String address, String action) handler) {
    _connectionHandler = handler;
  }

  void setDiscoveryHandler(
      Future<dynamic> Function(Map<dynamic, dynamic> device) onDeviceFound,
      VoidCallback onFinished) {
    _discoveryHandler = onDeviceFound;
    _onDiscoveryFinished = onFinished;
  }
}
