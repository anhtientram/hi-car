---
name: overlay-keepalive-headunit
description: Restore and keep the màn độ floating bubble after overnight reboot and while other apps (YouTube) play audio. Use when overlay disappears after car off/on, after back-from-home, after YouTube, or after process death.
---

# Overlay keep-alive (màn độ)

## Required user flow

1. Tắt xe, sang hôm sau mở lại (cold boot).
2. Vào app.
3. Phát nhạc xong.
4. Back ra ngoài → **bong bóng nổi hiện**.
5. Khách mở YouTube (hoặc app khác) nghe nhạc → **bong bóng vẫn còn**.

## Diagnose

| Symptom | Likely cause |
|---------|----------------|
| No bubble after back | Overlay not shown on `paused`; permission / `is_bubble_enabled` false after boot |
| Bubble flashes then gone | Hidden on `inactive` instead of only `resumed` |
| Bubble dies when YouTube plays | Overlay tied to audio focus / FGS killed / `closeOverlay` on focus loss |
| Release build never shows bubble | `overlayMain` not in `lib/main.dart` |
| After overnight, never comes back | No restore path: user must open app then leave; FGS not restarted |

## Fix rules

Read [`.cursor/rules/overlay-keepalive.mdc`](../../rules/overlay-keepalive.mdc).

- Show on `paused`; hide only when **this** app `resumed`.
- Do not close overlay because another media app is playing.
- Keep FGS + `flutter_overlay_window` service running in background.
- After boot, opening the app then backing out must recreate the bubble.

Màn độ ≠ Android Box. Box auto-play is `BootReceiver` (skill `android-box-boot-play`), not this overlay path.

## Files

- `lib/main.dart` — lifecycle + `overlayMain`
- `lib/providers/overlay_provider.dart`
- `lib/overlay/overlay_main.dart`
- `OverlayBridge.kt`, `MainActivity.kt`, `AudioForegroundService.kt`
