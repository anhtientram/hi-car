# Workflow — Luồng app (v7)

## Khởi động

1. `RemoteConfigService.load()`
2. Splash: check `auth_token`
3. Chưa login → Login / chọn chế độ kết nối / quyền
4. Đã login → `AudioProvider.init` + sync (nếu có mạng) + start FGS → Home

## Auth

- Login: SĐT + password **hoặc** mã kích hoạt
- Signup → Gen Audio
- Logout: clear auth (kể cả device-protected, tránh boot giả login)

## Gen Audio / Studio

1. Nhập tên / biển / hãng → generate (giới hạn lượt)
2. Nghe thử (`just_audio`) → set greeting / goodbye → sync native paths
3. iOS: sau khi set chào, hướng dẫn Shortcuts (CarPlay **và** Bluetooth)

## Home

- Phát chào / tạm biệt qua native
- List audio, BT panel (Android), permission, overlay toggle

## Overlay

Xem workflow [`03-overlay-after-boot.md`](03-overlay-after-boot.md) (chỉ **màn độ**). Android Box không dùng overlay làm đường auto-play.

## Auto-play

Xem [`02-connection-autoplay.md`](02-connection-autoplay.md). Box: [`05-android-box-boot.md`](05-android-box-boot.md).

## Permission setup

Overlay, notification, BT; hướng dẫn battery optimization (không xin quyền ignore trực tiếp — chính sách Play).
