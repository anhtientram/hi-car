# Changelog — 2026-08-31: Playback cắt 2–3s + sync DNS

## Triệu chứng

- Sync: `DioException Failed host lookup: admintts.chaoxechuanthuonggia.com`
- ADB: `playAudio OK` → ~1s sau `MediaPlayer error what=100 extra=2`, `1/-32`, `1/-38`
- Một số máy (màn độ mới cài) tịt; máy đã sync ổn vẫn offline OK

## Kết luận

- DNS = lỗi sync, không phải nguyên nhân tắt tiếng.
- Bộ ba MediaPlayer = player bị destroy giữa chừng; nguồn chính: `AUDIOFOCUS_LOSS` → `stopPlayback()` (không vào diagnostic log vì dùng `Log.d`).
- File tải cụt + skip re-download theo exists/hash làm hỏng lâu dài trên vài máy.

## Đã sửa

### Native `AudioForegroundService.kt`

- Focus: không hard-stop khi clip chưa ~90%; regain + resume timeout
- Error / stall: release + MediaPlayer mới + retry mọi mode
- `prepareAsync`, wake mode, log qua `HiCarDiagnosticLog`
- Watchdog stall giữa chừng

### Dart

- `sync_service.dart`: download `.part` + verify MP3 + xóa file hỏng khi hash match nhưng invalid
- `audio_repository.dart`: pin an toàn (validate + temp rename); `prepareBundledGreetingPath`
- `audio_provider.dart`: fallback phát asset khi active thiếu/hỏng; **UI lời chào mặc định chỉ khi Demo Beta**
- `constants.dart`: `defaultGreetingId`

## Kiểm thử gợi ý

1. Màn độ: mở app phát chào — cố tình có app radio cướp focus — phải tiếp tục / phát lại
2. Offline sau khi đã sync — vẫn phát
3. Sync lại trên máy từng lỗi — file cụt phải bị thay
4. Tắt Demo — list không hiện greeting mặc định; bật Demo — hiện
5. Box boot / BT / AA: không phát chồng (regression)
