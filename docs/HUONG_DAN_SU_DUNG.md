# Hướng dẫn sử dụng ứng dụng — Giọng Thương Gia

Tài liệu này mô tả **ứng dụng dùng để làm gì** và **cách dùng từng phần**, đồng thời làm rõ các điểm quan trọng khi lên Google Play / hỗ trợ khách hàng.

---

## 1. Ứng dụng là gì?

**Giọng Thương Gia (Chào Xe Tự Động)** là ứng dụng hỗ trợ tài xế / nhà xe:

1. Đồng bộ file lời chào / tạm biệt từ hệ thống về máy (phát **offline**, không stream lúc chạy xe).
2. Tự phát lời chào khi có sự kiện phù hợp (kết nối Bluetooth / Android Auto / mở app / khởi động Android Box — tùy chế độ).
3. Cho phép bấm phát thủ công (nút trong app hoặc **nút nổi** khi đang dùng app khác).
4. Studio tạo bản nghe thử lời chào AI và **gửi cấu hình lên hệ thống quản trị** (không phải mua hàng trong app qua VietQR).

---

## 2. Luồng sử dụng cơ bản

```
Chọn chế độ kết nối → Cấp quyền cần thiết → Đăng nhập → (Chọn xe nếu có nhiều xe)
→ Đồng bộ nhạc → Đặt lời chào / tạm biệt → Dùng xe / Box theo chế độ
```

### Bước 1 — Chọn chế độ kết nối

| Chế độ | Dùng khi |
|---|---|
| **Điện thoại + Bluetooth** | Điện thoại kết nối Bluetooth với đầu đĩa / màn xe |
| **Điện thoại + Android Auto** | Dùng Android Auto (có dây / không dây) |
| **Màn Android trên xe** | App chạy trên màn Android gắn trên xe |
| **Android Box** | App chạy trên Android Box; tự phát khi Box khởi động |

Chế độ quyết định quyền cần xin và logic tự phát. Đổi chế độ trong Cài đặt nếu cần.

### Bước 2 — Cấp quyền

Tùy chế độ, app sẽ hướng dẫn:

- Thông báo (Foreground Service)
- Bluetooth (kết nối xe / AA)
- Hiển thị trên ứng dụng khác (nút nổi)
- Tối ưu pin: **mở Cài đặt hệ thống** để người dùng tự chọn “Không hạn chế” (không dùng hộp thoại xin quyền bị Play hạn chế)

### Bước 3 — Đăng nhập

Hai cách:

- **Mã kích hoạt** (B2B / bán lẻ)
- **Số điện thoại + mật khẩu** (tài xế)

Hệ thống áp dụng: **1 tài khoản ≈ 1 thiết bị tại một thời điểm**. Đăng nhập máy mới có thể thu hồi phiên máy cũ.

### Bước 4 — Chọn xe (nếu có)

- Chỉ **1 xe** → app có thể tự chọn và vào trang chủ.
- **Từ 2 xe trở lên** → tài xế chọn xe đang lái hôm nay.

### Bước 5 — Đồng bộ nhạc

Trên trang chủ, đồng bộ danh sách audio từ máy chủ:

- Chỉ tải file mới / file đổi hash.
- **File nhạc cũ đã tải vẫn được giữ** nếu vẫn còn trên máy (kể cả khi API chỉ trả về danh sách mới).

### Bước 6 — Đặt lời chào / tạm biệt

- Chọn file làm **lời chào** và **lời tạm biệt**.
- Có bản tạm biệt mặc định trong app nếu chưa chọn file riêng.
- Cấu hình được đồng bộ xuống native để Box / dịch vụ nền phát đúng file.

### Bước 7 — Phát nhạc

| Cách | Mô tả |
|---|---|
| Tự động | Theo chế độ: BT sẵn sàng / AA projection / mở app / boot Box |
| Thủ công trong app | Nút phát Chào / Tạm biệt |
| Nút nổi | Khi app xuống nền (nếu đã bật bubble + cấp quyền overlay) |

---

## 3. Studio lời chào AI

### Mục đích

Cho phép người dùng **thiết kế / nghe thử** lời chào (mẫu, giọng AI, nhạc nền, âm hiệu, mixer), rồi **gửi cấu hình lên hệ thống** để quản trị xử lý / gán file cho xe.

### Các bước trong Studio

1. Chọn mẫu lời chào  
2. Điền danh xưng, biển số, dòng xe  
3. Chọn giọng / nhạc nền / âm hiệu, chỉnh mixer  
4. Bấm **Tạo bản nghe thử AI** → nghe lại  
5. Bấm **Gửi lên hệ thống** (khi đã có bản nghe thử)

### Làm rõ: “Gửi lên hệ thống” **không phải** nút mua trong app

| Có | Không |
|---|---|
| Gửi cấu hình + bản nháp lên máy chủ quản trị | Không hiện mã VietQR / số tiền trong app |
| Dùng API tạo đơn kỹ thuật + recreate để cập nhật cấu hình | Không thu tiền qua Google Play Billing |
| Toast thành công / thất bại | Không bán nội dung số bằng cổng thanh toán ngoài trong UI |

**Thanh toán / mua gói (nếu có)** được xử lý **ngoài ứng dụng** (admin, tổng đài, hợp đồng nhà xe). App chỉ là công cụ cấu hình và phát nhạc.

> Đây là điểm **bắt buộc làm rõ** trên mô tả Play Store và khi trả lời reviewer.

---

## 4. Báo cáo lỗi

Trong Cài đặt / khu vực báo lỗi:

- App có thể hiển thị thẻ lỗi (mạng, sync, phát nhạc, native boot…).
- Người dùng gửi kèm mô tả + log kỹ thuật lên máy chủ hỗ trợ.
- Chỉ gửi khi người dùng **chủ động** bấm gửi.

---

## 5. Đăng xuất

- Đăng xuất xóa phiên đăng nhập trên thiết bị.
- Tùy loại đăng xuất, danh sách nhạc local có thể được giữ hoặc xóa theo logic app (phiên hết hạn thường giữ nhạc local; đăng xuất đầy đủ có thể xóa metadata theo thiết kế hiện tại).

---

## 6. Lưu ý vận hành thực tế

1. **Luôn phát offline** — cần đồng bộ trước khi vào vùng sóng yếu.  
2. **Box** — cần đã đăng nhập + đã có file lời chào trước khi dựa vào tự phát lúc boot.  
3. **Pin** — nên đặt app “Không hạn chế” trên điện thoại để BT/AA ổn định.  
4. **Nút nổi** — cần quyền “Hiển thị trên ứng dụng khác”.  
5. **Đổi chế độ** — sau khi đổi, kiểm tra lại quyền và thử phát thủ công một lần.

---

## 7. Hỗ trợ

- Email: **[Điền email hỗ trợ]**  
- Kênh Zalo / hotline: **[Điền nếu có]**  

Khi gửi hỗ trợ, nên kèm: model máy / Box, chế độ kết nối, phiên bản app, mô tả lỗi, và (nếu có) đã gửi báo cáo lỗi trong app.
