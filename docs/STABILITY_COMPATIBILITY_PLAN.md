# Plan ổn định đa OS và đa chế độ

## 1. Mục tiêu

Đưa ứng dụng Giọng Thương Gia về một kiến trúc ổn định trên nhiều Android version,
ROM màn hình xe, Android Box, Android Auto, Bluetooth và iOS/CarPlay mà không sửa
được mode này rồi làm hỏng mode khác.

Mục tiêu sản phẩm giữ nguyên theo `.agents/workflows/` và `.cursor/rules/`:

- Bluetooth: kết nối đúng thiết bị thì phát qua loa xe hoặc tiếp tục chờ đến khi route sẵn sàng.
- Android Auto: có dây và không dây đều phát một lần cho mỗi projection.
- Màn độ: mở app thì phát, phát xong back ra thì có bong bóng và bong bóng sống khi mở YouTube/app khác.
- Android Box: boot lại xe thì phát ngầm, không cần mở Flutter UI.
- CarPlay/Bluetooth iOS: Shortcuts/App Intent phát được khi app ở nền hoặc chờ audio route.
- Sync lỗi không được xóa audio local; file lỗi không được trở thành file active/boot.
- Mọi lỗi quan trọng phải xuất hiện trong báo cáo lỗi trong app.

## 2. Nguyên tắc không được phá

### 2.1. Một event chỉ có một owner

| Mode | Owner phát auto-play | Không được dùng |
|------|----------------------|-----------------|
| `phone_bluetooth` | Native A2DP watch | Flutter phát khi chỉ mới ACL connect |
| `phone_android_auto` | CarConnection/MediaSession | Dùng nhánh Bluetooth thay AA |
| `android_screen_mode` | Flutter lifecycle + native playback | Boot receiver làm owner auto-play |
| `android_box_mode` | BootReceiver + Direct Boot + native service | Flutter play-on-open hoặc overlay làm owner |
| `ios_carplay` | Shortcuts/App Intent + `AVAudioPlayer` | Android A2DP watch trên iOS |

Không thêm fallback phát nhạc ở một tầng khác nếu chưa xác định rõ owner hiện tại.

### 2.2. Chờ và retry, không hủy vì máy chậm

Timeout chỉ là mốc đánh giá sức khỏe hoặc đổi nhịp retry, không phải lý do bỏ lời chào
vĩnh viễn.

Action chỉ được hủy khi:

- thiết bị thật sự disconnect;
- người dùng tắt auto-play;
- người dùng đổi mode;
- người dùng bấm stop;
- session đã hoàn tất hoặc bị thay thế bởi session mới.

### 2.3. Tách logic chung và adapter OS

Logic chung:

```text
triggered
→ waiting_route
→ waiting_focus
→ starting
→ playing
→ completed
hoặc failed_retrying
```

Adapter riêng:

- Android API cũ: API audio focus/service/alarm cũ.
- Android API mới: FGS type, notification permission, background-start rules.
- iOS: `AVAudioSession`, route và App Intent.
- Mỗi mode: readiness signal riêng.

Không hạ `targetSdk`, không bỏ FGS mới và không dùng implementation OS cũ cho OS mới.

## 3. Kiến trúc playback cần đạt

### 3.1. Playback job

Mỗi lần auto-play tạo một job có:

- `jobId`;
- `mode`;
- `connectionId` hoặc `bootSessionId`;
- trigger source;
- created time và elapsed time;
- target device/route;
- retry count;
- current state.

Job mới phải thay thế job cũ cùng connection/session; job cũ không được phát song song.

### 3.2. Audio focus

- `LOSS_TRANSIENT`: pause và chờ focus quay lại.
- `LOSS`: không stop ngay clip chào; giữ pending recovery và xin focus lại qua `Handler`.
- `GAIN`: resume nếu job vẫn còn hợp lệ.
- Người dùng bấm stop hoặc đổi mode mới release toàn bộ recovery.
- Mọi focus change phải ghi log, bao gồm kết quả request/abandon.

### 3.3. MediaPlayer

- Tạo player mới cho mỗi lần phát.
- Dùng `prepareAsync()` và callback trạng thái rõ ràng.
- Không reuse player sau `SERVER_DIED` hoặc error.
- Release player ngoài callback nếu cần để tránh state invalid.
- Có watchdog phát hiện player đã start nhưng không tiến triển.
- Error phải tạo retry bằng player mới, không gọi lại trên player hỏng.

