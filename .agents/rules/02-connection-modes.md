# Rules — Chế độ kết nối & môi trường xe

Ba môi trường: **màn zin**, **màn độ Android**, **màn zin + Android Box**.
Mặc định `connection_mode` = `android_screen_mode` (Dart và Kotlin phải khớp nhau).

## Điện thoại + Bluetooth (`phone_bluetooth`)

1. Xe bật → BT connect điện thoại
2. Native đợi đường audio sẵn sàng (profile A2DP **hoặc** thiết bị ra `TYPE_BLUETOOTH_A2DP`)
3. Delay đếm từ lúc ACL connect: `max(delay_seconds - đã trôi, 1.5s)` → phát ngay khi kịp
4. Phát lời chào **một lần / phiên** → stop → nhả focus
5. Chỉ phát khi đúng `target_device_address`
6. ACL ngắt rồi nối lại trong ~15 phút (HU flap 20–30p) **không** chào lại; rời xe lâu hơn thì
   chào chuyến mới
7. Hết phiên xét thuần theo thời gian — dựa vào trạng thái kết nối sẽ luôn sai vì hàm chỉ chạy
   đúng lúc vừa nối lại
8. Watch A2DP timeout mà ACL còn sống → phát best-effort, không huỷ

Flutter **không** phát song song khi BT connect.

## Android Auto (`phone_android_auto`)

- Có dây / không dây qua CarConnection (+ fallback gearhead)
- App = media app (MediaSession + FGS mediaPlayback)
- Một lần chào / phiên projection; hết phiên sau 15p kể từ lúc projection dừng
- AA không dây nhấp nháy ACL giữa chuyến **không** được reset cờ phiên
- Nếu BT đang schedule → hủy, chuyển AA
- Máy chậm: đợi hết watch rồi vẫn phát best-effort nếu còn nối

## Màn độ (`android_screen_mode`)

- Auto launch app (setting trên màn) → play on open → minimize về launcher
- Minimize bằng `moveTaskToBack(true)`, HOME intent chỉ fallback
- Phát xong → app xuống nền → sự kiện `paused` → hiện bong bóng nổi
- Hibernate ổn hơn cold reboot; resume app cũng phát lại nếu bật play-on-open
- Không phụ thuộc 100% `BOOT_COMPLETED` cho audio

## Android Box (`android_box_mode`)

- `BOOT_COMPLETED` / Direct Boot → FGS (specialUse từ boot trên API 34+)
- Copy `boot_greeting.mp3` sang device-protected
- Poll readiness (audio focus) + alarm retry 15s/40s/90s
- Flutter mở app **không** phát chồng boot

## iOS (Bluetooth / CarPlay)

- Theo dõi route change: vào `carAudio` / `bluetoothA2DP` → phát lời chào
- Phím tắt (`PlayGreetingIntent`) có thể chạy sau khi route đã phát: kết quả `duplicate` là
  **thành công**, không được báo "Không phát được lời chào"
- Luôn `setActive(true)` trước khi phát; `setActive` lỗi thì vẫn thử phát best-effort

## Overlay

Messenger bubble: chào / tạm biệt / stop; drag + close; show nền / hide foreground.
`is_bubble_enabled` = ý muốn người dùng; kết quả check quyền **không** được ghi đè key này.
