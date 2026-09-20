# Workflow — Overlay màn độ sau khi tắt xe qua đêm

## Kịch bản khách

1. Tắt xe (màn shutdown hoặc ngủ đông).
2. Sang hôm sau mở lại.
3. Vào app Giọng Thương Gia.
4. Phát nhạc (tự hoặc bấm).
5. Back ra ngoài.
6. **Bong bóng nổi phải hiện.**
7. Mở YouTube / app khác nghe nhạc → **bong bóng vẫn còn**, bấm được chào / tạm biệt.

## Checklist kỹ thuật

- [ ] Quyền overlay còn sau reboot
- [ ] `is_bubble_enabled` không bị reset false oan
- [ ] `paused` → `showOverlay`; chỉ `resumed` của app này mới `hideOverlay`
- [ ] Không `closeOverlay` khi mất audio focus
- [ ] FGS sống (YouTube không kill service)
- [ ] Release: `overlayMain` trong `lib/main.dart`

## Khi hỏng

Chạy skill `.cursor/skills/overlay-keepalive-headunit/SKILL.md`.

Không “sửa” bằng cách tắt bubble khi có app media khác.
