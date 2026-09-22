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

void main() {
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
}
