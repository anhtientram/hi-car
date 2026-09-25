# Stability regression / pilot gate — 2026-09-25

Branch được kiểm tra: `feat/v15`; pubspec `1.0.15+18`.
Đây là checklist nghiệm thu sau sửa, **không phải chứng nhận đã chạy trên mọi thiết bị**.
Không kết luận lỗi do firmware chỉ từ MediaPlayer `what=100 extra=2` hoặc `1/-32`.

## Phạm vi hỗ trợ và nguyên tắc

- APK debug đã merge manifest với `minSdkVersion=24`, `targetSdkVersion=35`: Android 7 trở lên, có ABI ARM 32-bit và ARM64 trong cấu hình build. Android 10 thuộc phạm vi cần sửa/test; không blacklist cả Android 10.
- Nhánh API < 24 trong code không đồng nghĩa APK hiện tại cài được Android 5/6. Muốn hỗ trợ thấp hơn phải kiểm tra lại SDK/plugin/build riêng, không chỉ hạ một con số.
- iOS project deployment target 13; App Intents/Shortcuts của app yêu cầu iOS 16+. Simulator không thay cho thử CarPlay/BT thật.
- Một owner cho mỗi autoplay: native BT, native AA, Flutter màn độ, native Box boot, iOS Shortcuts.
- Chờ route/focus không có hạn 90 giây. Hỏng player thật mới tiêu thụ ngân sách phục hồi: Android hai lần dựng lại (2.5s, 7.5s); hết ngân sách báo lỗi, không quay vòng vô hạn.
- Không fallback phát ra loa điện thoại khi route xe chưa được xác nhận. Android Auto không dùng “app gearhead đang chạy” thay bằng chứng projection.
- Stop, logout, đổi mode/target và ngắt kết nối xác nhận được là hủy hợp lệ. Chậm chưa sẵn sàng không phải lỗi terminal.

## Thay đổi đã đưa vào code

- PlaybackJob giữ owner, attempt, trạng thái, checkpoint và retry; callback player cũ không được kết thúc player mới.
- Native player mới sau media-server/decoder error; release ngoài callback; prepare bất đồng bộ; chờ focus qua handler, hỗ trợ listener API < 26.
- Health check phát hiện prepare/player không tiến triển 60s; **không** dùng thời gian chờ focus để giả định phát thành công.
- Box giữ alarm đến khi completion thật, dùng foreground-service PendingIntent ở API 26+; dấu started không khóa việc phục hồi sau process death. Checkpoint mỗi 5 giây; phần trước checkpoint cuối có thể lặp vài giây khi tiến trình chết.
- AA nghe broadcast CarConnection công khai và observer; query provider ở worker, không chặn main thread. Trạng thái unknown không bị coi là disconnect.
- BT readiness dùng public A2DP proxy của đúng địa chỉ target, không ghép ACL của xe với A2DP của tai nghe khác.
- Flutter chỉ auto play-on-open/resume cho màn độ. Khóa chống race trước await; hỏi trạng thái native thay vì timer đoán thời lượng. Thất bại/hủy không tự minimize.
- Sync tải file tạm, kiểm tra header/size, rename không xóa file tốt trước. Tải bản mới lỗi giữ cả path/hash cũ để lần sau còn retry; sync thiếu file báo partial failure. Asset lưu Documents/hicar_audio, không phụ thuộc temporary cache.
- Boot copy so sánh nội dung SHA-256, không chỉ độ dài. Rename cùng thư mục giữ inode cho decoder đang đọc. Đây không phải xác minh chữ ký/hash do server cung cấp.
- Bubble không mất lựa chọn bật chỉ vì kiểm tra quyền thất bại; show/hide xếp hàng; sticky service chịu được null intent. Patch overlay nằm trong build dự án, không ghi global Pub cache.
- iOS main-actor ownership, kiểm tra callback cũ, media-services reset/interruption, chờ route, decode error không giả completion; tìm lại file trong hicar_audio khi container đổi.
- Log native/Dart/iOS lưu trước khi Flutter attach; mã job/mode/attempt/vị trí/file/OS/model/route/focus và stack ở điểm lỗi. Giữ riêng lỗi quan trọng và resolution bên cạnh timeline; redaction token/MAC trong pipeline.
- Popup phân biệt “mã báo cáo” với mã lỗi hệ điều hành; đúng mode, có chi tiết kỹ thuật, đóng/gửi; chỉ hiện thử lại cho lỗi phát phù hợp; cuộn được trên màn hình nhỏ.

