# Rules — Audio native & sync

## Playback (Kotlin)

- File chính: `AudioForegroundService.kt`
- Player mới mỗi lần; `prepareAsync`; wake lock partial
- Focus: clip chào ngắn — mất focus → giành lại / resume, không hard-stop sớm
- Lỗi MediaPlayer → release + retry (mọi mode)
- Watchdog stall giữa chừng
- Log: `HiCarDiagnosticLog`

Chi tiết Cursor rule: `.cursor/rules/audio-playback.mdc`

## Sync / offline

- Tải `.part` → verify MP3 → rename
- Sync lỗi / DNS fail: giữ local, không wipe
- Pin chỉ khi file hợp lệ → `active_*.mp3` → copy boot
- Demo Beta: mới hiện “Lời chào mặc định” trong list; fallback phát ngầm vẫn có

## Demo Beta

- Prefs `is_beta_mode`
- Bật: hiện asset greeting trong list
- Tắt: ẩn khỏi UI (không xoá asset trong bundle)
