# 2026-09-16 — Bluetooth lần 2 không tự phát

## Triệu chứng

Nối Bluetooth (nút trong app hoặc Cài đặt hệ thống) lần đầu thì chào. Ngắt rồi nối lại thì im lặng.

## Nguyên nhân

Cờ "đã chào phiên này" giữ **15 phút** sau mọi `ACL_DISCONNECTED` để chống HU flap. Người dùng
disconnect/reconnect chủ động (vài giây) bị coi là cùng phiên nên bị nuốt lời chào.

Cửa sổ chống trùng 8s (`lastGreetingTriggerAtMs`) cũng không bị xóa khi phiên thật sự kết thúc.

## Sửa (chỉ `phone_bluetooth`)

- Flap ACL vài giây vẫn **không** chào lại (`BT_SESSION_FLAP_MS = 8s`).
- Disconnect trong app (`disconnectDevice`) và tắt Bluetooth (adapter OFF) gọi
  `ACTION_BT_END_SESSION` ngay → lần nối sau được chào.
- Ngắt ACL > 8s (rời xe / ngắt thiết bị ngoài app) cũng hết phiên.
- `clearBtSession` xóa luôn debounce để không chặn lần chào mới.

## Không đụng

- Android Auto / Màn độ / Box owners không đổi.
- Flutter `onTargetConnected` vẫn không phát.
