---
name: fix-by-connection-mode
description: Apply or review auto-play fixes scoped to phone_bluetooth, phone_android_auto, android_screen_mode, android_box_mode, or ios_carplay. Use when changing A2DP watch, CarConnection, BootReceiver, play-on-open, overlay, MediaSession, or Shortcuts. Enforces wait-don't-cancel on slow devices. Box details in skill android-box-boot-play.
---

# Fix by connection mode (v7)

1. Read prefs `connection_mode` and pick **one** owner (see `AGENTS.md`).
2. Change only that mode; regression-check the others with the checklist.
3. Read [`.cursor/rules/connection-modes.mdc`](../../rules/connection-modes.mdc).

## Wait, don’t cancel

If the car/phone is slow, keep the pending play action alive until the route/session is ready. Do not drop `ACTION_BT_WATCH_A2DP`, `ACTION_AA_WATCH_PROJECTION`, `ACTION_BOOT_RETRY_GREETING`, boot readiness poll, or a Shortcuts intent just because a timer fired.

## Checklist

- [ ] `phone_bluetooth` (Android): native A2DP watch owns play; Flutter `onTargetConnected` does not `playGreetingViaNative`; play when A2DP is ready **or wait**; no abort on slow HU
- [ ] iOS Bluetooth: same greeting as CarPlay; Shortcuts “When Bluetooth connects” plays immediately or waits — see `ios-carplay-shortcuts`
- [ ] `phone_android_auto`: **not** the BT flow; MediaSession; wired + wireless; one play per projection; slow cars wait; do not cancel the watch
- [ ] `android_screen_mode`: play on open + resume; overlay after back; bubble survives YouTube — see `overlay-keepalive-headunit`
- [ ] `android_box_mode`: native boot only; Direct Boot `boot_greeting.mp3`; `BOOT_COUNT` session; poll + alarms; Flutter open skip; FGS `specialUse` from boot — see `android-box-boot-play`
- [ ] `ios_carplay`: greeting set in-app, then CarPlay **or** Bluetooth automation

## Files

- BT Android: `BluetoothReceiver.kt`, `ACTION_BT_WATCH_A2DP`
- AA: CarConnection monitor, `ACTION_AA_WATCH_PROJECTION`, `updateMediaSessionState`
- Screen: `lib/main.dart` `_initPlayOnOpen` / `_maybePlayGreetingOnResume` / overlay lifecycle
- Box: `BootReceiver.kt`, `BootSessionManager.kt`, boot watch + `specialUse` in `AudioForegroundService.kt`, `HiCarPlugin` copy boot file
- iOS: `ios/Runner/AppDelegate.swift` App Intents + `HiCarAudioPlayer`
