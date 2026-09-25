import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../core/logger.dart';
import '../core/utils/device_utils.dart';
import 'native_diagnostic.dart';

/// Flutter → Kotlin bridge for AudioForegroundService control
class ServiceChannel {
  ServiceChannel._();
  static final ServiceChannel instance = ServiceChannel._();

  static const _channel = MethodChannel(AppConstants.serviceChannel);
  VoidCallback? onPlaybackComplete;
  void Function(String type)? onPlaybackStarted;
  VoidCallback? onPlaybackFailed;
  void Function(String type)? onPlaybackPending;

  void init() {
    _channel.setMethodCallHandler((call) async {
      debugPrint('ServiceChannel: Received method call: ${call.method}');
      if (call.method == 'onPlaybackComplete') {
        onPlaybackComplete?.call();
      } else if (call.method == 'onPlaybackStarted') {
        onPlaybackStarted?.call(call.arguments?.toString() ?? 'greeting');
      } else if (call.method == 'onPlaybackPending') {
        onPlaybackPending?.call(call.arguments?.toString() ?? 'greeting');
      } else if (call.method == 'onPlaybackFailed') {
        onPlaybackFailed?.call();
      } else if (call.method == 'onPlaybackResolved') {
        AppLogger.instance.resolvePlaybackJob(call.arguments.toString());
      } else if (call.method == 'onNativeError') {
        final message =
            call.arguments?.toString() ?? 'Lỗi không xác định từ Native';
        final prefs = await SharedPreferences.getInstance();
        final device = await DeviceUtils.getDeviceContext();
        AppLogger.instance.log(
          'LỖI NATIVE: $message',
          type: 'native_error',
          userMessage: NativeDiagnostic.message(message),
          incidentId: NativeDiagnostic.idFor(message),
          requiresAction: true,
          details: {
            'source': 'native_method_channel',
            'native_message': message,
            'mode': prefs.getString('connection_mode') ?? 'unknown',
            'device_name': device['device_name'],
            'device_model': device['device_model'],
            'os_version': device['os_version'],
            'metadata_errors': device['metadata_errors'],
          },
        );
      }
    });
  }

  Future<Map<String, dynamic>?> getPlaybackStatus() async {
    try {
      return await _channel
          .invokeMapMethod<String, dynamic>('getPlaybackStatus');
    } catch (e) {
      AppLogger.instance.log('Không đọc được trạng thái native playback: $e',
          type: 'native_error', details: {'operation': 'getPlaybackStatus'});
      return null;
    }
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

  Future<void> playGreeting(
      {required String audioPath, bool automatic = false}) async {
    try {
      final accepted = await _channel.invokeMethod<bool>(
          'playGreeting', {'audioPath': audioPath, 'automatic': automatic});
      if (accepted == false)
        throw PlatformException(
            code: 'PLAYBACK_REJECTED', message: 'Native từ chối phát lời chào');
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
      final accepted = await _channel
          .invokeMethod<bool>('playGoodbye', {'audioPath': audioPath});
      if (accepted == false)
        throw PlatformException(
            code: 'PLAYBACK_REJECTED',
            message: 'Native từ chối phát lời tạm biệt');
    } on PlatformException catch (e) {
      debugPrint('ServiceChannel: playGoodbye error: $e');
      AppLogger.instance.log(
        'Native playGoodbye lỗi: ${e.message}',
        type: 'native_error',
        details: {'code': e.code, 'audioPath': audioPath},
      );
      rethrow;
    } on MissingPluginException catch (e) {
      debugPrint('ServiceChannel: playGoodbye missing plugin: $e');
      AppLogger.instance.log(
        'Plugin Service chưa đăng ký (playGoodbye): $e',
        type: 'native_error',
      );
      rethrow;
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
  Future<void>? _importing;

  Future<void> importNativeDiagnostics() => _importing ??=
      _importNativeDiagnostics().whenComplete(() => _importing = null);

  Future<void> _importNativeDiagnostics() async {
    try {
      final raw = await getDiagnosticLogFull();
      if (raw.trim().isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final importedList =
          prefs.getStringList(_kImportedDiagKeys) ?? <String>[];
      final importedSet = importedList.toSet();
      final mode = prefs.getString('connection_mode') ?? 'unknown';
      final device = await DeviceUtils.getDeviceContext();

      var added = 0;
      for (final line in raw.split('\n')) {
        // Readiness warnings remain in the full timeline, but must not evict real bugs
        // from the bounded in-app bug list during a long/overnight wait.
        if (line.contains(' W ') && RegExp(
            r'state=waiting_|focus_pending|SESSION_WAIT|route_or_file_pending|chưa sẵn sàng|vẫn đang chờ|CarConnection unavailable')
            .hasMatch(line)) continue;
        final isError = line.contains(' E HiCar') ||
            line.contains(' W HiCar') ||
            line.contains(' E OverlayBridge') ||
            line.contains(' W OverlayBridge') ||
            line.contains('BOOT_PLAYBACK_MISSED');
        if (!isError) continue;

        final key = line.trim();
        if (key.isEmpty || importedSet.contains(key)) continue;

        importedSet.add(key);
        importedList.add(key);
        final isHardError = NativeDiagnostic.needsAction(line, mode, raw);
        AppLogger.instance.log(
          _readableNativeLine(line),
          type: _mapNativeLineType(line),
          userMessage: NativeDiagnostic.message(line),
          incidentId: NativeDiagnostic.idFor(key),
          requiresAction: isHardError,
          details: {
            'source': 'native_diagnostic',
            'mode': NativeDiagnostic.modeIn(line) ?? mode,
            'current_mode': mode,
            'mode_source':
                NativeDiagnostic.modeIn(line) == null ? 'import_time' : 'event',
            'device_name': device['device_name'],
            'device_model': device['device_model'],
            'os_version': device['os_version'],
            'metadata_errors': device['metadata_errors'],
            'native_line': line,
          },
        );
        added++;
      }

      if (added > 0) {
        // Giới hạn key đã import (file native vốn bị cắt ~200 dòng) để prefs không phình.
        final bounded = importedList.length > 2000
            ? importedList.sublist(importedList.length - 2000)
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
