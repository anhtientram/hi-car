# Google Play — Văn bản làm rõ & checklist nộp store

Tài liệu dành cho người điền **Play Console**. Copy/chỉnh các đoạn bên dưới cho khớp thông tin thật của đơn vị vận hành.

---

## A. Mô tả ngắn (Short description) — gợi ý ≤ 80 ký tự

```
Tự động phát lời chào/tạm biệt cho tài xế: Bluetooth, Android Auto, màn xe, Box.
```

## B. Mô tả đầy đủ (Full description) — gợi ý

```
Giọng Thương Gia (Chào Xe Tự Động) hỗ trợ tài xế và nhà xe phát lời chào, lời tạm biệt khi đón khách.

TÍNH NĂNG CHÍNH
• Đồng bộ nhạc về máy và phát offline (không phụ thuộc sóng khi đang chạy)
• Nhiều chế độ: Điện thoại + Bluetooth, Android Auto, màn Android trên xe, Android Box
• Tự phát khi kết nối / mở app / khởi động Box (tùy cấu hình)
• Nút nổi để phát Chào / Tạm biệt khi đang dùng app điều hướng
• Studio tạo bản nghe thử lời chào AI và gửi cấu hình lên hệ thống quản trị

LƯU Ý VỀ MUA HÀNG / THANH TOÁN
Ứng dụng không bán nội dung số bằng cổng thanh toán trong app (không VietQR, không thu tiền trong app).
Việc mua gói / kích hoạt dịch vụ (nếu có) được thực hiện ngoài ứng dụng qua nhà xe, admin hoặc tổng đài.
Nút “Gửi lên hệ thống” chỉ gửi cấu hình lời chào để quản trị xử lý, không phải nút thanh toán.

QUYỀN ỨNG DỤNG
Ứng dụng cần một số quyền hệ thống để chạy nền, Bluetooth, nút nổi và tự khởi động trên Box.
Chi tiết xem Chính sách quyền riêng tư.

Hỗ trợ: [email] — [hotline]
```

---

## C. Làm rõ “Gửi lên hệ thống” / Studio (trả lời reviewer)

**Câu hỏi thường gặp của Google:** App có bán digital content ngoài Play Billing không?

**Trả lời mẫu (EN — nên dùng khi reply review):**

```
The in-app Studio does NOT sell digital content and does NOT collect payment.
There is no QR code, price, or checkout UI in the Play build.

The “Submit to system” button only uploads greeting configuration / draft audio
metadata to our admin backend so operators can review and assign audio to the
vehicle account. Any commercial activation (license / package), if applicable,
is handled OUTSIDE the app (B2B contract, call center, or admin portal).

We previously removed in-app VietQR purchase UI specifically to comply with
Google Play Payments policy.
```

**Tiếng Việt (nội bộ / listing):**

```
Studio không bán nội dung số trong app và không thu tiền.
Không có QR, giá, hay màn thanh toán trong bản Play.

Nút “Gửi lên hệ thống” chỉ gửi cấu hình lời chào / bản nháp lên hệ thống quản trị
để admin duyệt và gán file cho xe. Mua gói / kích hoạt (nếu có) thực hiện ngoài app
(hợp đồng B2B, tổng đài, cổng admin).
```

---

## D. Data safety (Play Console) — gợi ý khai báo

> Điền đúng theo thực tế triển khai. Dưới đây là **gợi ý** dựa trên mã nguồn hiện tại.

### Dữ liệu thu thập / chia sẻ

| Loại dữ liệu (Play) | Có thu thập? | Chia sẻ? | Mục đích |
|---|---|---|---|
| Số điện thoại | Có | Với backend / nhà xe vận hành hệ thống | Account management |
| Tên | Có | Có (backend) | Account |
| Mật khẩu | Có (gửi khi đăng nhập; không lưu plaintext trên máy) | Backend | Account |
| ID thiết bị | Có | Backend (login + error log) | Fraud prevention / support |
| Thông tin xe (biển số) | Có | Backend | App functionality |
| File âm thanh / cấu hình lời chào | Có | Backend khi sync / Studio | App functionality |
| Nhật ký lỗi / diagnostic | Có (khi user gửi) | Backend | Support / diagnostics |
| Vị trí chính xác | Không (không theo dõi GPS) | — | — |
| Thông tin thanh toán tài chính trong app | Không | — | — |

### Các câu hỏi yes/no thường gặp

| Câu hỏi | Gợi ý |
|---|---|
| App có thu thập dữ liệu người dùng? | **Có** |
| Dữ liệu có được mã hóa khi truyền? | **Có** (HTTPS) |
| Người dùng có thể yêu cầu xóa dữ liệu? | **Có** (liên hệ email / đăng xuất + hỗ trợ) |
| App có chuyển dữ liệu cho bên thứ ba để quảng cáo? | **Không** (nếu đúng thực tế) |
| Có dùng dữ liệu để cá nhân hóa quảng cáo? | **Không** |

