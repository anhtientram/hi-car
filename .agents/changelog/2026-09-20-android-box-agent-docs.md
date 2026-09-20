# 2026-09-20 — Bổ sung Android Box vào agent docs

Mode `android_box_mode` vốn đã chạy ổn trên code v7 nhưng lần tái cấu trúc trước chỉ ghi chú ngắn. Bổ sung ngang hàng BT / AA / màn độ / CarPlay.

## Thêm

- `.cursor/rules/android-box.mdc`
- `.cursor/skills/android-box-boot-play/SKILL.md`
- `.agents/rules/05-android-box.md`
- `.agents/workflows/05-android-box-boot.md`

## Hợp đồng

Cục box gắn màn zin. Khởi động lại xe → tự phát ngầm. Box chậm thì đợi / retry. Flutter không phát chồng. Session theo `BOOT_COUNT` (box không RTC). FGS boot = `specialUse`.

Không đổi code app.
