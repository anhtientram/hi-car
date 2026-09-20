# Architecture — bản đồ file (v7 stable)

Package: `com.hicar.ora.limited` · App: **Giọng Thương Gia**

## Flutter (`lib/`)

| Khu vực | Path | Việc |
|---------|------|------|
| Entry | `lib/main.dart` | RemoteConfig, providers, play-on-open / resume Màn độ, overlay lifecycle |
| Overlay entry | `lib/main.dart` → `overlayMain` | **Phải** cùng file `main()` (AOT release) |
| Overlay UI | `lib/overlay/overlay_main.dart` | Bubble Messenger-style |
| Router / theme | `lib/core/` | `app_router`, `app_theme`, `constants` |
| API | `lib/data/services/api_client.dart` | Dio + token |
| Remote URL | `lib/data/services/remote_config_service.dart` | GitHub config → `api_base_url` |
| Sync | `lib/data/services/sync_service.dart` | Download `.part` → verify → rename |
| Repo audio | `lib/data/repositories/audio_repository.dart` | Pin `active_*.mp3` |
| State | `lib/providers/*_provider.dart` | Auth, Audio, BT, Overlay, Settings, Permission, Studio |
| Bridge | `lib/native/` | MethodChannel ↔ Kotlin / Swift |
| Setup | `lib/screens/setup/` | Connection mode + permission (iOS: hướng dẫn Shortcuts) |

### Prefs quan trọng

`auth_token`, `connection_mode`, `greeting_audio_path`, `goodbye_audio_path`, `greeting_audio_id`, `auto_play_enabled`, `delay_seconds`, `is_bubble_enabled`, `target_device_address`

Box Direct Boot: `filesDir/boot_greeting.mp3` trên device-protected context (không nằm Documents Flutter).

## Android (`android/app/.../com/hicar/ora/limited/`)

| File | Việc |
|------|------|
| `AudioForegroundService.kt` | MediaPlayer, focus, MediaSession, AA/BT/Box watch |
| `HiCarPlugin.kt` | MethodChannel, sync prefs, copy `boot_greeting.mp3` sang Direct Boot |
| `BootReceiver.kt` | **Box only** — boot broadcasts → delayed greeting + retry alarms |
| `BootSessionManager.kt` | Box session id (`BOOT_COUNT` / `boot_id`), playback started, miss report |
| `BluetoothReceiver.kt` | ACL → A2DP watch (BT) hoặc AA projection watch |
| `HiCarDiagnosticLog.kt` | Log file (báo cáo lỗi) |
| `OverlayBridge.kt` | Overlay isolate → native play |
| `MainActivity.kt` | Gắn OverlayBridge lên overlay engine |

## iOS (`ios/Runner/AppDelegate.swift`)

| Thành phần | Việc |
|------------|------|
| `HiCarAudioPlayer` | AVAudioPlayer, UserDefaults `flutter.*` paths |
| `PlayGreetingIntent` / `PlayGoodbyeIntent` | Shortcuts: CarPlay **hoặc** Bluetooth automation |
| MethodChannels cùng tên Android | Flutter không cần nhánh iOS riêng cho play |

## Tài liệu agent

[`AGENTS.md`](../AGENTS.md)