## 4. Kế hoạch theo mode

### Phase A — Bluetooth Android

- Native A2DP watch là owner duy nhất.
- ACL connect chỉ tạo pending job.
- Poll đúng target A2DP; log trạng thái mỗi khoảng thời gian vừa phải, không log mỗi vòng.
- Không dùng timeout 90 giây để bỏ action.
- Sau mốc dài: chuyển sang backoff/alarm nhưng vẫn giữ job.
- Chỉ dừng khi ACL/A2DP disconnect thật hoặc mode thay đổi.
- Dedup bằng `connectionId`/target address, không dùng timeout để chống lặp.

### Phase B — Android Auto

- Giữ CarConnection cho có dây và không dây.
- Bluetooth chỉ là tín hiệu khởi động watch, không phải readiness.
- Chờ projection/gearhead thật sự sẵn sàng.
- Một greeting cho mỗi projection session.
- Khi projection mất, đóng job của session đó; nếu projection mới xuất hiện thì tạo job mới.
- Không để `onGetRoot`, ContentObserver và Bluetooth trigger phát ba lần.

### Phase C — Màn độ và overlay

- Flutter play-on-open/resume là owner.
- Không giới hạn chờ audio list ở một mốc cứng rồi bỏ luôn; giữ pending hoặc retry có giới hạn hợp lý.
- Chỉ hide overlay khi app này `resumed`.
- App `paused` thì show overlay.
- `inactive` không được hide.
- Audio focus của YouTube/radio không được đóng overlay.
- Overlay bridge phải hoạt động kể cả isolate chính bị kill.
- Kiểm tra clear recent, reboot, permission overlay và FGS sống lâu.

### Phase D — Android Box

- BootReceiver là owner duy nhất.
- Dùng `BOOT_COUNT`, kernel `boot_id`, rồi mới fallback wall-clock.
- File `boot_greeting.mp3` phải nằm ở Direct Boot storage trên API hỗ trợ.
- API quá cũ phải có fallback credential storage/file thường hoặc được đánh dấu không hỗ trợ đầy đủ.
- Boot FGS dùng type phù hợp theo API; không dùng `mediaPlayback` từ boot trên Android mới.
- Poll focus/route và retry bằng alarm/backoff.
- Không đánh dấu session hoàn tất chỉ vì gọi `start()`; cần xác nhận playback thực sự bắt đầu.
- Boot broadcast trùng phải reuse cùng session; boot thật phải tạo session mới.

### Phase E — iOS/CarPlay/Bluetooth

- Một greeting dùng chung cho CarPlay automation và Bluetooth automation.
- `AVAudioSession` cấu hình lúc launch và trước khi phát.
- Intent chạy nền, không yêu cầu Flutter UI foreground.
- Nếu route chưa sẵn sàng thì wait/retry, không trả false ngay.
- Đường dẫn cũ phải có fallback theo filename trong Documents.
- Xác định rõ iOS tối thiểu cho App Intent; iOS quá cũ cần fallback hoặc hiển thị giới hạn hỗ trợ.

## 5. Tương thích OS mà không gây xung đột

### Android API

| Nhóm | Cách xử lý |
|------|------------|
| API 21–23 | Service/audio focus/alarm cũ; file storage thường; không phụ thuộc Device Protected Storage |
| API 24–25 | Có Direct Boot nhưng phải kiểm tra quyền/ROM; fallback khi `BOOT_COUNT` không đọc được |
| API 26–33 | `startForegroundService`, media playback FGS, notification channel |
| API 34 | Khai báo đúng FGS type và permission; kiểm tra notification permission |
| API 35+ | Boot Box dùng nhánh được phép; không khởi động media playback FGS từ `BOOT_COMPLETED` |

Mỗi API guard chỉ nằm ở adapter tương thích. State machine, session/dedup và log dùng chung.

### Quyết định hỗ trợ

- Không hứa “mọi ROM đều chạy như nhau”.
- Với ROM chặn autostart/FGS/audio route, app phải báo rõ capability và hướng dẫn người dùng.
- Không âm thầm coi lỗi là thành công.
- Nếu OS không hỗ trợ một tính năng nền, báo `unsupported/degraded`, không ghi `completed`.

