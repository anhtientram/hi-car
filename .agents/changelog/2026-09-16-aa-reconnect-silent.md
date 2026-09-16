# 2026-09-16 — Android Auto lần 2 không tự phát

## Log thực tế

`scheduleDelayedGreeting: no valid audio path found` rồi vài phút sau `playAudio OK`
(bấm phát trong app, có path). Ngắt AA / ACL xong lần nối sau im.

## Nguyên nhân

Lần đầu chào xong (`playAudio OK`). Ngắt AA không dây log chỉ có `ACL Disconnected` — **không** có
`CarConnection=0`. Cờ "đã chào phiên này" sống mãi trong process. Lần ACL sau bị bỏ qua.

## Sửa

- `ACTION_AA_LINK_LOST` khi ACL ngắt ở mode AA: đếm ~8s rồi mở phiên mới (flap vài giây không chào lại).
- Disconnect chủ động (`ACTION_BT_END_SESSION`) đóng luôn phiên AA.
- `resolveGreetingPath()` + retry 2s khi prefs path trống lúc bind.

## Không đụng

- BT flap 8s / màn độ / box owners.
