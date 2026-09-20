---
name: debug-playback-cut
description: Diagnose and fix greeting audio that starts then dies after 1–3s on Android head units. Use when user reports MediaPlayer errors 100/2, 1/-32, 1/-38, focus loss, silent stop, or sync DNS errors alongside cut audio.
---

# Debug playback cut (2–3s rồi tịt)

## 1. Tách 2 lỗi

| Triệu chứng | Ý nghĩa |
|-------------|---------|
| `Failed host lookup` / Dio | Sync only — không tắt MediaPlayer local |
| `MediaPlayer error what=100 extra=2` + `1/-32` + `1/-38` | Player bị destroy giữa chừng (focus / HAL) |
| `playAudio called` không có `playAudio OK` | Player chết từ lần trước, `reset()` trên xác |
| Connect rồi im, không retry | Watch bị **hủy** vì timeout — vi phạm hợp đồng “máy chậm thì đợi” |

## 2. Thu log

```bash
adb logcat -c && adb logcat -v time | grep -Ei "HiCarAudio|HiCarService|HiCarBoot|HiCarAA|HiCarBT|AudioFlinger|MediaPlayer|requestAudioFocus"
```

Trong app: **Báo cáo lỗi** (`HiCarDiagnosticLog`).

## 3. Checklist

1. Radio/YouTube cướp focus → `handleFocusChange` không hard-stop clip chào.
2. File mp3 cụt → `SyncService` verify + re-download.
3. Không retry sau `SERVER_DIED`.
4. Flutter + native cùng phát.
5. A2DP/AA watch timeout → skip (phải đợi, không hủy action).

## 4. Fix

Đọc [`.cursor/rules/audio-playback.mdc`](../../rules/audio-playback.mdc) và skill `fix-by-connection-mode`.

Ổn định mọi device — không patch 1 ROM rồi phá mode khác.
