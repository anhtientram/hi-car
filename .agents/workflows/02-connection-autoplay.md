# Workflow — Auto-play theo mode (v7)

Nguyên tắc chung: **phát ngay nếu sẵn sàng, không thì đợi**. Không hủy action vì máy chậm.

## 1. Bluetooth Android (`phone_bluetooth`)

```
Xe connect BT (đúng target)
  → BluetoothReceiver ACL
  → ACTION_BT_WATCH_A2DP
  → poll A2DP đến khi loa xe sẵn sàng
  → delay_seconds (min ~3s)
  → phát chào → stop → nhả focus
```

- Flutter không phát khi ACL.
- A2DP chưa sẵn sàng → **chờ**, không skip.

## 2. Bluetooth iOS

```
Đã set chào trong app
  → Shortcuts: Tự động hóa Bluetooth “Khi kết nối”
  → Phát lời chào HiCar (không hỏi trước)
  → Connect → Intent chạy nền → phát ngay hoặc đợi route
```

## 3. Android Auto (`phone_android_auto`) — khác BT

```
Có dây: CarConnection = projection → phát
Không dây: BT có thể nối trước → ACTION_AA_WATCH_PROJECTION
  → đợi CarConnection/gearhead
  → phát một lần / phiên
```

- Không đi luồng A2DP greeting.
- Xe chậm → giữ watch, **không hủy** greeting đang chờ.

## 4. Màn độ (`android_screen_mode`)

```
Nổ máy / auto launch → mở app → phát
  → xong → minimize/back
  → overlay hiện (workflow 03)
```

Resume từ nền (đã pause) → phát lại nếu bật play-on-open.

## 5. Box (`android_box_mode`) — cục box, khác màn độ

```
Nổ máy → box reboot
  → BootReceiver (chỉ khi android_box_mode)
  → FGS specialUse + boot_greeting.mp3 (Direct Boot)
  → poll audio focus / alarm 15s·40s·90s
  → phát ngầm
```

- Flutter open **không** phát chồng.
- Chi tiết: [`05-android-box-boot.md`](05-android-box-boot.md).

## 6. CarPlay

```
Set chào trong app
  → Shortcuts: Tự động hóa CarPlay “Khi kết nối”
     (hoặc Bluetooth — cùng Intent)
  → Connect → phát ngay hoặc đợi
```