## Test tự động và cách chạy

Dùng đúng SDK tại `.fvm/flutter_sdk`, không dùng SDK mặc định khác version của máy.

```sh
.fvm/flutter_sdk/bin/flutter test --no-pub --reporter expanded
.fvm/flutter_sdk/bin/flutter analyze --no-pub --no-fatal-infos
cd android
./gradlew :app:testDebugUnitTest --console=plain
```

Android dùng JUnit và Robolectric **chỉ trong testImplementation**, không thêm vào APK production.
Lần đầu cần mạng tải dependency và Android framework test jars.

Các nhóm test:

- Dart: classifier đủ 5 mode; log persistence/redaction/dismiss/resolve; import lỗi trước khi có Flutter; 500 warning chờ không xóa lỗi; partial sync giữ bản tốt; metadata duration roundtrip.
- Flutter channel/lifecycle: bài 74 giây; pending trên 90 giây; hai lệnh mở/resume đua nhau; failed/cancelled/idle không minimize; Flutter không chiếm owner BT/AA/Box/CarPlay.
- Overlay: quyền tạm mất vẫn giữ preference; hide thắng show chậm; không show ở bốn mode khác.
- Widget: popup có context/nút gửi/đóng; màn hình 480×240 không overflow.
- Kotlin policy: bốn mode Android, các lỗi 100/2, 1/-32, 1/-38, prepare stall -110; retry hữu hạn; chờ 24 giờ mô phỏng không hao retry; callback cũ; logout/auto-off/mode/target thay đổi.
- File I/O JVM: cùng size khác nội dung; nguồn hỏng giữ đích tốt; descriptor đang đọc vẫn đọc file cũ qua atomic replacement.
- Robolectric API 29 và 35: boot trùng; boot kế tiếp sau session completed; started/checkpoint không đồng nghĩa completed; failure không lây sang boot sau; lỗi không mất sau 1.100 dòng log khác.
- XCTest: ownership/cancel/retry policy dùng chung CarPlay và BT Shortcuts; đường dẫn container cũ; log iOS không cần Flutter.

Các bài trên **không mô phỏng đầy đủ HAL/codec của Sprd, audio thực qua xe, OEM kill policy, AA/CarPlay handshake hay cắt nguồn vật lý**.

## Test trên thiết bị — CHƯA CHẠY

Mỗi ca ghi: app version, hãng/model, Android/iOS/API, build fingerprint, mode, loại kết nối, file + duration, thời điểm thao tác, kết quả nghe thực tế, mã job/báo cáo. Chỉ thao tác khi xe đang đỗ.

### Bộ ca chung cho tất cả mode

- Cài mới và nâng cấp giữ nguyên dữ liệu; online/offline; file dài 75 giây; nhạc chào đã có không bị sync đổi lựa chọn.
- Chưa chọn nhạc; file thiếu; HTML/JSON lỗi trả từ server; file có header nhưng codec hỏng; mạng/DNS mất giữa tải; hết dung lượng.
- Mất quyền liên quan; thu hồi/cấp lại quyền; notification bị tắt; OEM hạn chế nền; auto-off; logout; đổi mode khi chờ và đang phát.
- Focus bị navigation/YouTube/cuộc gọi lấy; prepare treo; server audio chết sau 1–3 giây; stop trong lúc retry; callback completion cũ tới muộn.
- Pending 5s/90s/5 phút; phát đúng route sau khi sẵn sàng; không tạo popup lỗi chỉ vì pending.
- Gửi lỗi online thành công; gửi offline thất bại vẫn giữ báo cáo; đóng rồi mở lại; reboot trước khi mở màn báo lỗi; không lộ token.
- Sau mỗi ca: đúng một owner, không chồng tiếng, không success giả, lỗi có mã/chi tiết, không mang pending cũ sang mode mới.

