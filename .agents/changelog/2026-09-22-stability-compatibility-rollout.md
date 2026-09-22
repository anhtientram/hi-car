# 2026-09-22 — Stability/compatibility rollout

Triển khai theo [`docs/STABILITY_COMPATIBILITY_PLAN.md`](../../docs/STABILITY_COMPATIBILITY_PLAN.md).

## Phạm vi

- Giữ owner riêng cho Bluetooth, Android Auto, Màn độ, Android Box và CarPlay.
- Route/A2DP/projection/audio focus chậm thì tiếp tục chờ/retry; không bỏ action ở mốc 90 giây.
- MediaPlayer dùng player mới, `prepareAsync`, wake mode, validation callback và release có guard.
- Android Box hỗ trợ fallback API cũ, boot session không phụ thuộc RTC, alarm backoff 15s/40s/90s/180s/360s.
- Sync audio ghi `.part`, validate header/size, rename sau khi tải hoàn tất; boot copy cũng dùng temp/rename.
- Diagnostic log native persist, Flutter log persist, global Flutter error capture và redaction trước khi gửi.
- Incident popup có context mode/kết nối/thiết bị/OS/mã sự cố cùng Đóng/Thử lại/Gửi báo lỗi.
- iOS App Intent chờ route CarPlay/Bluetooth; UI nêu rõ giới hạn tự động hóa trên iOS < 16.

## Kiểm tra

- Flutter test: pass.
- Android debug Flutter/Kotlin compile: pass.
- iOS simulator build: pass.
- Chưa có head unit/Android Box vật lý trong môi trường build; cần pilot log trên nhóm ROM/OS thật trước khi phát hành rộng.