## 6. Hệ thống log và Báo lỗi trong app

### 6.1. Khởi tạo sớm

Native diagnostic logger phải khởi tạo từ service/receiver trước khi xử lý boot hoặc playback.
Flutter, native service và overlay có thể chạy ở process/isolate khác nhau nhưng báo cáo cuối
cùng phải gộp được log của cả ba tầng.

### 6.2. Schema log tối thiểu

Mỗi event quan trọng lưu:

```text
timestamp wall-clock + elapsedRealtime
OS/API + manufacturer + model
connection_mode
jobId / connectionId / bootSessionId
trigger source
state before → state after
audio route
audio focus result
file path, exists, size, validation result
retry count + next retry time
error code, exception, stack/context
```

### 6.3. Các event bắt buộc

- app/service/receiver start và stop;
- mode load/change;
- target device match/mismatch;
- ACL, A2DP, CarConnection, gearhead;
- route waiting định kỳ;
- audio focus request/change/abandon;
- player create/prepare/start/completion/error/release;
- retry schedule/fire/cancel;
- boot session create/reuse/complete/miss;
- overlay show/hide/error;
- MethodChannel missing/plugin exception;
- file download, validation, pin, copy boot;
- mọi exception ở `catch` quan trọng.

### 6.4. Không được mất log

- Không để `catch (_) {}` nuốt lỗi quan trọng.
- Logcat và file persist phải ghi song song.
- Lỗi ghi file log phải được báo ra Logcat.
- Không lọc mất warning boot/route trong báo cáo lỗi.
- Có `Recent activity` và `Errors`, không chỉ lấy dòng `ERROR`.
- File log dùng ring buffer có giới hạn, nhưng không xóa session gần nhất trước khi export.
- Export báo cáo gồm metadata thiết bị, mode, full log và error summary.
- Có cơ chế redaction token, URL nhạy cảm và thông tin cá nhân trước khi gửi.

### 6.5. Incident Popup khi action thật sự bị hủy/lỗi

Khi một playback job hoặc connection action bị hủy do lỗi thật, app phải hiển thị một
popup rõ ràng cho người dùng. Popup không được xuất hiện chỉ vì app đang chờ route/focus
hoặc đang retry bình thường.

#### Điều kiện hiển thị

Hiển thị popup khi:

- thiếu quyền bắt buộc và hệ thống không thể tiếp tục;
- Bluetooth/A2DP hoặc Android Auto bị disconnect thật;
- Android Box boot session hết khả năng retry an toàn;
- FGS/service bị hệ điều hành từ chối hoặc bị dừng;
- audio route không tồn tại sau khi đã retry theo policy;
- file greeting/boot bị mất, hỏng hoặc không validate được;
- MediaPlayer/AVAudioPlayer thất bại và recovery không thành công;
- mode không được hỗ trợ bởi OS/ROM hiện tại.

Không hiển thị popup khi:

- A2DP/CarConnection/route vẫn đang được chờ;
- audio focus vừa mất nhưng recovery job vẫn còn;
- đang retry với backoff;
- popup cùng `incidentId` đã hiển thị, tránh spam nhiều lần.

#### Nội dung popup

Popup phải hiển thị bằng ngôn ngữ người dùng, tránh chỉ đưa mã lỗi kỹ thuật:

```text
Tiêu đề: Không phát được lời chào
Vấn đề: Android Auto chưa sẵn sàng hoặc quyền Bluetooth chưa được cấp.
Thiết bị: [manufacturer] [model]
OS: Android [version] / API [level]
Mode: [connection_mode]
Kết nối: [Bluetooth/A2DP/Android Auto/Box/CarPlay]
Trạng thái: [route/focus/service/file]
Mã sự cố: [incidentId]
```

Thông báo phải chỉ rõ bước xử lý nếu có thể:

- “Hãy bật quyền Thiết bị lân cận cho ứng dụng.”
- “Hãy tắt tối ưu pin/cho phép tự khởi động trên thiết bị này.”
- “Android Auto chưa hoàn tất kết nối; hãy giữ xe ở trạng thái kết nối và thử lại.”
- “Không tìm thấy file lời chào; hãy mở app và đồng bộ lại audio.”
- “ROM này đã chặn chạy nền; hãy cho phép ứng dụng chạy nền/Autostart.”
- “OS hiện tại không hỗ trợ tự động phát nền; hãy mở app để phát thủ công.”

