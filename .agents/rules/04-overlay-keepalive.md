# Rules — Bong bóng nổi màn độ (v7)

## Flow bắt buộc

Tắt xe → sang hôm sau mở lại → **vào app** → phát nhạc xong → **back ra ngoài** → hiện bong bóng nổi.

Bong bóng nổi phải luôn duy trì dù cho khách họ có mở YouTube nghe nhạc hay làm gì đó.

## Hành vi

| Sự kiện | Overlay |
|---------|---------|
| User back / app `paused` | Hiện |
| App này `resumed` | Ẩn |
| App này `inactive` (thanh thông báo, dialog) | **Không** ẩn |
| YouTube / radio / Maps lên foreground | **Giữ** bong bóng |
| Clear recent (khi đã bật bubble) | Vẫn tồn tại nhờ FGS |
| Mở lại app | Ẩn bubble, UI đầy đủ |

## Kỹ thuật

- Entry `overlayMain` **bắt buộc** trong `lib/main.dart`.
- Quyền `SYSTEM_ALERT_WINDOW` + `is_bubble_enabled`.
- Không gắn vòng đời bubble với audio focus (YouTube cướp focus ≠ đóng overlay).
- Cold boot: không trông chờ `BOOT_COMPLETED` của màn độ; user vào app rồi back là đường restore chính.

## Files

`lib/main.dart`, `overlay_provider.dart`, `lib/overlay/`, `OverlayBridge.kt`
