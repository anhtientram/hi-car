# Giọng Thương Gia — Agent Index (v7 stable)

Baseline ổn định của repo này. Package: `com.hicar.ora.limited`. Store version trên branch: `1.0.14+17` (code v7).

Đọc **đúng file** theo việc đang làm. Không nhét hết context vào prompt. **Không viết code app** trừ khi user yêu cầu sửa hành vi.

---

## Tìm nhanh

| Cần gì | Mở đâu |
|--------|--------|
| Rule luôn áp dụng | [`.cursor/rules/project-core.mdc`](.cursor/rules/project-core.mdc) |
| Hợp đồng 5 mode (BT / AA / Màn độ / Box / CarPlay) | [`.cursor/rules/connection-modes.mdc`](.cursor/rules/connection-modes.mdc) |
| Phát nhạc native + focus | [`.cursor/rules/audio-playback.mdc`](.cursor/rules/audio-playback.mdc) |
| Bong bóng nổi màn độ | [`.cursor/rules/overlay-keepalive.mdc`](.cursor/rules/overlay-keepalive.mdc) |
| Android Box boot | [`.cursor/rules/android-box.mdc`](.cursor/rules/android-box.mdc) |
| iOS CarPlay / Shortcuts BT | [`.cursor/rules/ios-carplay.mdc`](.cursor/rules/ios-carplay.mdc) |
| Sync / offline | [`.cursor/rules/offline-sync.mdc`](.cursor/rules/offline-sync.mdc) |
| UI Flutter | [`.cursor/rules/flutter-ui.mdc`](.cursor/rules/flutter-ui.mdc) |
| Skill: sửa theo mode | [`.cursor/skills/fix-by-connection-mode/SKILL.md`](.cursor/skills/fix-by-connection-mode/SKILL.md) |
| Skill: overlay sau reboot | [`.cursor/skills/overlay-keepalive-headunit/SKILL.md`](.cursor/skills/overlay-keepalive-headunit/SKILL.md) |
| Skill: Android Box boot | [`.cursor/skills/android-box-boot-play/SKILL.md`](.cursor/skills/android-box-boot-play/SKILL.md) |
| Skill: CarPlay + Shortcuts | [`.cursor/skills/ios-carplay-shortcuts/SKILL.md`](.cursor/skills/ios-carplay-shortcuts/SKILL.md) |
| Skill: nhạc cắt 1–3s | [`.cursor/skills/debug-playback-cut/SKILL.md`](.cursor/skills/debug-playback-cut/SKILL.md) |
| Bản đồ file | [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) |
| Workflow nghiệp vụ | [`.agents/workflows/`](.agents/workflows/) |
| Rules tiếng Việt | [`.agents/rules/`](.agents/rules/) |
| System prompt | [`.agents/prompt/system-prompt.md`](.agents/prompt/system-prompt.md) |

---

## Hợp đồng sản phẩm (giữ nguyên khi sửa)

1. **Bluetooth (Android và iOS)** — vừa kết nối là phát nhạc ngay hoặc chờ cho kịp để phát, tránh lỗi xảy ra.
2. **Màn độ** — khởi động lại máy (tắt xe rồi sang hôm sau mở lại) → vào app, phát nhạc xong back ra ngoài → hiện bong bóng nổi. Bong bóng phải luôn duy trì dù khách mở YouTube nghe nhạc hay làm gì đó.
3. **Android Auto** (khác Bluetooth) — khi connect xong phát nhạc (cả không dây lẫn có dây). Máy nào chậm thì đợi, tránh hủy luôn cái action đó.
4. **CarPlay** — set nhạc chào rồi, ra cài đặt tự động hóa CarPlay hoặc tự động hóa Bluetooth; khi connect xong phải phát nhạc ngay, hoặc đợi.
5. **Android Box** — cục box gắn màn zin. Khởi động lại xe (kể cả qua đêm) → box boot → tự phát nhạc ngầm; box chậm thì đợi / retry, không hủy. Flutter không phát chồng.

Chi tiết: [`.agents/rules/02-connection-modes.md`](.agents/rules/02-connection-modes.md) · workflow [`.agents/workflows/02-connection-autoplay.md`](.agents/workflows/02-connection-autoplay.md).

---

## Chế độ (`connection_mode`)

| Prefs | Tên | Ai phát auto |
|-------|-----|----------------|
| `phone_bluetooth` | Điện thoại + BT | Native `ACTION_BT_WATCH_A2DP` — đợi A2DP rồi phát / đợi tiếp |
| `phone_android_auto` | Android Auto | Native CarConnection + MediaSession — **không** đi luồng BT |
| `android_screen_mode` | Màn độ | Flutter play-on-open / resume + overlay khi back |
| `android_box_mode` | Android Box (cục box) | Native `BootReceiver` + boot watch / alarm — Flutter open **không** phát chồng |
| `ios_carplay` | iPhone | App Intents / Shortcuts (CarPlay **hoặc** Bluetooth) |

Một sự kiện auto-play = **một owner** (Flutter **hoặc** native). Máy chậm → **đợi**, không hủy action đang chờ.

---

## Khi sửa code (chỉ khi user yêu cầu)

1. Ổn định mọi loại máy (màn rẻ / xịn / chậm) — không abort vì timeout cứng.
2. Log sự kiện quan trọng qua `HiCarDiagnosticLog`.
3. Overlay màn độ không được chết vì YouTube / app khác lấy audio focus.
4. `overlayMain` giữ trong `lib/main.dart`.
5. Box: không thêm Flutter play-on-open; không đổi session sang đồng hồ tường.
