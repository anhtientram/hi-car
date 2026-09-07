# Changelog — 2026-09-03: Bluetooth chào lại mỗi 20–30 phút

## Triệu chứng

Mode `phone_bluetooth`: đã chào lúc lên xe, khoảng 20–30 phút sau tự phát lời chào lại dù người dùng không tắt BT / không rời xe.

## Nguyên nhân

Head unit / stack BT thường **flap ACL** (ngắt rồi nối lại) định kỳ. App coi mỗi `ACL_CONNECTED` là chuyến mới:

1. `BluetoothReceiver` → `ACTION_BT_WATCH_A2DP`
2. Service **xóa** `lastGreetingTriggerAtMs` (debounce 8s vô dụng)
3. `ACTION_BLUETOOTH_DISCONNECTED` cũng xóa cờ → A2DP ready là chào lại

Android Auto đã có `aaGreetingPlayedThisConnection`; Bluetooth thì chưa.

## Đã sửa (chỉ `phone_bluetooth`)

- Một lần chào / phiên + persist prefs (sống sót khi process restart)
- ACL ngắt: giữ phiên **15 phút** rồi mới cho chào chuyến mới
- Không reset debounce trên mỗi `ACTION_BT_WATCH_A2DP`
- Log ACL / skip phiên qua `HiCarDiagnosticLog` (`HiCarBT`)

## Không đụng

- AA / Màn độ / Box owners không đổi
- Flutter `onTargetConnected` vẫn không phát

## Kiểm thử

1. Nối xe lần đầu → có chào
2. Giả lập ACL ngắt/nối (tắt BT xe vài giây) trong <15p → **không** chào lại
3. Ngắt >15p rồi nối → chào lại
4. Đổi xe mục tiêu → chào xe mới
5. AA / Màn độ / Box: hành vi cũ
