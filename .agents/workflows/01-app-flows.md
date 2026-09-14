# Workflow — Luồng app

## Khởi động

1. `RemoteConfigService.load()` (cache rồi fetch GitHub config)
2. Splash: check `auth_token` / session
3. Chưa login → Login / Connection mode setup
4. Đã login → `AudioProvider.init` + sync (nếu có mạng) + start FGS → Home

## Auth

- Login: SĐT + password **hoặc** mã kích hoạt
- Signup → thường tới Gen Audio
- Logout: clear auth cả prefs thường + device-protected (chặn boot giả login)

## Gen Audio / Studio

1. Nhập tên / biển / hãng → generate (giới hạn lượt)
2. Nghe thử (just_audio) → set greeting / goodbye → sync native paths

## Chọn lời chào tự động

- Sau `init()` và sau mỗi lần sync: chưa có `greeting_audio_id` mà đã có nhạc → tự chọn
  (ưu tiên `type=greeting` + đã tải về). Menu ba chấm vẫn dùng để đổi.
- Người dùng chủ động bỏ đặt → `greeting_cleared_by_user = true`, không tự chọn lại.
- Đăng nhập lại **cùng tài khoản** giữ nguyên lựa chọn; chỉ đổi `user.id` mới xoá.
- Không ghi đè `active_greeting.mp3` bằng lời chào dựng sẵn khi danh sách chưa nạp xong.

## Home

- Phát chào / tạm biệt qua native
- List audio, BT panel, permission status, overlay state

## Overlay

- App paused → show bubble  
- App resumed → hide  
- Actions: play_greeting / play_goodbye / stop / open_app (qua isolate port)

## Auto-play theo mode

Xem `.agents/rules/02-connection-modes.md` và `.cursor/rules/connection-modes.mdc`.

## Permission setup

Overlay, notification, BT, battery optimization — màn hướng dẫn trong setup/settings.
