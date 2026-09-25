// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hi_car/core/logger.dart';
import 'package:hi_car/widgets/incident_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLogger.instance.init();
  });
  testWidgets('incident popup shows context and can be dismissed',
      (WidgetTester tester) async {
    AppLogger.instance.clear();

    await tester.pumpWidget(
      MaterialApp(
        home: IncidentOverlay(
          child: const Scaffold(body: Text('HiCar')),
        ),
      ),
    );

    AppLogger.instance.log(
      'Native playback failed',
      type: 'native_playback_error',
      userMessage: 'Không phát được lời chào.',
      incidentId: 'test-incident',
      requiresAction: true,
      details: {
        'mode': 'phone_android_auto',
        'device_name': 'Test Head Unit',
        'os_version': 'Android 12',
      },
    );
    await tester.pump();

    expect(find.text('Không phát được lời chào.'), findsOneWidget);
    expect(find.textContaining('Android Auto'), findsOneWidget);
    expect(find.textContaining('Test Head Unit'), findsOneWidget);
    expect(find.text('Gửi báo lỗi'), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);

    await tester.tap(find.text('Đóng'));
    await tester.pump();
    expect(find.text('Không phát được lời chào.'), findsNothing);

    AppLogger.instance.clear();
  });

  testWidgets('incident remains closable on a small old head-unit display', (tester) async {
    tester.view.physicalSize = const Size(480, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    AppLogger.instance.clear();
    await tester.pumpWidget(MaterialApp(home: IncidentOverlay(child: const Scaffold())));
    AppLogger.instance.log('MediaPlayer error what=100 extra=2 type=greeting boot=false',
        type: 'native_playback_error', requiresAction: true,
        userMessage: 'Bộ phát âm thanh đang gặp vấn đề.',
        details: {'mode': 'android_screen_mode', 'device_model': 'Sprd ums512_1h10_Natv', 'os_version': 'Android 10'});
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Đóng'));
    await tester.pump();
    expect(find.text('Ứng dụng gặp vấn đề'), findsNothing);
    AppLogger.instance.clear();
  });
}
