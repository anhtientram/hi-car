import 'package:flutter_test/flutter_test.dart';
import 'package:hi_car/native/native_diagnostic.dart';

void main() {
  const modes = [
    'phone_bluetooth',
    'phone_android_auto',
    'android_screen_mode',
    'android_box_mode',
    'ios_carplay'
  ];
  test('reported screen-mode error is not labeled Android Box from boot=false',
      () {
    const line =
        '09-25 E HiCarAudio: MediaPlayer error what=100 extra=2 type=greeting boot=false';
    expect(NativeDiagnostic.message(line), isNot(contains('Box')));
    expect(NativeDiagnostic.message(line), contains('âm thanh'));
    expect(NativeDiagnostic.idFor(line), NativeDiagnostic.idFor(line));
  });
  for (final mode in modes) {
    test('$mode preserves mode and only unresolved final errors need action',
        () {
      final line =
          '2026-09-25 E HiCarAudio: job=123 mode=$mode state=failed what=1 extra=-32';
      expect(NativeDiagnostic.modeIn(line), mode);
      expect(NativeDiagnostic.needsAction(line, mode, line), isTrue);
      expect(
          NativeDiagnostic.needsAction(line, mode,
              '$line\nD HiCarAudio: job=123 mode=$mode state=completed'),
          isFalse);
      expect(
          NativeDiagnostic.needsAction(
              line, mode, '$line\nD HiCarAudio: job=999 state=completed'),
          isTrue);
      expect(
          NativeDiagnostic.needsAction(
              line.replaceFirst('state=failed', 'state=retrying'), mode, line),
          isFalse);
    });
  }
  test('old mode error remains in report but does not popup in new mode', () {
    const line = 'E HiCarBoot: mode=android_box_mode BOOT_PLAYBACK_MISSED';
    expect(NativeDiagnostic.needsAction(line, 'android_screen_mode', line),
        isFalse);
  });
  test('readiness warnings are not fatal errors', () {
    expect(
        NativeDiagnostic.needsAction(
            'W HiCarBT: waiting_route', 'phone_bluetooth', ''),
        isFalse);
  });
}
