# Rules — Audio native & sync (v7)

## Playback

- Android: `AudioForegroundService.kt` — player mới mỗi lần; `prepareAsync`; wake lock.
- Clip chào ngắn: mất focus → giành lại / resume, không hard-stop sớm.
- Lỗi MediaPlayer → release + retry.
- Watch A2DP / AA / boot: máy chậm thì đợi; timeout không được biến thành “hủy luôn action”.
- iOS: `HiCarAudioPlayer` + session `.playback`; Shortcuts không cần UI foreground.
- Log: `HiCarDiagnosticLog`.

Chi tiết: `.cursor/rules/audio-playback.mdc` · Box: `.cursor/rules/android-box.mdc`

## Sync / offline

- Tải `.part` → verify MP3 → rename.
- Sync lỗi / DNS: giữ local, không wipe.
- Pin chỉ khi file hợp lệ → `active_*.mp3` → copy boot.
- Demo Beta: mới hiện “Lời chào mặc định” trong list.

## Demo Beta

- Prefs `is_beta_mode`
- Tắt: ẩn greeting mặc định khỏi UI (không xoá asset)
