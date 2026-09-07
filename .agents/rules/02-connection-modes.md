# Rules — Chế độ kết nối & môi trường xe

Ba môi trường: **màn zin**, **màn độ Android**, **màn zin + Android Box**.

## Điện thoại + Bluetooth (`phone_bluetooth`)

1. Xe bật → BT connect điện thoại  
2. Native đợi A2DP sẵn sàng → delay (min ~3s, user chỉnh 1/3/5/10)  
3. Phát lời chào **một lần / phiên** → stop → nhả focus  
4. Chỉ phát khi đúng `target_device_address`  
5. ACL ngắt rồi nối lại trong ~15 phút (HU flap 20–30p) **không** chào lại; rời xe lâu hơn thì chào chuyến mới

Flutter **không** phát song song khi BT connect.

## Android Auto (`phone_android_auto`)

- Có dây / không dây qua CarConnection (+ fallback gearhead)
- App = media app (MediaSession + FGS mediaPlayback)
- Một lần chào / phiên projection
- Nếu BT đang schedule → hủy, chuyển AA

## Màn độ (`android_screen_mode`)

- Auto launch app (setting trên màn) → play on open → minimize về launcher
- Hibernate ổn hơn cold reboot; resume app cũng phát lại nếu bật play-on-open
- Không phụ thuộc 100% `BOOT_COMPLETED` cho audio

## Android Box (`android_box_mode`)

- `BOOT_COMPLETED` / Direct Boot → FGS (specialUse từ boot trên API 34+)  
- Copy `boot_greeting.mp3` sang device-protected  
- Poll readiness (audio focus) + alarm retry 15s/40s/90s  
- Flutter mở app **không** phát chồng boot

## Overlay

Messenger bubble: chào / tạm biệt / stop; drag + close; show nền / hide foreground.