Gắn link **Privacy Policy** công khai (host file `docs/privacy-policy.html`).

---

## E. Declarations quyền nhạy cảm — nội dung mẫu

### 1) Foreground service — Media playback

```
Used to play greeting/farewell audio reliably in the background while the driver
uses navigation or while the car head unit is connected (Bluetooth / Android Auto).
A persistent notification indicates the service is active.
```

### 2) Foreground service — Special use

```
Required for:
1) Starting automotive greeting playback from BOOT_COMPLETED on Android Box
   devices (mediaPlayback type is restricted from boot on newer Android versions).
2) Floating overlay control bubble service so the driver can trigger play/stop
   while another app (e.g. maps) is in the foreground.

This is core automotive functionality, not unrelated background work.
```

### 3) Display over other apps (SYSTEM_ALERT_WINDOW)

```
A small floating bubble lets drivers play greeting or farewell audio without
leaving the navigation app. The overlay only shows playback controls for this app
and can be disabled in settings.
```

### 4) Bluetooth

```
Used to detect connection to the vehicle Bluetooth audio unit / wireless Android Auto
and to trigger greeting playback when the audio route is ready. Scanning is not used
to derive user location (BLUETOOTH_SCAN declared with neverForLocation).
```

### Video demo (nên chuẩn bị 1 clip ≤ 1–2 phút)

1. Đăng nhập  
2. Cấp quyền overlay / thông báo  
3. Đồng bộ nhạc, đặt lời chào  
4. Đưa app xuống nền → hiện nút nổi → bấm phát  
5. (Nếu có) Box / BT auto-play  

Upload vào phần Declaration nếu Console yêu cầu.

---

## F. Checklist trước khi Submit

### Hồ sơ bắt buộc

- [ ] Host Privacy Policy công khai (HTTPS) — dùng `docs/privacy-policy.html`
- [ ] Dán URL Privacy vào Play Console + Data safety
- [ ] Điền Data safety khớp mục D
- [ ] Điền Declaration FGS / Overlay / Special use (mục E)
- [ ] Icon, feature graphic, screenshot (điện thoại; tablet nếu hỗ trợ)
- [ ] Short + Full description (mục A/B) — **nhấn mạnh không thanh toán trong app**
- [ ] Category phù hợp (ví dụ Auto & Vehicles / Tools — chọn theo listing thật)
- [ ] Content rating questionnaire
- [ ] Target audience / news app / COVID… trả lời đúng

### Kỹ thuật

- [ ] Build **AAB** release đã ký (`flutter build appbundle --release`)
- [ ] `versionName` / `versionCode` tăng đúng
- [ ] Test bản **release** trên máy thật: login, sync, phát, overlay, logout
- [ ] Test Box boot (nếu phân phối cho Box)
- [ ] Không hiện VietQR / giá trong UI Studio
- [ ] Thống nhất tên hiển thị: listing vs `android:label` (hiện Manifest đang là “Chào Xe Tự Động”)

### Policy / làm rõ

- [ ] Đoạn “không bán digital trong app” có trong Full description
- [ ] Có sẵn câu trả lời reviewer (mục C) nếu bị hỏi Payments
- [ ] Email hỗ trợ hoạt động

### Nên cải thiện thêm (không chặn submit ngay nhưng nên làm)

- [ ] Bỏ / thu hẹp `badCertificateCallback` chấp nhận mọi chứng chỉ SSL
- [ ] Gỡ `WRITE_EXTERNAL_STORAGE` nếu không còn cần
- [ ] Thêm link Privacy trong app (Cài đặt → Chính sách quyền riêng tư)
- [ ] Crash reporting (tuỳ chọn)

---

## G. Thông tin cần điền tay (placeholder)

Thay trong Privacy / HTML / listing trước khi publish:

| Placeholder | Ý nghĩa |
|---|---|
| `[Điền tên công ty / cá nhân]` | Chủ sở hữu app trên Play |
| `[Điền email hỗ trợ]` / `SUPPORT_EMAIL_HERE` | Email công khai |
| `[Điền địa chỉ nếu có]` | Địa chỉ pháp lý (nếu có) |
| URL Privacy | Ví dụ `https://yourdomain.com/privacy` |
| Hotline / Zalo | Kênh hỗ trợ tài xế |

---

## H. File liên quan trong repo

| File | Mục đích |
|---|---|
| `docs/PRIVACY_POLICY.md` | Bản đầy đủ tiếng Việt (markdown) |
| `docs/privacy-policy.html` | Bản host web cho Play Console |
| `docs/HUONG_DAN_SU_DUNG.md` | Hướng dẫn dùng app + làm rõ Studio |
| `docs/PLAY_STORE_CLARIFICATIONS.md` | File này |
