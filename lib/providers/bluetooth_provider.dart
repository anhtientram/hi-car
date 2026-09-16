import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../data/models/bluetooth_device_model.dart';
import '../native/bluetooth_channel.dart';

class BluetoothProvider extends ChangeNotifier {
  List<BluetoothDeviceModel> _pairedDevices = [];
  BluetoothDeviceModel? _targetDevice;
  int _delaySeconds = AppConstants.defaultDelaySeconds;
  bool _isLoading = false;
  String? _error;
  List<BluetoothDeviceModel> _scannedDevices = [];
  bool _isScanning = false;
  final Map<String, bool> _connectingDevices = {};
  Future<bool> Function()? onTargetConnected;

  List<BluetoothDeviceModel> get pairedDevices => _pairedDevices;
  BluetoothDeviceModel? get targetDevice => _targetDevice;
  int get delaySeconds => _delaySeconds;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasTargetDevice => _targetDevice != null;
  List<BluetoothDeviceModel> get scannedDevices => _scannedDevices;
  bool get isScanning => _isScanning;
  Map<String, bool> get connectingDevices => _connectingDevices;

  BluetoothDeviceModel? get connectedDevice {
    for (final device in _pairedDevices) {
      if (device.isConnected) return device;
    }
    return null;
  }

  // ===== Init =====

  Future<void> init() async {
    BluetoothChannel.instance.init();

    BluetoothChannel.instance
        .setConnectionChangeHandler((address, action) async {
      await loadPairedDevices(showSpinner: false);

      debugPrint(
          'BT Handler: action=$action, incoming=$address, target=${_targetDevice?.address}');

      if (action == 'connected') {
        // Nối từ Cài đặt hệ thống / màn xe: nhận diện ngay, không bắt user chọn lại trong app.
        final hadTarget =
            _targetDevice != null && _targetDevice!.address.isNotEmpty;
        await adoptConnectedDeviceIfNeeded(incomingAddress: address);
        // Native có thể đã bỏ qua ACL vì lúc đó chưa có target — bật watch sau khi đã nhận xe.
        if (!hadTarget &&
            _targetDevice?.address.toLowerCase() == address.toLowerCase()) {
          await BluetoothChannel.instance.watchA2dp(address);
        }
      }

      if (action == 'connected' &&
          _targetDevice?.address.toLowerCase() == address.toLowerCase()) {
        final prefs = await SharedPreferences.getInstance();
        final mode = prefs.getString('connection_mode') ?? '';
        if (mode != 'phone_bluetooth') {
          debugPrint(
              'BT Handler: MATCH nhưng mode=$mode → bỏ qua (AA/Box do native xử lý)');
          return;
        }
        debugPrint('BT Handler: MATCH FOUND, triggering greeting...');
        if (onTargetConnected != null) {
          await onTargetConnected!();
        } else {
          debugPrint('BT Handler: onTargetConnected chưa gán → bỏ qua');
        }
      }
    });

    await _loadSavedTarget();
    await loadPairedDevices();
    await adoptConnectedDeviceIfNeeded();

    BluetoothChannel.instance.setDiscoveryHandler((raw) async {
      final device = BluetoothDeviceModel.fromMap(raw);
      debugPrint('Found Bluetooth device: ${device.name} (${device.address})');
      if (!_pairedDevices.any((d) => d.address == device.address) &&
          !_scannedDevices.any((d) => d.address == device.address)) {
        _scannedDevices.add(device);
        notifyListeners();
      }
    }, () async {
      _isScanning = false;
      await loadPairedDevices(showSpinner: false);
      notifyListeners();
    });
  }

  /// App vừa ra tiền cảnh: đọc lại trạng thái BT (có thể đã nối/ngắt ngoài app).
  Future<void> refreshOnForeground() async {
    await loadPairedDevices(showSpinner: false);
    await adoptConnectedDeviceIfNeeded();
  }

  /// Nếu chưa chọn xe tự phát mà hệ thống đang nối một thiết bị đã ghép → nhận luôn.
  Future<void> adoptConnectedDeviceIfNeeded({String? incomingAddress}) async {
    if (_targetDevice != null && _targetDevice!.address.isNotEmpty) return;

    BluetoothDeviceModel? candidate;
    if (incomingAddress != null && incomingAddress.isNotEmpty) {
      candidate = _deviceByAddress(incomingAddress) ??
          BluetoothDeviceModel(
            name: incomingAddress,
            address: incomingAddress,
            isConnected: true,
          );
    } else {
      candidate = connectedDevice;
    }
    if (candidate == null || candidate.address.isEmpty) return;

    debugPrint(
        'BT: tự nhận thiết bị đang nối ${candidate.name} (${candidate.address})');
    await setTargetDevice(candidate);
  }

