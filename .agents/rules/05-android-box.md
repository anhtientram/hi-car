# Rules — Android Box (v7)

Cục **Android Box** cắm vào màn zin (USB / HDMI), chạy như mini PC có CH Play. App cài **trên box**, không trên điện thoại.

## Hợp đồng

Khi khởi động lại xe (tắt máy rồi nổ lại, kể cả qua đêm) → box boot → **tự phát lời chào ngầm**. Không bắt buộc mở UI. Box chậm thì đợi / retry, không hủy action boot.

## Owner

| Được | Không được |
|------|------------|
| `BootReceiver` → FGS delayed greeting + alarm 15s / 40s / 90s / 180s / 360s | Flutter `_initPlayOnOpen` / resume play |
| File `boot_greeting.mp3` vùng device-protected | Chỉ dựa `BOOT_COMPLETED` một lần rồi bỏ |
| Session theo `BOOT_COUNT` / kernel `boot_id` | Debounce theo đồng hồ tường (box hay **không có RTC**) |

## Flow

```
Nổ máy → box reboot
  → LOCKED_BOOT / BOOT_COMPLETED / QUICKBOOT / USER_UNLOCKED
  → mode == android_box_mode + đã login + có file chào
  → start FGS (type specialUse từ boot, API 34+)
  → poll audio focus (~2s ấm, cold thì đợi)
  → phát boot_greeting.mp3
  → nếu chưa phát thật: alarm retry, không chốt “đã chào”
```

Mở app lần đầu sau khi set chào = **copy** file sang Direct Boot. Lần boot sau mới có nhạc.

## Khác màn độ

- Màn độ: cài trên màn, mở app mới phát, overlay khi back.
- Box: phát ngầm khi boot, overlay không phải đường auto-play.

## Test

Power off **2–5 phút** rồi bật (xem `docs/TEST_CASES.md`). Fast reboot không đủ cho cold boot.
