import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hi_car/core/logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final logger = AppLogger.instance;
  setUp(() async {
    await logger.flush();
    SharedPreferences.setMockInitialValues({});
    await logger.init();
  });
  tearDown(() async => logger.flush());

  test(
      'actionable errors survive reload with automatically assigned incident ID',
      () async {
    logger.log('failed', type: 'native_error', requiresAction: true);
    final id = logger.activeIncident!.incidentId;
    expect(id, isNotNull);
    await logger.flush();
    await logger.init();
    expect(logger.activeIncident?.incidentId, id);
  });

  test('dismissal survives restart without deleting evidence', () async {
    logger.log('failure', incidentId: 'stable', requiresAction: true);
    logger.dismissIncident();
    await logger.flush();
    await logger.init();
    expect(logger.activeIncident, isNull);
    expect(logger.logs, hasLength(1));
    logger.log('same imported event',
        incidentId: 'stable', requiresAction: true);
    expect(logger.activeIncident, isNull);
  });

  test(
      'burst persistence keeps newest records, and nested secrets are redacted at rest',
      () async {
    for (var i = 0; i < 140; i++) {
      logger.log('event $i Bearer secret AA:BB:CC:DD:EE:FF',
          type: 'native_error',
          details: {
            'nested': [
              {'password': 'secret', 'address': 'AA:BB:CC:DD:EE:FF'}
            ]
          });
    }
    await logger.flush();
    await logger.init();
    expect(logger.logs, hasLength(120));
    expect(logger.logs.first.message, contains('event 139'));
    final raw = (await SharedPreferences.getInstance())
        .getString('hicar_app_diagnostic_logs')!;
    expect(raw, isNot(contains('secret')));
    expect(raw, isNot(contains('AA:BB:CC:DD:EE:FF')));
  });

  test('resolved playback does not resurrect an old popup', () async {
    logger.log('job=123 mode=android_screen_mode failed', requiresAction: true);
    logger.resolvePlaybackJob('123');
    await logger.flush();
    await logger.init();
    expect(logger.activeIncident, isNull);
  });

  test('overlay failure appears in bug list', () {
    logger.log('overlay denied', type: 'overlay_error');
    expect(logger.errorLogs, hasLength(1));
  });
}
