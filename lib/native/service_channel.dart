import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../core/logger.dart';
import '../core/utils/device_utils.dart';

/// Flutter → Kotlin bridge for AudioForegroundService control
class ServiceChannel {
  ServiceChannel._();
  static final ServiceChannel instance = ServiceChannel._();

  static const _channel = MethodChannel(AppConstants.serviceChannel);
  VoidCallback? onPlaybackComplete;
  void Function(String type)? onPlaybackStarted;

  void init() {
    _channel.setMethodCallHandler((call) async {
      debugPrint('ServiceChannel: Received method call: ${call.method}');
      if (call.method == 'onPlaybackComplete') {
        onPlaybackComplete?.call();
      } else if (call.method == 'onPlaybackStarted') {
        onPlaybackStarted?.call(call.arguments?.toString() ?? 'greeting');
      } else if (call.method == 'onNativeError') {
        final message =
            call.arguments?.toString() ?? 'Lỗi không xác định từ Native';
        final prefs = await SharedPreferences.getInstance();
        final device = await DeviceUtils.getDeviceContext();
        AppLogger.instance.log(
          'LỖI NATIVE: $message',
          type: 'native_error',
          userMessage:
              'Thiết bị hoặc kết nối xe vừa báo lỗi. Hãy thử lại hoặc gửi báo cáo.',
          requiresAction: true,
          details: {
            'source': 'native_method_channel',
            'native_message': message,
            'mode': prefs.getString('connection_mode') ?? 'unknown',
            'device_name': device['device_name'],
            'device_model': device['device_model'],
            'os_version': device['os_version'],
          },
        );
      }
    });
  }

  Future<void> startService() async {
    try {
      await _channel.invokeMethod('startService');
    } on PlatformException catch (e) {
      debugPrint('ServiceChannel: startService error: $e');
      AppLogger.instance.log(
        'Native startService lỗi: ${e.message}',
        type: 'native_error',
        details: {'code': e.code, 'details': e.details?.toString()},
      );
    } on MissingPluginException catch (e) {
      debugPrint('ServiceChannel: startService missing plugin: $e');
      AppLogger.instance.log(
        'Plugin Service chưa đăng ký (startService): $e',
        type: 'native_error',
      );
    }
  }

  Future<void> stopService() async {
    try {
      await _channel.invokeMethod('stopService');
    } on PlatformException catch (e) {
      debugPrint('ServiceChannel: stopService error: $e');
      AppLogger.instance.log(
        'Native stopService lỗi: ${e.message}',
        type: 'native_error',
        details: {'code': e.code},
      );
    } on MissingPluginException catch (e) {
      debugPrint('ServiceChannel: stopService missing plugin: $e');
    }
  }

  Future<void> playGreeting({required String audioPath}) async {
    try {
      await _channel.invokeMethod('playGreeting', {'audioPath': audioPath});
    } on PlatformException catch (e) {
      debugPrint('ServiceChannel: playGreeting error: $e');
      AppLogger.instance.log(
        'Native playGreeting lỗi: ${e.message}',
        type: 'native_error',
        details: {'code': e.code, 'audioPath': audioPath},
      );
      rethrow;
    } on MissingPluginException catch (e) {
      debugPrint('ServiceChannel: playGreeting missing plugin: $e');
      AppLogger.instance.log(
        'Plugin Service chưa đăng ký (playGreeting): $e',
        type: 'native_error',
      );
      rethrow;
    }
  }

