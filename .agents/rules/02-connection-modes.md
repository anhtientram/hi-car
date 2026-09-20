# Rules — Chế độ kết nối (hợp đồng v7)

Ba môi trường Android: **màn zin**, **màn độ**, **màn zin + Android Box**. iPhone: **CarPlay + Shortcuts**.

## Hợp đồng (nguyên văn yêu cầu sản phẩm)

- Đối với chế độ bluetooth (cả android và ios), vừa kết nối là phát nhạc ngay hoặc chờ cho kịp để phát, tránh lỗi xảy ra.
- Đối với màn độ, cần hoạt động tốt bong bóng khi khởi động lại máy (tắt xe rồi sang hôm sau mở lại) → vào app, phát nhạc xong back ra ngoài xong hiện bong bóng nổi, bong bóng nổi phải luôn duy trì dù cho khách họ có mở youtube nghe nhạc hay làm gì đó.
- Đối với android auto (khác bluetooth), khi connect xong cũng phát nhạc như hiện tại (cả không dây lẫn có dây) → cần đồng đều, máy nào chậm thì đợi, tránh trường hợp hủy luôn cái action đó.
- Đối với carplay, set nhạc chào rồi, sau đó ra cài đặt tự động hóa carplay hoặc tự động hóa bluetooth thì khi connect xong phải phát nhạc ngay, hoặc đợi.
- Đối với android box (cục box gắn màn zin), khi khởi động lại xe là auto phát nhạc ngầm; box chậm thì đợi / retry, không hủy.

## Điện thoại + Bluetooth (`phone_bluetooth`) — Android

1. Xe bật → BT connect đúng `target_device_address`.
2. Native đợi A2DP (tiếng phải ra **loa xe**, không loa điện thoại).
3. Delay user (`delay_seconds`, min ~3s) rồi phát.
4. Máy/màn chậm → **tiếp tục đợi**, không hủy `ACTION_BT_WATCH_A2DP`.
5. Flutter **không** phát song song khi ACL connect.

## Bluetooth trên iOS

Không dùng picker thiết bị Android. Khách set lời chào trong app, rồi Shortcuts → tự động hóa **Bluetooth “Khi thiết bị kết nối”** → **Phát lời chào HiCar**. Connect xong: phát ngay hoặc đợi session/route sẵn sàng.

## Android Auto (`phone_android_auto`)

- Luồng **khác** Bluetooth: CarConnection (wired + wireless) + MediaSession.
- AA không dây: BT có thể nối trước projection → chỉ **watch**, chưa phát.
- Máy chậm: giữ watch, **không hủy** action chào đang chờ.
- Một lần chào / phiên projection khi nhạc thực sự bắt đầu.

## Màn độ (`android_screen_mode`)

- Auto launch / mở app → phát → back/minimize.
- Overlay: xem [`04-overlay-keepalive.md`](04-overlay-keepalive.md).
- Hibernate ổn hơn cold reboot; resume cũng phát nếu bật play-on-open.
- Không phụ thuộc 100% `BOOT_COMPLETED` cho audio.

## Android Box (`android_box_mode`)

Cục box gắn màn zin — **không** phải màn độ.

- Boot / Direct Boot → FGS `specialUse` → poll focus + alarm 15s/40s/90s.
- Flutter mở app **không** phát chồng boot.
- Box chậm / không RTC → đợi, session theo `BOOT_COUNT` (không theo đồng hồ tường).
- Chi tiết: [`05-android-box.md`](05-android-box.md) · workflow [`../workflows/05-android-box-boot.md`](../workflows/05-android-box-boot.md).

## CarPlay (`ios_carplay`)

- Set chào trong app trước.
- Shortcuts: tự động hóa **CarPlay khi kết nối** **hoặc** **Bluetooth khi kết nối**.
- Intent chạy nền; phát ngay hoặc đợi — không fail vì xe chậm.
