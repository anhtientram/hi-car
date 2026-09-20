# Workflow — Android Box boot auto-play

## Kịch bản khách

1. App cài trên **cục box** gắn màn zin, mode `android_box_mode`, đã login, đã set lời chào (mở app một lần để copy `boot_greeting.mp3`).
2. Tắt xe (cắt nguồn box).
3. Hôm sau nổ máy.
4. Box boot xong → **tự phát lời chào ra loa xe**, không cần chạm app.
5. Box boot chậm → vẫn phát (đợi focus / alarm retry), không im luôn.

## Checklist kỹ thuật

- [ ] `connection_mode=android_box_mode` (BootReceiver skip mọi mode khác)
- [ ] Có `auth_token` (kể cả device-protected khi Direct Boot)
- [ ] `boot_greeting.mp3` tồn tại ở `createDeviceProtectedStorageContext().filesDir`
- [ ] FGS boot dùng `specialUse`, không `mediaPlayback` từ `BOOT_COMPLETED` (API 35)
- [ ] Session mới khi `BOOT_COUNT` / `boot_id` đổi — không kẹt vì đồng hồ reset
- [ ] Poll readiness; timeout chỉ **best-effort + retry**, không hủy phiên
- [ ] Flutter open app **không** phát chồng
- [ ] Logout → BootReceiver không phát

## adb

```bash
adb shell am broadcast -a android.intent.action.BOOT_COMPLETED -p com.hicar.ora.limited
adb logcat -v time | grep -Ei "HiCarBoot|HiCarService|HiCarAudio"
```

Khi hỏng: skill `.cursor/skills/android-box-boot-play/SKILL.md`.
