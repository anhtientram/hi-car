# Rules — Tech stack & kiến trúc

## Stack

- Flutter (stable) + Dart Provider + go_router + flutter_screenutil
- just_audio (preview UI); playback nền = Kotlin MediaPlayer + FGS
- flutter_overlay_window, flutter_blue_plus, dio, shared_preferences
- Android: Kotlin, MediaBrowserServiceCompat / MediaSession (AA)

## Cấu trúc `lib/`

```
lib/
  core/          # theme, router, constants, logger
  data/          # models, repositories, services (api, sync, remote_config)
  providers/     # Auth, Audio, Bluetooth, Overlay, Settings, Permission, Studio
  screens/       # splash, auth, home, settings, setup, studio
  native/        # ServiceChannel
  overlay/       # bubble UI
```

## Phân tầng

| Tầng | Việc |
|------|------|
| UI | Widget, ScreenUtil, gọi provider |
| Provider | State + orchestration |
| Repository / Service | API, sync, file |
| Kotlin | FGS, boot, BT, AA, MediaPlayer, overlay bridge |

## UI

- Cyan `#00E5FF` + đen; dark automotive.
- Size: `.w` `.h` `.sp` `.r` — không hardcode.

## Keep-alive

- Foreground service + WakeLock + (khuyến nghị) ignore battery optimization
- Overlay sống khi clear app; ẩn khi app foreground
