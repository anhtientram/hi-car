# Rules — Tech stack & kiến trúc (v7)

## Stack

- Flutter + Provider + go_router + flutter_screenutil
- just_audio (preview UI); playback nền Android = Kotlin MediaPlayer + FGS
- iOS: `AVAudioPlayer` + App Intents (Shortcuts)
- flutter_overlay_window, flutter_blue_plus, dio, shared_preferences

## `lib/`

```
lib/
  core/          # theme, router, constants, logger
  data/          # models, repositories, services
  providers/     # Auth, Audio, Bluetooth, Overlay, Settings, Permission, Studio
  screens/
  native/        # ServiceChannel, BluetoothChannel
  overlay/       # bubble UI (entry overlayMain nằm ở main.dart)
```

## Phân tầng

| Tầng | Việc |
|------|------|
| UI | Widget, ScreenUtil, gọi provider |
| Provider | State + orchestration |
| Repository / Service | API, sync, file |
| Kotlin | FGS, boot, BT, AA, MediaPlayer, overlay bridge |
| Swift | Session playback, App Intents |

## Keep-alive

- Foreground service + WakeLock
- Overlay sống khi app khác (YouTube) lên foreground; ẩn chỉ khi **app này** resume
