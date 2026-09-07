---
name: fix-by-connection-mode
description: Apply or review audio/auto-play fixes scoped to phone_bluetooth, phone_android_auto, android_screen_mode, or android_box_mode. Use when changing BootReceiver, A2DP watch, CarConnection, play-on-open, or MediaSession.
---

# Fix by connection mode

1. Đọc prefs `connection_mode` và xác định **một** owner phát (xem `AGENTS.md` bảng modes).
2. Chỉ sửa nhánh mode đó; regression-check 3 mode còn lại bằng checklist dưới.
3. Đọc [`.cursor/rules/connection-modes.mdc`](../../rules/connection-modes.mdc).

## Checklist regression

- [ ] `phone_bluetooth`: chỉ native A2DP watch; Flutter `onTargetConnected` không `playGreetingViaNative`; **một chào/phiên**, không reset session khi ACL flap
- [ ] `phone_android_auto`: MediaSession active; một lần/phiên; cancel BT delay khi projection
- [ ] `android_screen_mode`: play on open + resume; minimize chỉ khi complete tự nhiên (`isManual=false`)
- [ ] `android_box_mode`: BootReceiver + boot focus poll; Flutter open skip; Direct Boot files OK

## Files hay đụng

- Box: `BootReceiver.kt`, `BootSessionManager.kt`, boot watch trong `AudioForegroundService.kt`
- BT: `BluetoothReceiver.kt`, `ACTION_BT_WATCH_A2DP`
- AA: CarConnection monitor, `updateMediaSessionState`
- Screen: `lib/main.dart` `_initPlayOnOpen` / `_maybePlayGreetingOnResume`
