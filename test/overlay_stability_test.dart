import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hi_car/core/logger.dart';
import 'package:hi_car/providers/overlay_provider.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('x-slayer/overlay_channel');
  late bool allowed;
  late bool active;
  Completer<void>? showing;
  setUp(() async {
    await AppLogger.instance.flush();
    SharedPreferences.setMockInitialValues({
      'connection_mode': 'android_screen_mode',
      'auth_token': 'test',
      'is_bubble_enabled': true,
    });
    allowed = true;
    active = false;
    showing = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      switch (call.method) {
        case 'checkPermission':
          return allowed;
        case 'isOverlayActive':
          return active;
        case 'showOverlay':
          await showing?.future;
          active = true;
          return true;
        case 'closeOverlay':
          active = false;
          return true;
        default:
          return null;
      }
    });
  });
  tearDown(() async {
    await AppLogger.instance.flush();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
  test('temporary permission denial cannot erase saved bubble preference',
      () async {
    allowed = false;
    final provider = OverlayProvider.forTest();
    await provider.init();
    expect(provider.isBubbleEnabled, isTrue);
    expect((await SharedPreferences.getInstance()).getBool('is_bubble_enabled'),
        isTrue);
    allowed = true;
    await provider.showOverlay();
    expect(active, isTrue);
    provider.dispose();
  });
  test('resume/hide wins a slow background show request', () async {
    final provider = OverlayProvider.forTest();
    await provider.init();
    showing = Completer<void>();
    final show = provider.showOverlay();
    await Future<void>.delayed(Duration.zero);
    final hide = provider.hideOverlay();
    showing!.complete();
    await Future.wait([show, hide]);
    expect(active, isFalse);
    provider.dispose();
  });
  for (final mode in [
    'phone_bluetooth',
    'phone_android_auto',
    'android_box_mode',
    'ios_carplay'
  ]) {
    test('bubble never starts in $mode', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('connection_mode', mode);
      final provider = OverlayProvider.forTest();
      await provider.showOverlay();
      expect(active, isFalse);
      provider.dispose();
    });
  }
}
