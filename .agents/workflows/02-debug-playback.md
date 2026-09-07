# Workflow — Debug nhạc cắt / sync lỗi

## Khi user gửi log

1. Phân loại: DNS/Dio vs MediaPlayer vs stop tường minh (`ACTION_STOP_*`).
2. Hỏi / lấy: `connection_mode`, máy mới cài hay đã sync trước, màn độ hay box.
3. Chạy skill `.cursor/skills/debug-playback-cut/SKILL.md`.
4. Nếu sửa theo mode → skill `fix-by-connection-mode`.

## Sau khi fix

- [ ] Build debug APK / analyze sạch phần đụng
- [ ] Ghi changelog ngắn vào `.agents/changelog/`
- [ ] Không phá owner playback của mode khác

## Lệnh

```bash
adb logcat -v time | grep -Ei "HiCarAudio|HiCarService|HiCarBoot|MediaPlayer"
flutter analyze
```