Không hiển thị token, URL có thông tin nhạy cảm, số điện thoại, mật khẩu hoặc full path
nội bộ trong popup.

#### Hành động của popup

Popup bắt buộc có:

- `Gửi báo lỗi`: đóng gói incident summary + device/mode metadata + log liên quan và mở
  luồng gửi báo cáo;
- `Thử lại`: tạo job mới hợp lệ, không lặp lại job cũ đã failed;
- `Đóng`: đóng popup nhưng giữ incident trong lịch sử để người dùng gửi sau.

Nếu lỗi là permission/settings, có thể thêm nút `Mở cài đặt` dẫn đúng màn hình cần thiết.
Nếu hệ thống không cung cấp deep link ổn định, chỉ hiển thị hướng dẫn cụ thể và không làm
crash app.

#### Incident lifecycle

Mỗi lỗi có một `incidentId` và vòng đời:

```text
detected
→ shown
→ dismissed / retry_requested / report_requested
→ resolved hoặc kept_for_report
```

Popup phải tồn tại độc lập với lifecycle của Flutter UI: lỗi xảy ra khi native service,
BootReceiver hoặc overlay đang chạy vẫn phải được lưu lại và hiển thị khi người dùng mở app.

#### Quy tắc chống popup giả và popup lặp

- Chỉ một popup cho mỗi `incidentId` trong một khoảng thời gian.
- Các retry nội bộ chỉ cập nhật nội dung/log của incident hiện tại.
- Khi playback thành công, đánh dấu incident cũ là resolved; không hiện lại warning đã xử lý.
- Khi lỗi lặp lại sau một connection/boot session mới, tạo `incidentId` mới.
- Popup không được che hoặc làm dừng audio đang phát thành công ở mode khác.

#### Báo cáo gửi tại popup

Gói báo cáo tối thiểu:

- thời gian lỗi và timezone;
- manufacturer, model, OS/API, app version;
- connection mode và connection type;
- job/session/incident ID;
- bước cuối đã thành công;
- lỗi hiện tại và error code;
- audio route/focus/service status;
- số lần retry và nguyên nhân hủy;
- log quanh incident và full log tùy người dùng chọn;
- trạng thái quyền liên quan.

Trước khi gửi phải redaction dữ liệu nhạy cảm, hiển thị cho user biết nội dung nào sẽ được
gửi, và cho phép đóng popup mà không gửi gì.

## 7. Đồng bộ audio an toàn

- Tải vào `.part`.
- Kiểm tra HTTP status, size tối thiểu và MP3 header.
- Rename atomic sau khi validate.
- Hash đổi nhưng file local lỗi thì tải lại.
- Không pin file chưa hợp lệ vào active/boot.
- Copy boot qua file tạm rồi rename.
- DNS/sync lỗi không được stop local playback.
- Khi sync xong mới cập nhật native path và Direct Boot copy.

## 8. Test không cần hardware

Tạo fake adapter và unit tests mô phỏng:

- A2DP sẵn sàng sau 5 giây, 90 giây, vài phút;
- Android Auto projection đến sau Bluetooth;
- route không bao giờ sẵn sàng;
- focus loss/loss transient/gain;
- MediaPlayer error `100/2`, `1/-32`, `1/-38`, prepare failure;
- process/service bị kill rồi khởi động lại;
- boot broadcast trùng và boot session mới;
- file tải dở, MP3 hỏng, hash mismatch;
- MethodChannel chưa attach;
- overlay isolate sống còn isolate chính chết;
- đổi mode trong lúc đang pending.

## 9. Trạng thái triển khai đợt nền tảng trước

Đã triển khai các hạng mục nền tảng sau:

