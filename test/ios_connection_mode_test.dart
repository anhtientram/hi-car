import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hi_car/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const bluetooth = MethodChannel('com.hicar.ora.limited/bluetooth');
  const service = MethodChannel('com.hicar.ora.limited/service');

  setUp(() {
    for (final channel in [bluetooth, service]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => true);
    }
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    for (final channel in [bluetooth, service]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  test('iPhone migrates a stale Android mode and keeps the greeting', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    SharedPreferences.setMockInitialValues({
      'connection_mode': 'phone_android_auto',
      'greeting_audio_path': '/Documents/hicar_audio/greeting.mp3',
    });
    final settings = SettingsProvider();
    expect(settings.connectionMode, 'ios_carplay');
    await settings.init();
    final prefs = await SharedPreferences.getInstance();
    expect(settings.connectionMode, 'ios_carplay');
    expect(settings.connectionModeLabel, 'iPhone + CarPlay / Bluetooth');
    expect(prefs.getString('connection_mode'), 'ios_carplay');
    expect(prefs.getString('greeting_audio_path'),
        '/Documents/hicar_audio/greeting.mp3');
    await settings.setConnectionMode('phone_android_auto');
    await settings.commitSettings();
    expect(settings.connectionMode, 'ios_carplay');
    expect(prefs.getString('connection_mode'), 'ios_carplay');
    settings.dispose();
  });

  for (final mode in [
    'phone_bluetooth', 'phone_android_auto',
    'android_screen_mode', 'android_box_mode',
  ]) {
    test('Android preserves $mode', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues({'connection_mode': mode});
      final settings = SettingsProvider();
      await settings.init();
      expect(settings.connectionMode, mode);
      expect(settings.connectionModeLabel, isNot(contains('iPhone')));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('connection_mode'), mode);
      settings.dispose();
    });
  }
}
