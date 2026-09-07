---
name: debug-playback-cut
description: Diagnose and fix greeting audio that starts then dies after 1–3s on Android head units. Use when user reports MediaPlayer errors 100/2, 1/-32, 1/-38, focus loss, silent stop, or sync DNS errors alongside cut audio.
---

# Debug playback cut (2–3s rồi tịt)

## 1. Tách 2 lỗi

| Triệu chứng | Ý nghĩa |
|-------------|----------|
| `Failed host lookup` / Dio connection | Sync only — không tự tắt MediaPlayer local |
| `MediaPlayer error what=100 extra=2` + `1/-32` + `1/-38` sát nhau | Player bị destroy giữa chừng (thường do focus / HAL) |
| `playAudio called` không có `playAudio OK` | Player chết từ lần trước, `reset()` trên xác |

## 2. Thu log

```bash
adb logcat -c && adb logcat -v time | grep -Ei "HiCarAudio|HiCarService|HiCarBoot|AudioFlinger|MediaPlayer|requestAudioFocus"
```

Trong app: xuất **Báo cáo lỗi** (`HiCarDiagnosticLog`) — cần thấy `Focus LOSS`, `stopPlayback`, `Phát lại`.

## 3. Checklist nguyên nhân

1. Focus bị radio/launcher màn độ cướp → xem `handleFocusChange` (không hard-stop).
2. File mp3 cụt → `SyncService.isValidAudioFile`, re-download `.part`.
3. Không retry sau `SERVER_DIED` → `onPlaybackError` + `retryPlayback`.
4. Flutter + native cùng phát → kiểm `connection_mode` ownership.
5. `ACTION_STOP_AUDIO` / BT disconnect trong log → nguồn dừng tường minh.

## 4. Fix hướng dẫn

Đọc rule [`.cursor/rules/audio-playback.mdc`](../../rules/audio-playback.mdc) và changelog [`.agents/changelog/2026-08-31-playback-cut-fix.md`](../../../.agents/changelog/2026-08-31-playback-cut-fix.md).

Ưu tiên: ổn định mọi device — không patch theo 1 ROM rồi phá mode khác.
