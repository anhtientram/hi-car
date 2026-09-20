---
name: android-box-boot-play
description: Keep Android Box auto-play working on car restart (USB box + factory screen). Use when box is silent after overnight power-off, plays twice, plays only after opening the app, or stops working after a few days. Covers BootReceiver, Direct Boot files, BOOT_COUNT sessions, readiness poll, and retry alarms.
---

# Android Box boot play

## Required user flow

Cục box gắn với màn zin. Tắt xe → hôm sau nổ máy → box boot → **tự phát lời chào ngầm**, không bắt buộc mở app.

Same wait rule as other modes: box chậm thì đợi / retry, không hủy action boot.

## Diagnose

| Symptom | Likely cause |
|---------|----------------|
| Silent after overnight | No `boot_greeting.mp3` in device-protected; credential prefs locked; FGS `mediaPlayback` from boot (API 35) |
| Works only after opening app | Flutter play-on-open accidentally enabled; boot path skipped (`Boot skip`) |
| Plays twice | Flutter **and** BootReceiver; session not reused for duplicate broadcasts |
| Worked a few days then dead | Session keyed by wall-clock on box **without RTC** — must use `BOOT_COUNT` / `boot_id` |
| Early boot then never retry | Alarms cancelled too soon; `markSessionCompleted` before real playback |
| Unlock later still silent | `USER_UNLOCKED` retry skipped incorrectly |

Need `connection_mode=android_box_mode`, logged in, auto-play on, greeting pinned (open app **once** after set greeting so boot file copies).

## Fix rules

Read [`.cursor/rules/android-box.mdc`](../../rules/android-box.mdc) and [`docs/TEST_CASES.md`](../../../docs/TEST_CASES.md).

- Do not add Flutter auto-play on open for this mode.
- Cold-boot test = power off **2–5 min**, not a fast reboot.
- Log tag `HiCarBoot` via `HiCarDiagnosticLog`.

## Files

- `BootReceiver.kt`, `BootSessionManager.kt`
- Boot watch / `specialUse` in `AudioForegroundService.kt`
- `HiCarPlugin.kt` copy `boot_greeting.mp3`
- `lib/main.dart` `_initPlayOnOpen` skip box
