---
name: ios-carplay-shortcuts
description: Make iOS greeting play on CarPlay connect or Bluetooth connect via Shortcuts automations. Use when CarPlay/Bluetooth automation is silent, plays late then aborts, or only works if the app is open.
---

# iOS CarPlay / Bluetooth Shortcuts

## Required user path

1. Set nhạc chào in-app (path stored as `flutter.greeting_audio_path`).
2. Open Shortcuts → Personal Automation → **CarPlay “When Connected”** **or** **Bluetooth “Device connects”**.
3. Action **Phát lời chào HiCar**, Ask Before Running off.
4. On connect: play immediately, **or wait** until car audio is ready. Do not fail.

Same App Intent serves both automations. No second in-app mode.

## Diagnose

| Symptom | Likely cause |
|---------|----------------|
| “Chưa cấu hình lời chào” | Greeting not pinned / UserDefaults key missing |
| Silent connect | Session not `.playback`, route not to car yet, intent aborted |
| Works only in foreground | `openAppWhenRun` or background audio missing |
| File not found after update | Absolute path stale — use `resolvePath` lastPathComponent fallback |

## Fix rules

Read [`.cursor/rules/ios-carplay.mdc`](../../rules/ios-carplay.mdc).

- Configure session at launch **and** in `perform()`.
- If route/session not ready: wait/retry, don’t return false and give up.
- Do not implement Android A2DP watch on iOS.

## Files

- `ios/Runner/AppDelegate.swift` — `PlayGreetingIntent`, `HiCarAudioPlayer`
- `lib/screens/setup/connection_mode_screen.dart` — guide copy
- `lib/screens/setup/permission_config_screen.dart`
