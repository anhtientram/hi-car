import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hi_car/core/constants.dart';
import 'package:hi_car/core/logger.dart';
import 'package:hi_car/providers/audio_provider.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(AppConstants.serviceChannel);
  late Map<String, dynamic> status;
  late int plays;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLogger.instance.init();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'greeting_audio_path': '/test.mp3',
      'connection_mode': 'android_screen_mode'
    });
    plays = 0;
    status = {
      'state': 'playing',
      'type': 'greeting',
      'durationMs': 74815,
      'jobId': 'test-job'
    };
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'playGreeting') {
        plays++;
        return true;
      }
      if (call.method == 'getPlaybackStatus') return status;
      return true;
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.ryanheise.audio_session'), (_) async => null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.ryanheise.just_audio.methods'),
        (_) async => <String, dynamic>{});
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets(
      '74-second greeting never becomes completed from a 15-second fallback',
      (tester) async {
    final provider = AudioProvider();
    var completions = 0;
    provider.onNativePlaybackComplete = (manual) {
      if (!manual) completions++;
    };
    expect(await provider.playGreetingViaNative(), isTrue);
    await tester.pump(const Duration(seconds: 80));
    expect(completions, 0);
    expect(provider.isNativePlaybackBusy, isTrue);
    status = {'state': 'completed', 'type': 'greeting'};
    await provider.reconcileNativePlayback();
    expect(completions, 1);
    expect(provider.isNativePlaybackBusy, isFalse);
    provider.dispose();
    await tester.pump();
  });

  testWidgets(
      'open/resume racing during path lookup only send one native command',
      (tester) async {
    final provider = AudioProvider();
    final first = provider.playGreetingViaNative();
    final second = provider.playGreetingViaNative();
    await Future.wait([first, second]);
    expect(plays, 1);
    provider.dispose();
    await tester.pump();
  });

  for (final state in ['failed', 'cancelled', 'idle']) {
    testWidgets('$state does not report successful completion or minimize',
        (tester) async {
      final provider = AudioProvider();
      var completed = false;
      provider.onNativePlaybackComplete = (manual) {
        completed |= !manual;
      };
      await provider.playGreetingViaNative();
      status = {'state': state};
      await provider.reconcileNativePlayback();
      expect(completed, isFalse);
      expect(provider.isNativePlaybackBusy, isFalse);
      provider.dispose();
      await tester.pump(const Duration(seconds: 3));
    });
  }

  testWidgets('waiting route remains pending well beyond 90 seconds',
      (tester) async {
    final provider = AudioProvider();
    await provider.playGreetingViaNative();
    status = {'state': 'waiting_route', 'type': 'greeting'};
    await tester.pump(const Duration(minutes: 10));
    expect(provider.isNativePlaybackBusy, isTrue);
    expect(provider.isNativeGreetingPlaying, isFalse);
    provider.dispose();
    await tester.pump();
  });

  for (final mode in [
    'phone_bluetooth',
    'phone_android_auto',
    'android_box_mode',
    'ios_carplay'
  ]) {
    testWidgets('Flutter cannot own automatic play-on-open for $mode',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'connection_mode': mode,
        'auth_token': 'test',
        'greeting_audio_path': '/test.mp3'
      });
      final provider = AudioProvider();
      expect(await provider.playGreetingViaNative(allowAutostartRetry: true),
          isFalse);
      expect(plays, 0);
      provider.dispose();
      await tester.pump();
    });
  }
}
