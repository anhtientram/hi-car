import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hi_car/core/constants.dart';
import 'package:hi_car/core/logger.dart';
import 'package:hi_car/native/service_channel.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(AppConstants.serviceChannel);
  late String full;
  setUp(() async {
    await AppLogger.instance.flush();
    SharedPreferences.setMockInitialValues({'connection_mode': 'android_screen_mode'});
    await AppLogger.instance.init();
    full = '';
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async =>
        call.method == 'getDiagnosticLogFull' ? full : null);
  });
  tearDown(() async {
    await AppLogger.instance.flush();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
  test('native error before Flutter attach is imported once despite long readiness history', () async {
    full = '2026-09-25 E HiCarAudio: job=before-ui mode=android_screen_mode state=failed what=100 extra=2 boot=false\n'
        + List.generate(500, (i) => 'W HiCarAudio: state=waiting_focus checkpoint=$i').join('\n');
    await Future.wait([ServiceChannel.instance.importNativeDiagnostics(),
      ServiceChannel.instance.importNativeDiagnostics()]);
    expect(AppLogger.instance.errorLogs, hasLength(1));
    expect(AppLogger.instance.activeIncident!.userMessage, isNot(contains('Box')));
    expect(AppLogger.instance.activeIncident!.details!['mode_source'], 'event');
    await ServiceChannel.instance.importNativeDiagnostics();
    expect(AppLogger.instance.errorLogs, hasLength(1));
  });
}
