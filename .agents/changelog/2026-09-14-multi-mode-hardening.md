# 2026-09-14 — Rào lại 4 mode cho mọi loại máy

Đợt fix theo feedback người dùng: lời chào không tự phát ở lần kết nối đầu, nhạc bị đổi sau
khi đăng nhập lại, màn độ không thu nhỏ, nút nổi biến mất, iOS báo "Không phát được lời chào".

## 1. Bluetooth — lần kết nối đầu im lặng, lần sau mới chạy

**Gốc:** trong `onStartCommand / ACTION_BT_WATCH_A2DP`, `cancelBtSessionEnd()` chạy TRƯỚC
`isBtSessionGreetingConsumed()`. Hàm đó xoá `bt_last_acl_disconnect_at` (vì xe đang nối lại),
mà đúng mốc ấy là căn cứ duy nhất để biết phiên cũ đã hết grace 15 phút. Thêm nữa
`expireBtSessionIfStale` còn đòi `!isAddressConnected(...)` — điều kiện luôn sai vì hàm chỉ
chạy đúng lúc ACL vừa nối. Kết quả: cờ "đã chào" của chuyến trước (persist trong prefs) sống
mãi, chuyến sau bị nuốt lời chào.

**Sửa** (`AudioForegroundService.kt`):
- Tính `consumed` trước, `cancelBtSessionEnd()` sau.
- `expireBtSessionIfStale` chỉ xét THỜI GIAN: hết `BT_SESSION_GRACE_MS` sau ACL ngắt, hoặc
  quá `BT_SESSION_MAX_MS` (6h) kể từ lời chào (tiến trình bị kill giữa phiên nên không có mốc
  ngắt), hoặc đồng hồ hệ thống nhảy lùi.
- Đổi xe (khác địa chỉ) vẫn chào lại như cũ.

## 2. Bluetooth — phát nhanh hơn, không bỏ cuộc

- `isBtAudioRouteReady()`: ngoài `getProfileConnectionState(A2DP)` còn soi
  `AudioManager.getDevices(GET_DEVICES_OUTPUTS)` tìm `TYPE_BLUETOOTH_A2DP`. Nhiều màn rẻ
  không bao giờ báo trạng thái profile nhưng vẫn nhận audio.
- Delay tính TỪ LÚC ACL CONNECT chứ không cộng dồn sau A2DP ready:
  `max(delay_seconds - elapsedSinceAcl, BT_MIN_AFTER_A2DP_MS = 1500ms)`.
- Hết `BT_A2DP_WATCH_TIMEOUT_MS` (45s) mà xe còn ACL → phát **best-effort** thay vì huỷ hẳn.

## 3. Android Auto — không chào lại giữa chuyến, không huỷ action khi máy chậm

- `ACTION_AA_WATCH_PROJECTION` không còn reset cờ phiên vô điều kiện (ACL nhấp nháy của AA
  không dây từng làm phát lại lời chào giữa lúc đang lái).
- `expireAaSessionIfStale()`: hết phiên theo `AA_SESSION_GRACE_MS` (15p từ lúc projection kết
  thúc) hoặc `BT_SESSION_MAX_MS`.
- Timeout watch projection → phát best-effort nếu xe còn nối, thay vì im lặng.
- `triggerAaGreetingOnce` huỷ luôn watch BT đang chạy (một chủ sở hữu).

## 4. Lời chào bị đổi sau khi đăng nhập lại

Ba nguồn gây đổi nhạc, sửa cả ba:
- `AudioProvider._syncNativePaths` từng ghi đè `active_greeting.mp3` + `boot_greeting.mp3`
  bằng **lời chào dựng sẵn** mỗi khi danh sách chưa nạp xong. Nay ưu tiên bản đã ghim
  (`AudioRepository.existingPinnedPath`), chỉ dùng bản dựng sẵn khi không còn gì hợp lệ.
- `AuthRepository.logout()` từng xoá `greeting_audio_id` → đăng nhập lại là mất lựa chọn.
  Nay giữ lại; đổi tài khoản mới được xử lý riêng.
- `AuthRepository._clearAudioSelectionIfAccountChanged`: chỉ khi `user.id` khác lần trước mới
  xoá lựa chọn + file ghim, tránh xe phát giọng của tài khoản cũ.

## 5. Tự đặt lời chào sau đồng bộ

`AudioProvider._autoSelectGreetingIfMissing()` chạy sau `init()` và sau `syncFromServer()`:
chưa có `greeting_audio_id` mà danh sách đã có nhạc thì chọn sẵn (ưu tiên `type=greeting` +
đã tải về). Người dùng chủ động bỏ đặt → set `greeting_cleared_by_user`, không tự chọn lại.
Menu ba chấm giữ nguyên để đổi bài.

## 6. Màn độ — phát xong không về home

`HiCarPlugin.minimizeApp()` dùng `startActivity(CATEGORY_HOME)`; nhiều màn độ / box không có
activity nào khai báo CATEGORY_HOME hoặc chặn chuyển launcher từ app khác → lệnh thất bại im
lặng. Nay gọi `MainActivity.instance.moveTaskToBack(true)` trên main thread, chỉ fallback
intent HOME khi activity đã bị huỷ.

## 7. Nút nổi biến mất từ lần khởi động thứ hai

`OverlayProvider` từng ghi `is_bubble_enabled = false` vào prefs MỖI KHI
`isPermissionGranted()` trả về false — kể cả khi chỉ là trục trặc nhất thời lúc máy vừa khởi
động. Một lần như vậy là tắt vĩnh viễn. Nay tách:
- `is_bubble_enabled` = **ý muốn** người dùng, chỉ ghi khi họ tự bấm.
- `isBubbleEnabled` = `bubbleWanted && hasPermission` (suy ra, không persist).
- Watchdog trong `main.dart` đọc lại quyền khi chưa có, thay vì bỏ qua luôn.

Lỗi 6 và 7 đi cùng nhau: app không xuống nền được thì cũng không có sự kiện `paused` để hiện
bong bóng.

## 8. iOS — "Không phát được lời chào" dù đã set nhạc

- `AutoPlayOutcome { played, duplicate, failed }`: bị chặn trùng (bộ theo dõi route đã phát,
  Phím tắt chạy sau) KHÔNG còn bị báo là thất bại.
- `activateSession()` luôn gọi `setActive(true)` thay vì tin vào cờ `isSessionActive` —
  just_audio/hệ thống có thể đã hạ session mà ta không biết, khiến `play()` trả true nhưng
  không ra tiếng.
- `setActive` thất bại thì vẫn thử phát best-effort thay vì bỏ cuộc.
- Thông báo lỗi kèm đường ra âm thanh hiện tại để khách tự chẩn đoán.

## 9. Chống lỗi chung mọi thiết bị

- `PREPARE_TIMEOUT_MS`: `prepareAsync` treo (HAL lỗi) từng làm cờ `preparing` kẹt `true` và
  chặn mọi lệnh phát sau đó. Nay quá 12s thì coi là lỗi và dựng player mới.
- `DEFAULT_CONNECTION_MODE` thống nhất giữa Kotlin và Dart; `SettingsProvider.init()` ghi
  `connection_mode` xuống prefs ngay cả khi là mặc định (native đọc thẳng key này).
- `_initPlayOnOpen` chỉ chạy cho `android_screen_mode` — các mode khác do native sở hữu.
- `AudioProvider.init()` idempotent (main + splash đều gọi).
- `AudioModel` đọc được cả `duration` lẫn `duration_seconds`.