  /// Tạo playback job mới từ incident popup. Android Box đi lại qua Boot/session
  /// owner; các mode còn lại gửi play greeting bình thường.
  Future<bool> retryGreeting({String? audioPath}) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'retryGreeting',
        {'audioPath': audioPath ?? ''},
      );
      return result ?? false;
    } catch (e) {
      AppLogger.instance.log(
        'Không tạo được playback retry: $e',
        type: 'native_error',
        userMessage:
            'Không thể thử lại lúc này. Hãy kiểm tra quyền và kết nối xe.',
        requiresAction: true,
        details: {'error': e.toString()},
      );
      return false;
    }
  }

  Future<void> playGoodbye({required String audioPath}) async {
    try {
      await _channel.invokeMethod('playGoodbye', {'audioPath': audioPath});
    } on PlatformException catch (e) {
      debugPrint('ServiceChannel: playGoodbye error: $e');
      AppLogger.instance.log(
        'Native playGoodbye lỗi: ${e.message}',
        type: 'native_error',
        details: {'code': e.code, 'audioPath': audioPath},
      );
    } on MissingPluginException catch (e) {
      debugPrint('ServiceChannel: playGoodbye missing plugin: $e');
      AppLogger.instance.log(
        'Plugin Service chưa đăng ký (playGoodbye): $e',
        type: 'native_error',
      );
    }
  }

  Future<void> stopAudio() async {
    try {
      await _channel.invokeMethod('stopAudio');
    } on PlatformException catch (e) {
      debugPrint('ServiceChannel: stopAudio error: $e');
      AppLogger.instance.log(
        'Native stopAudio lỗi: ${e.message}',
        type: 'native_error',
        details: {'code': e.code},
      );
    } on MissingPluginException catch (e) {
      debugPrint('ServiceChannel: stopAudio missing plugin: $e');
    }
  }

  Future<void> showAutostartSettings() async {
    try {
      await _channel.invokeMethod('showAutostartSettings');
    } catch (e) {
      debugPrint('ServiceChannel: showAutostartSettings error: $e');
    }
  }

  /// Mở màn hình "Tối ưu hoá pin" của hệ thống để người dùng tự tắt cho app.
  /// Cách hợp lệ với Google Play (không dùng hộp thoại cấp quyền trực tiếp).
  Future<void> showBatteryOptimizationSettings() async {
    try {
      await _channel.invokeMethod('showBatteryOptimizationSettings');
    } catch (e) {
      debugPrint('ServiceChannel: showBatteryOptimizationSettings error: $e');
    }
  }

  /// Trạng thái "Không hạn chế" từ PowerManager (chính xác hơn permission_handler).
  Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return result ?? false;
    } catch (e) {
      debugPrint('ServiceChannel: isIgnoringBatteryOptimizations error: $e');
      return false;
    }
  }

  Future<void> minimizeApp() async {
    try {
      await _channel.invokeMethod('minimizeApp');
    } catch (e) {
      debugPrint('ServiceChannel: minimizeApp error: $e');
    }
  }

  Future<void> openApp() async {
    try {
      await _channel.invokeMethod('openApp');
    } on PlatformException catch (e) {
      debugPrint('ServiceChannel: openApp error: $e');
    } on MissingPluginException catch (e) {
      debugPrint('ServiceChannel: openApp missing plugin: $e');
    }
  }

  Future<void> clearGreetingConfig() async {
    try {
      await _channel.invokeMethod('clearGreetingConfig');
    } on PlatformException catch (e) {
      debugPrint('ServiceChannel: clearGreetingConfig error: $e');
    } on MissingPluginException catch (e) {
      debugPrint('ServiceChannel: clearGreetingConfig missing plugin: $e');
    }
  }

  Future<void> clearGoodbyeConfig() async {
    try {
      await _channel.invokeMethod('clearGoodbyeConfig');
    } on PlatformException catch (e) {
      debugPrint('ServiceChannel: clearGoodbyeConfig error: $e');
    } on MissingPluginException catch (e) {
      debugPrint('ServiceChannel: clearGoodbyeConfig missing plugin: $e');
    }
  }

  /// Xoá token đăng nhập (auth_token, user_data) khỏi cả prefs thường VÀ vùng
  /// device-protected. Dùng khi đăng xuất để boot/khởi động lại không tự phát nhạc.
  Future<void> clearAuthState() async {
    try {
      await _channel.invokeMethod('clearAuthState');
    } on PlatformException catch (e) {
      debugPrint('ServiceChannel: clearAuthState error: $e');
    } on MissingPluginException catch (e) {
      debugPrint('ServiceChannel: clearAuthState missing plugin: $e');
    }
  }

  Future<void> syncPrefs() async {
    try {
      await _channel.invokeMethod('syncPrefs');
    } on PlatformException catch (e) {
      debugPrint('ServiceChannel: syncPrefs error: $e');
      AppLogger.instance.log(
        'Native syncPrefs lỗi: ${e.message}',
        type: 'native_error',
        details: {'code': e.code, 'details': e.details?.toString()},
      );
    } on MissingPluginException catch (e) {
      debugPrint('ServiceChannel: syncPrefs missing plugin: $e');
      AppLogger.instance.log(
        'Plugin Service chưa đăng ký (syncPrefs): $e',
        type: 'native_error',
      );
    } catch (e) {
      debugPrint('ServiceChannel: syncPrefs unknown error: $e');
      AppLogger.instance.log(
        'syncPrefs lỗi không xác định: $e',
        type: 'native_error',
      );
    }
  }

  Future<String> getDiagnosticLogErrors() async {
    try {
      final result =
          await _channel.invokeMethod<String>('getDiagnosticLogErrors');
      return result ?? '';
    } catch (e) {
      debugPrint('ServiceChannel: getDiagnosticLogErrors error: $e');
      return '';
    }
  }

  Future<String> getDiagnosticLogFull() async {
    try {
      final result =
          await _channel.invokeMethod<String>('getDiagnosticLogFull');
      return result ?? '';
    } catch (e) {
      debugPrint('ServiceChannel: getDiagnosticLogFull error: $e');
      return '';
    }
  }

  Future<bool> hasDiagnosticErrors() async {
    try {
      final result = await _channel.invokeMethod<bool>('hasDiagnosticErrors');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Cầu nối log native → danh sách lỗi trên UI ("Báo cáo lỗi").
  ///
  /// Lỗi native xảy ra LÚC BOOT (BootReceiver/Service chạy khi app chưa mở) chỉ nằm trong file
  /// diagnostic, KHÔNG tự tạo thẻ AppLogger → trước đây danh sách lỗi trống nên không bấm Gửi
  /// được. Hàm này đọc các dòng E/W native và đẩy MỖI lỗi MỚI thành 1 thẻ AppLogger (đúng nút
  /// cũ), kèm adb log đầy đủ khi gửi. Dedup theo nội dung từng dòng để mở lại không bị lặp.
  static const String _kImportedDiagKeys = 'imported_native_diag_keys';

  Future<void> importNativeDiagnostics() async {
    try {
      final raw = await getDiagnosticLogErrors();
      if (raw.trim().isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final importedList =
          prefs.getStringList(_kImportedDiagKeys) ?? <String>[];
      final importedSet = importedList.toSet();
      final mode = prefs.getString('connection_mode') ?? 'unknown';
      final device = await DeviceUtils.getDeviceContext();

      var added = 0;
      for (final line in raw.split('\n')) {
        final isError = line.contains(' E HiCar') ||
            line.contains(' W HiCar') ||
            line.contains('BOOT_PLAYBACK_MISSED');
        if (!isError) continue;

        final key = line.trim();
        if (key.isEmpty || importedSet.contains(key)) continue;

        importedSet.add(key);
        importedList.add(key);
        final isHardError =
            line.contains(' E HiCar') || line.contains('BOOT_PLAYBACK_MISSED');
        AppLogger.instance.log(
          _readableNativeLine(line),
          type: _mapNativeLineType(line),
          userMessage: _userMessageForNativeLine(line),
          incidentId: 'native-${key.hashCode}',
          requiresAction: isHardError,
          details: {
            'source': 'native_diagnostic',
            'mode': mode,
            'device_name': device['device_name'],
            'device_model': device['device_model'],
            'os_version': device['os_version'],
            'native_line': line,
          },
        );
        added++;
      }

      if (added > 0) {
        // Giới hạn key đã import (file native vốn bị cắt ~200 dòng) để prefs không phình.
        final bounded = importedList.length > 200
            ? importedList.sublist(importedList.length - 200)
            : importedList;
        await prefs.setStringList(_kImportedDiagKeys, bounded);
        debugPrint(
            'ServiceChannel: importNativeDiagnostics → +$added thẻ lỗi native');
      }
    } catch (e) {
      debugPrint('ServiceChannel: importNativeDiagnostics error: $e');
    }
  }

  /// Map dòng log native sang loại lỗi UI (đều nằm trong AppLogger.errorTypes để hiện thẻ).
  String _mapNativeLineType(String line) {
    if (line.contains('BOOT_PLAYBACK_MISSED')) return 'native_playback_error';
    if (line.contains('HiCarAudio')) return 'native_playback_error';
    if (line.contains('HiCarSync')) return 'sync_error';
    return 'native_error';
  }

  String _userMessageForNativeLine(String line) {
    final lower = line.toLowerCase();
    if (lower.contains('permission') || lower.contains('securityexception')) {
      return 'Thiết bị đang thiếu quyền cần thiết để kết nối hoặc phát nhạc. Hãy mở phần Quyền ứng dụng và kiểm tra lại.';
    }
    if (lower.contains('a2dp')) {
      return 'Bluetooth đã kết nối nhưng đường tiếng A2DP của xe chưa sẵn sàng.';
    }
    if (lower.contains('projection') || lower.contains('gearhead')) {
      return 'Android Auto chưa sẵn sàng để phát qua hệ thống xe.';
    }
    if (lower.contains('file does not exist') ||
        lower.contains('no valid audio')) {
      return 'Không tìm thấy file nhạc chào trên thiết bị. Hãy mở app và đồng bộ lại audio.';
    }
    if (lower.contains('boot') || lower.contains('direct boot')) {
      return 'Android Box chưa phát được lời chào sau khi khởi động.';
    }
    if (lower.contains('mediaplayer') || lower.contains('audio')) {
      return 'Thiết bị gặp lỗi khi phát âm thanh. Bạn có thể gửi log để kiểm tra model và hệ điều hành.';
    }
    return 'Ứng dụng không hoàn tất được thao tác phát nhạc. Bạn có thể gửi báo lỗi để kiểm tra thiết bị này.';
  }

  /// Rút gọn dòng adb thành thông điệp dễ đọc: "[Lỗi · HiCarBoot] nội dung".
  String _readableNativeLine(String line) {
    final tagMatch = RegExp(r'\b(HiCar\w*|OverlayBridge)\b').firstMatch(line);
    final tag = tagMatch?.group(1) ?? 'Native';
    final level = line.contains(' E HiCar') ? 'Lỗi' : 'Cảnh báo';
    final colonIdx = line.indexOf('$tag: ');
    final body =
        colonIdx >= 0 ? line.substring(colonIdx + tag.length + 2) : line;
    return '[$level · $tag] ${body.trim()}';
  }

  Future<void> clearDiagnosticLog() async {
    try {
      await _channel.invokeMethod('clearDiagnosticLog');
    } catch (e) {
      debugPrint('ServiceChannel: clearDiagnosticLog error: $e');
    }
  }

  /// Inject sample adb-style native log lines for bug-report UI testing.
  Future<void> appendDiagnosticDemo(String scenario) async {
    try {
      await _channel
          .invokeMethod('appendDiagnosticDemo', {'scenario': scenario});
    } catch (e) {
      debugPrint('ServiceChannel: appendDiagnosticDemo error: $e');
    }
  }
}