### Bluetooth điện thoại

- Đúng xe mục tiêu; xe khác/tai nghe khác không phát. Target ACL có trước A2DP; A2DP của tai nghe đã nối sẵn không được dùng.
- Ngắt/nối lại 10 lần; hai broadcast connect; app đã mở, nền, bị OS thu hồi; tắt/bật Bluetooth.
- API 24/25, 29 (Android 10), 31/33 với Nearby Devices và 34/35+ với FGS restrictions.

### Android Auto

- Có dây và không dây; BT nối trước projection; chỉ cài/mở gearhead mà chưa nối xe thì không autoplay.
- CarConnection provider chậm/null/throw; broadcast hoặc observer đến riêng lẻ; mất projection khi đang phát; cắm lại.
- Xác nhận app browse/bind không mở player trước foreground service hợp lệ.

### Màn độ Android

- Sprd ums512_1h10_Natv Android 10 là ca pilot ưu tiên, cùng file 74.815s đã báo lỗi; lưu log cả lượt chạy tốt và lỗi.
- Mở app → chào hoàn tất → thu nhỏ → bubble. Error không tự thu nhỏ; retry không chồng tiếng.
- Nghe YouTube/navigation khi bubble hiện; mở/đóng app nhanh; quyền overlay trả lời chậm; hệ thống restart overlay với null intent.
- Cắt nguồn 8–12h rồi bật: ít nhất 3 ngày liên tiếp. Thử riêng ACC sleep/wake **không reboot**, không đánh đồng với BOOT_COMPLETED.

### Android Box

- Cold boot/Direct Boot chưa unlock; unlock sau 90s và sau vài phút; LOCKED_BOOT + BOOT_COMPLETED trùng.
- Kill process trước start, sau start trước checkpoint, giữa bài, sau completion. Chưa complete thì phục hồi; complete thì không lặp.
- Boot với clock bị reset/NTP nhảy; boot hôm sau sau khi hôm trước completed/failed/stopped.
- API 35 kiểm tra foreground policy thực và quyền/khai báo specialUse được chấp nhận. Khai báo manifest không tự bảo đảm OEM/Play sẽ cho chạy.
- Mở Flutter giữa boot không tạo lần phát thứ hai.

### iOS CarPlay / Bluetooth Shortcuts

- Hai automation riêng, cùng App Intent. CarPlay dây/không dây; BT target chọn trong Shortcuts. App foreground/background/khóa màn hình.
- Route tới trễ >30s; audio session activation tạm từ chối; gọi hai Shortcuts gần nhau; stop khi chờ; cuộc gọi/interruption/reset media services.
- Hệ điều hành hủy/suspend Shortcuts: xác nhận log/cảnh báo, không khẳng định app có thể vượt giới hạn thời gian chạy nền của iOS.
- Ngắt xe khi phát không chuyển lời chào sang loa iPhone; app/container update vẫn tìm được nhạc.

## Tiêu chí pilot / rollout

Chưa phát hành rộng chỉ dựa vào unit tests. Pilot tối thiểu một máy/ROM của từng nhóm:
Sprd Android 10 màn độ, màn độ khác hãng, Box Android cũ + mới, điện thoại AA dây/không dây, BT điện thoại, iPhone CarPlay/BT.
Giữ bản app và cấu hình/file cố định qua 3 đêm, ghi số lần trigger/start/complete/failed/duplicate/recovered theo job.
Không nghe được dù start() báo OK phải ghi “chưa chứng minh audible”, không tính thành công.

Nếu vẫn lỗi sau retry: giữ log, thông báo giới hạn đúng model/ROM và hướng dẫn khách gửi báo cáo; không kết luận toàn bộ Android 10 không hỗ trợ.
Force-stop thủ công, rút điện, SIGKILL và firmware không gửi sự kiện có thể không có callback cuối; log là best-effort, API 30+ có bổ sung historical process-exit reason.
