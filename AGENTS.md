# Giọng Thương Gia — Agent Index

App Flutter + Kotlin: lời chào / tạm biệt xe tự động. Package: `com.hicar.ora.limited`.

Dùng file này làm **mục lục**. Đọc đúng file theo việc đang làm — đừng nhét hết context vào prompt.

---

## Tìm nhanh

| Cần gì | Mở đâu |
|--------|--------|
| Rule luôn áp dụng (stack, UI, kiến trúc) | [`.cursor/rules/project-core.mdc`](.cursor/rules/project-core.mdc) |
| 4 chế độ kết nối (BT / AA / Màn độ / Box) | [`.cursor/rules/connection-modes.mdc`](.cursor/rules/connection-modes.mdc) |
| Phát nhạc native + audio focus | [`.cursor/rules/audio-playback.mdc`](.cursor/rules/audio-playback.mdc) |
| Sync / offline / tải file | [`.cursor/rules/offline-sync.mdc`](.cursor/rules/offline-sync.mdc) |
| UI Flutter (ScreenUtil, Provider) | [`.cursor/rules/flutter-ui.mdc`](.cursor/rules/flutter-ui.mdc) |
| Skill: debug nhạc cắt 2–3s | [`.cursor/skills/debug-playback-cut/SKILL.md`](.cursor/skills/debug-playback-cut/SKILL.md) |
| Skill: sửa theo mode | [`.cursor/skills/fix-by-connection-mode/SKILL.md`](.cursor/skills/fix-by-connection-mode/SKILL.md) |
| Bản đồ file code | [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) |
| Changelog fix đã làm | [`.agents/changelog/`](.agents/changelog/) |
| Workflow nghiệp vụ | [`.agents/workflows/`](.agents/workflows/) |
| Rules chi tiết (tiếng Việt) | [`.agents/rules/`](.agents/rules/) |
| System prompt gốc | [`.agents/prompt/system-prompt.md`](.agents/prompt/system-prompt.md) |

---

## Chế độ kết nối (`connection_mode`)

| Key prefs | Tên | Ai sở hữu phát nhạc |
|-----------|-----|---------------------|
| `phone_bluetooth` | Điện thoại + BT màn xe | Native `ACTION_BT_WATCH_A2DP` (một chào/phiên; ACL flap không phát lại) |
| `phone_android_auto` | Android Auto | Native CarConnection + MediaSession |
| `android_screen_mode` | Màn độ | Flutter `playOnOpen` + minimize khi xong |
| `android_box_mode` | Android Box | `BootReceiver` + boot watch / alarm retry |

**Không** để Flutter và native cùng phát một sự kiện (trùng → cắt giữa chừng).

---

## Offline

- Đã login + đã tải nhạc → **dùng được không mạng**.
- Sync fail → **không xoá** file local.
- Máy mới cài / chưa login → cần mạng lần đầu.
- Lời chào mặc định (`audio_default.MP3`) **chỉ hiện UI khi bật Demo (Beta)**; fallback phát ngầm vẫn dùng được khi file active hỏng.

---

## Nguyên tắc khi sửa

1. Ưu tiên **ổn định trên mọi loại máy** (màn xịn lẫn màn kém), không chỉ fix 1 device.
2. Log quan trọng qua `HiCarDiagnosticLog` (không chỉ `Log.d`) — để vào “Báo cáo lỗi” trong app.
3. Sync không được phá file đang phát / pin file hỏng sang `active_*.mp3` / `boot_*.mp3`.
4. `AUDIOFOCUS_LOSS` **không** được `stopPlayback()` cứng trên clip chào ngắn — xem rule audio.
5. Sau `MEDIA_ERROR_SERVER_DIED` phải `release` + player **mới** + retry (mọi mode).

---

## Lệnh hữu ích

```bash
# Log chẩn đoán playback
adb logcat -c && adb logcat -v time | grep -Ei "HiCarAudio|HiCarService|HiCarBoot|AudioFlinger|MediaPlayer"

# Build check
flutter analyze
flutter build apk --debug
```
