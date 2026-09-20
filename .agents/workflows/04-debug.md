# Workflow — Debug auto-play / overlay

## Khi user gửi log

1. Phân loại: DNS/Dio vs MediaPlayer vs watch bị hủy vs overlay mất.
2. Lấy: `connection_mode`, wired/wireless, màn độ hay box, iOS CarPlay hay Shortcuts BT.
3. Skill:
   - cắt tiếng 1–3s → `debug-playback-cut`
   - sai mode / chờ-hủy → `fix-by-connection-mode`
   - bong bóng màn độ → `overlay-keepalive-headunit`
   - Android Box im sau nổ máy → `android-box-boot-play`
   - iOS → `ios-carplay-shortcuts`

## Cờ đỏ (vi phạm v7)

- Watch A2DP/AA/Box timeout → bỏ luôn, không phát
- Overlay biến mất khi mở YouTube (màn độ)
- Box im sau cold boot / “chạy vài ngày rồi tịt” (session theo đồng hồ)
- CarPlay/BT Shortcuts im vì Intent return false khi route chưa sẵn
- Flutter + native cùng phát (đặc biệt Box + play-on-open)

## Sau khi fix (khi user yêu cầu code)

- [ ] Analyze / build phần đụng
- [ ] Changelog ngắn `.agents/changelog/`
- [ ] Không phá owner của mode khác

```bash
adb logcat -v time | grep -Ei "HiCarAudio|HiCarService|HiCarBoot|HiCarAA|HiCarBT|MediaPlayer"
flutter analyze
```