- Native Android chờ A2DP/Android Auto/audio focus không còn hủy cứng ở 90 giây; Box boot tiếp tục poll và có backoff alarm dài hơn.
- MediaPlayer dùng instance mới + `prepareAsync()` + wake mode + guard player cũ; lỗi phát ghi log, release an toàn và tạo retry phù hợp.
- Android Box có fallback API < 24, session boot không phụ thuộc RTC, copy boot qua file tạm/rename và validator audio dùng chung.
- Sync Flutter tải qua `.part`, validate header/size rồi mới rename; sync lỗi không thay file local hợp lệ và không pin file hỏng.
- AppLogger persist log, bắt lỗi Flutter/unhandled Dart, native diagnostic giữ cả warning/error và redaction thông tin nhạy cảm.
- Incident popup hiển thị thông điệp tiếng Việt, mode, kết nối, thiết bị, OS, mã sự cố; có Đóng / Thử lại / Gửi báo lỗi.
- Overlay bridge, Bluetooth receiver và native playback error đều đẩy sự cố về diagnostic pipeline.
- iOS App Intent chờ route CarPlay/Bluetooth trước khi phát; iOS cũ hơn iOS 16 được thông báo giới hạn tự động hóa.

Đã kiểm tra bằng Flutter test, Android Kotlin compile và iOS simulator build. Vì không có head unit/Android Box thực tế trong môi trường này, vẫn cần thu thập log pilot từ các nhóm OS/ROM thật trước khi phát hành rộng.

Mỗi test phải kiểm tra cả:

- có phát đúng một lần hay không;
- có retry đúng hay không;
- có bị phát chồng hay không;
- session có hoàn tất sai hay không;
- báo cáo lỗi có đủ event hay không.

## 9.1. Regression gate sau mỗi thay đổi

Không merge thay đổi mode nếu chưa kiểm tra:

- owner auto-play không đổi;
- mode khác không nhận nhầm event;
- disconnect dừng đúng job;
- reconnect tạo session mới;
- slow device không bị cancel vĩnh viễn;
- log xuất hiện khi thành công, đang chờ và thất bại;
- sync lỗi không làm mất local file;
- `flutter analyze`, Kotlin compile và iOS compile phần bị đụng.

## 10. Thứ tự triển khai

1. Ổn định logger, export báo cáo và hiển thị full diagnostic.
2. Thêm job/session/state machine và dedup rõ ràng.
3. Sửa MediaPlayer/audio focus/recovery.
4. Sửa Bluetooth và Android Auto watch: timeout thành health checkpoint + backoff.
5. Sửa Box Direct Boot, session và retry theo API.
6. Sửa Màn độ/overlay keep-alive.
7. Sửa iOS route wait/retry và policy iOS cũ.
8. Sửa sync `.part`/validate/atomic rename.
9. Chạy fake tests + build matrix.
10. Phát hành bản pilot có báo cáo lỗi đầy đủ để thu log từ thiết bị thực tế.

## 11. Tiêu chí hoàn thành

Kế hoạch chỉ được coi là đạt khi:

- không còn watch nào tự bỏ action chỉ vì một timeout cố định;
- không còn audio error quan trọng bị catch im lặng;
- mọi auto-play event có owner và session rõ ràng;
- mỗi mode phát tối đa một lần cho một connection/boot session;
- mất focus không làm mất vĩnh viễn greeting;
- Box không phụ thuộc Flutter UI;
- overlay không phụ thuộc audio focus;
- sync file hỏng không được pin;
- màn hình Báo lỗi luôn có ít nhất lifecycle/trigger/state cuối cùng, kể cả khi lỗi xảy ra trước khi Flutter mở;
- lỗi thật bị hủy phải tạo Incident Popup có nguyên nhân, model, OS, mode, mã sự cố và nút gửi/đóng;
- trạng thái chờ/retry bình thường không được tạo popup gây phiền;
- fake test mô phỏng được thiết bị chậm, route lỗi, process kill và callback trễ;
- thay đổi API cũ không làm thay đổi nhánh hành vi của API mới.

## 12. Giới hạn thực tế

Không thể đảm bảo tuyệt đối mọi ROM xe nếu ROM chặn autostart, foreground service,
Bluetooth profile hoặc audio route. Khi gặp trường hợp đó, mục tiêu là:

1. phát hiện đúng capability;
2. giữ retry an toàn nếu OS còn cho phép;
3. ghi đủ log để xác định giới hạn của ROM;
4. báo rõ degraded/unsupported thay vì im lặng;
5. không làm hỏng các OS và mode khác.