  // ===== Load Paired Devices =====

  Future<void> loadPairedDevices({bool showSpinner = true}) async {
    if (showSpinner) {
      _isLoading = true;
      _error = null;
      notifyListeners();
    }

    try {
      final rawDevices = await BluetoothChannel.instance.getPairedDevices();
      _pairedDevices = rawDevices.map((raw) {
        final device = BluetoothDeviceModel.fromMap(raw);
        return device.copyWith(
          isSelected: device.address.toLowerCase() ==
              (_targetDevice?.address.toLowerCase() ?? ''),
        );
      }).toList();
    } catch (e) {
      _error = 'Không thể lấy danh sách thiết bị Bluetooth';
    }

    _isLoading = false;
    notifyListeners();
  }

  // ===== Scan Devices =====

  Future<void> startScan() async {
    if (_isScanning) return;
    _isScanning = true;
    _scannedDevices.clear();
    notifyListeners();

    final started = await BluetoothChannel.instance.startDiscovery();
    if (!started) {
      _isScanning = false;
      _error = 'Không thể bắt đầu tìm kiếm';
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    if (!_isScanning) return;
    await BluetoothChannel.instance.stopDiscovery();
    _isScanning = false;
    notifyListeners();
  }

  // ===== Toggle Connection =====

  Future<void> toggleDeviceConnection(BluetoothDeviceModel device) async {
    final address = device.address;
    if (_connectingDevices[address] == true) return;

    _connectingDevices[address] = true;
    notifyListeners();

    try {
      if (device.isConnected) {
        await BluetoothChannel.instance.disconnectDevice(address);
        _pairedDevices = _pairedDevices
            .map((d) =>
                d.address == address ? d.copyWith(isConnected: false) : d)
            .toList();
        notifyListeners();
      } else {
        await setTargetDevice(device);
        await BluetoothChannel.instance.connectDevice(address);
      }

      await Future.delayed(const Duration(milliseconds: 2000));
      await loadPairedDevices(showSpinner: false);
    } catch (_) {
    } finally {
      _connectingDevices.remove(address);
      notifyListeners();
    }
  }

  // ===== Set Target Device =====

  Future<void> setTargetDevice(BluetoothDeviceModel device) async {
    _targetDevice = device.copyWith(isSelected: true);

    _pairedDevices = _pairedDevices.map((d) {
      return d.copyWith(
          isSelected: d.address.toLowerCase() == device.address.toLowerCase());
    }).toList();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyTargetDeviceAddress, device.address);
    await prefs.setString(AppConstants.keyTargetDeviceName, device.name);

    await BluetoothChannel.instance.setTargetDevice(
      address: device.address,
      delay: _delaySeconds,
    );

    notifyListeners();
  }

  Future<void> clearTargetDevice() async {
    _targetDevice = null;
    _pairedDevices =
        _pairedDevices.map((d) => d.copyWith(isSelected: false)).toList();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.keyTargetDeviceAddress);
    await prefs.remove(AppConstants.keyTargetDeviceName);

    await BluetoothChannel.instance.clearTargetDevice();
    notifyListeners();
  }

  // ===== Set Delay =====

  Future<void> setDelaySeconds(int seconds) async {
    _delaySeconds = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.keyDelaySeconds, seconds);

    if (_targetDevice != null) {
      await BluetoothChannel.instance.setTargetDevice(
        address: _targetDevice!.address,
        delay: seconds,
      );
    }
    notifyListeners();
  }

  // ===== Private =====

  Future<void> _loadSavedTarget() async {
    final prefs = await SharedPreferences.getInstance();
    final address = prefs.getString(AppConstants.keyTargetDeviceAddress) ?? '';
    final name = prefs.getString(AppConstants.keyTargetDeviceName) ?? '';
    _delaySeconds = prefs.getInt(AppConstants.keyDelaySeconds) ??
        AppConstants.defaultDelaySeconds;

    if (address.isNotEmpty) {
      _targetDevice =
          BluetoothDeviceModel(name: name, address: address, isSelected: true);
    }
    notifyListeners();
  }

  BluetoothDeviceModel? _deviceByAddress(String address) {
    for (final device in _pairedDevices) {
      if (device.address.toLowerCase() == address.toLowerCase()) return device;
    }
    return null;
  }
}
