# 2026-09-20 — Tái cấu trúc agent docs (v7 stable)

Branch này là code v7 ổn định, version store bump lên `1.0.14+17`. Không đổi logic app; chỉ viết lại tài liệu agent cho dễ tìm và khóa 4 hợp đồng sản phẩm.

## Đã dọn

- `.agents/rules/rules1.md`, `rules2.md`
- `.agents/workflows/workflow1.md`
- `.agents/prompt/prompt_v1.md`

## Cấu trúc mới

- `AGENTS.md` — mục lục
- `.cursor/rules/` — core, modes, audio, overlay, iOS, sync, UI
- `.cursor/skills/` — fix theo mode, overlay màn độ, CarPlay Shortcuts, debug cắt tiếng
- `.agents/rules|workflows|prompt|changelog/` — nghiệp vụ tiếng Việt
- `docs/ARCHITECTURE.md` — bản đồ file
