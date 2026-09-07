# Architecture — bản đồ file

Package: `com.hicar.ora.limited` · App: **Giọng Thương Gia**

## Flutter (`lib/`)

| Khu vực | Path | Việc |
|---------|------|------|
| Entry | `lib/main.dart` | RemoteConfig → providers → play-on-open / resume Màn độ |
| Overlay entry | `lib/main.dart` → `overlayMain` | **Phải** cùng file `main()` (AOT release) |
| Router / theme | `lib/core/` | `app_router`, `app_theme`, `constants`, `logger` |
| API | `lib/data/services/api_client.dart` | Dio + token; fallback URL + RemoteConfig |
| Remote URL | `lib/data/services/remote_config_service.dart` | GitHub `config.json` → `api_base_url` |
| Sync tải nhạc | `lib/data/services/sync_service.dart` | List API → download `.part` → verify → rename |
| Repo audio | `lib/data/repositories/audio_repository.dart` | Pin `active_*.mp3`, asset → Documents |
| State | `lib/providers/audio_provider.dart` | Sync, native play, Demo Beta list |
| State | `lib/providers/settings_provider.dart` | `connection_mode`, delay, playOnOpen, beta |
| State | `lib/providers/*_provider.dart` | Auth, BT, Overlay, Permission, Studio |
| Bridge | `lib/native/service_channel.dart` | MethodChannel ↔ Kotlin |
| UI | `lib/screens/` | splash, auth, home, settings, setup, studio |
| Overlay UI | `lib/overlay/` | Bubble Messenger-style |

### Prefs keys quan trọng

- `auth_token`, `connection_mode`, `greeting_audio_path`, `goodbye_audio_path`
- `greeting_audio_id`, `goodbye_audio_id`, `auto_play_enabled`, `delay_seconds`
- `is_beta_mode`, `api_base_url`, `audio_list`, `cached_audio_list`

### Storage audio

| File | Vị trí | Ai dùng |
|------|--------|---------|
| `{id}_{hash}.mp3` | Documents/`hicar_audio/` | Pool sync |
| `active_greeting.mp3` / `active_goodbye.mp3` | Documents/`hicar_audio/` | Path cố định cho native / CarPlay |
| `boot_greeting.mp3` / `boot_goodbye.mp3` | Device-protected `filesDir` | Boot Box / Direct Boot |
| `audio_default.MP3`, `good_bye.MP3` | Assets → copy Documents khi cần | Fallback / Demo |

## Android (`android/app/.../com/hicar/ora/limited/`)

| File | Việc |
|------|------|
| `AudioForegroundService.kt` | MediaPlayer, focus, MediaSession, AA/BT/Box watch — tag log `HiCarService` / `HiCarAudio` |
| `HiCarPlugin.kt` | MethodChannel, sync prefs + copy boot files |
| `BootReceiver.kt` | Boot Box → delayed greeting + alarm retry |
| `BootSessionManager.kt` | Session id, playback started, miss report |
| `BluetoothReceiver.kt` | ACL + A2DP watch trigger |
| `HiCarDiagnosticLog.kt` | Log file device-protected (báo cáo lỗi) |
| `OverlayBridge.kt` | Tín hiệu overlay |

Manifest: FGS `mediaPlayback|specialUse`, `directBootAware`, Boot + BT receivers.

## Tài liệu agent

Xem [`AGENTS.md`](../AGENTS.md).
