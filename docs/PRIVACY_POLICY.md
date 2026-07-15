# Chính sách quyền riêng tư — Giọng Thương Gia (Chào Xe Tự Động)

**Ngày hiệu lực:** 15/07/2026  
**Ứng dụng:** Giọng Thương Gia / Chào Xe Tự Động  
**Package Android:** `com.hicar.ora.limited`  
**Đơn vị vận hành:** [Điền tên công ty / cá nhân]  
**Email liên hệ:** [Điền email hỗ trợ]  
**Website:** [Điền URL trang chủ / privacy]

---

## 1. Giới thiệu

Ứng dụng **Giọng Thương Gia** (sau đây gọi là “Ứng dụng”) hỗ trợ tài xế / nhà xe phát lời chào và lời tạm biệt tự động trên điện thoại Android, màn hình Android trên xe, Android Box hoặc Android Auto.

Chính sách này giải thích **dữ liệu nào được thu thập**, **mục đích sử dụng**, **cách lưu trữ / chia sẻ**, và **quyền của người dùng**. Bằng việc sử dụng Ứng dụng, bạn đồng ý với nội dung dưới đây.

---

## 2. Dữ liệu chúng tôi thu thập

### 2.1. Tài khoản và định danh

| Dữ liệu | Mục đích |
|---|---|
| Số điện thoại | Đăng nhập / đăng ký tài khoản tài xế |
| Họ tên | Hiển thị tài khoản, gắn với đơn / lời chào |
| Mật khẩu | Xác thực đăng nhập (được xử lý phía máy chủ; không lưu plaintext trên thiết bị) |
| Mã kích hoạt (nếu dùng) | Đăng nhập theo gói B2B / bán lẻ |
| Token đăng nhập (Bearer) | Duy trì phiên đăng nhập trên thiết bị |

### 2.2. Thông tin xe / vận hành

| Dữ liệu | Mục đích |
|---|---|
| Biển số xe | Gán xe đang vận hành, điền Studio lời chào |
| Danh sách xe được phép | Cho phép chọn xe khi tài xế có nhiều xe |
| Tên / danh xưng chủ xe (do người dùng nhập) | Tạo bản nghe thử / gửi cấu hình lời chào |

### 2.3. Thông tin thiết bị

Khi đăng nhập hoặc gửi báo cáo lỗi, Ứng dụng có thể gửi:

- Mã định danh thiết bị (Android ID / tương đương)
- Tên thiết bị, model
- Phiên bản hệ điều hành
- Phiên bản ứng dụng

**Mục đích:** chống dùng chung tài khoản trên nhiều thiết bị cùng lúc, hỗ trợ bảo mật và hỗ trợ kỹ thuật.

### 2.4. Âm thanh và cấu hình phát

- Danh sách file âm thanh được phép phát (metadata từ máy chủ)
- File âm thanh tải về **lưu cục bộ trên thiết bị** để phát offline
- Cấu hình lời chào / tạm biệt đang chọn
- Chế độ kết nối (Bluetooth điện thoại, Android Auto, màn độ, Android Box)
- Địa chỉ / tên thiết bị Bluetooth đã chọn (chỉ lưu trên thiết bị để tự nhận diện xe)
- Cài đặt độ trễ phát, tự phát khi mở app / khi kết nối

### 2.5. Nhật ký lỗi (khi người dùng gửi báo cáo)

Nếu bạn bấm gửi báo cáo lỗi, Ứng dụng có thể gửi:

- Mô tả lỗi / ghi chú của bạn
- Loại lỗi (ví dụ: audio, bluetooth, sync, khác)
- Thông tin thiết bị (như mục 2.3)
- Đoạn nhật ký kỹ thuật nội bộ (diagnostic) liên quan sự cố

### 2.6. Dữ liệu chúng tôi **không** thu thập

Ứng dụng **không** thu thập:

- Vị trí GPS liên tục để theo dõi hành trình (quyền vị trí chỉ có thể được hệ thống yêu cầu gián tiếp khi quét Bluetooth trên một số phiên bản Android; Ứng dụng **không** dùng dữ liệu quét BLE để suy ra vị trí)
- Danh bạ, SMS, nhật ký cuộc gọi
- Ảnh / camera / microphone để thu âm người dùng
- Dữ liệu thanh toán thẻ trong app (không tích hợp cổng thanh toán Play Billing / thẻ trong app)

---

## 3. Cách chúng tôi sử dụng dữ liệu

- Cung cấp và duy trì chức năng đăng nhập, đồng bộ nhạc, phát lời chào
- Gán đúng tài khoản ↔ thiết bị (1 tài khoản = 1 thiết bị tại một thời điểm theo chính sách hệ thống)
- Hỗ trợ Studio tạo / gửi cấu hình lời chào lên hệ thống quản trị
- Chẩn đoán sự cố khi người dùng chủ động gửi báo cáo lỗi
- Cải thiện độ ổn định và trải nghiệm (phân tích kỹ thuật nội bộ, không bán dữ liệu cá nhân)

---

## 4. Lưu trữ dữ liệu

| Loại | Nơi lưu |
|---|---|
| Token, cấu hình, danh sách audio metadata | Bộ nhớ cục bộ thiết bị (SharedPreferences / storage riêng của app) |
| File nhạc offline | Thư mục riêng của ứng dụng trên thiết bị |
| Tài khoản, đơn hàng, danh sách audio được gán | Máy chủ của đơn vị vận hành |
| Nhật ký chẩn đoán native | File cục bộ trên thiết bị; chỉ gửi lên máy chủ khi bạn gửi báo cáo |

Dữ liệu trên máy chủ được lưu trong thời gian cần thiết để cung cấp dịch vụ, tuân thủ pháp luật, hoặc theo yêu cầu hỗ trợ / khiếu nại.

---

## 5. Chia sẻ dữ liệu

Chúng tôi **không bán** dữ liệu cá nhân.

Dữ liệu có thể được xử lý / chia sẻ trong các trường hợp:

- **Nhà xe / quản trị viên hệ thống** liên kết với tài khoản của bạn (để gán xe, duyệt lời chào, hỗ trợ)
- **Nhà cung cấp hạ tầng** (máy chủ hosting, lưu trữ file âm thanh) chỉ để vận hành dịch vụ
- **Yêu cầu pháp lý** khi cơ quan có thẩm quyền yêu cầu hợp pháp

Ứng dụng có thể tải cấu hình địa chỉ API từ nguồn cấu hình công khai do đơn vị vận hành duy trì, nhằm cập nhật endpoint dịch vụ. Nội dung cấu hình này không phải dữ liệu cá nhân của bạn.

---

## 6. Quyền hệ thống Android và lý do

| Quyền / khả năng | Lý do |
|---|---|
| Internet | Đăng nhập, đồng bộ nhạc, gửi báo cáo lỗi |
| Bluetooth / Bluetooth Scan / Connect | Nhận diện kết nối với đầu đĩa / màn hình xe, chế độ Android Auto không dây |
| Thông báo | Duy trì dịch vụ phát nhạc nền (Foreground Service) |
| Hiển thị trên ứng dụng khác (nút nổi) | Cho phép tài xế bấm Chào / Tạm biệt khi đang dùng app khác (ví dụ điều hướng) |
| Chạy nền / Foreground Service (media / special use) | Phát lời chào ổn định, tự khởi động trên Android Box khi bật máy |
| Khởi động cùng thiết bị (Boot) | Android Box tự sẵn sàng phát lời chào khi xe / box khởi động |
| Tối ưu pin (hướng dẫn vào Cài đặt) | Giảm việc hệ thống tắt app khi chạy nền — người dùng tự bật trong Cài đặt |

---

## 7. Quyền của người dùng

Bạn có thể:

- Xem / cập nhật thông tin tài khoản theo khả năng hệ thống cung cấp
- Đăng xuất để xoá token phiên trên thiết bị
- Xóa dữ liệu ứng dụng trong Cài đặt Android (xoá cache / dữ liệu app)
- Yêu cầu hỗ trợ xóa / chỉnh sửa dữ liệu tài khoản bằng cách liên hệ email hỗ trợ ở đầu tài liệu
- Từ chối gửi báo cáo lỗi (chỉ gửi khi bạn chủ động thao tác)

---

## 8. Bảo mật

Chúng tôi áp dụng biện pháp hợp lý về kỹ thuật và tổ chức để bảo vệ dữ liệu (truyền qua HTTPS, token xác thực, giới hạn truy cập máy chủ). Tuy nhiên không có phương thức truyền hoặc lưu trữ nào tuyệt đối an toàn 100%.

Khuyến nghị: không chia sẻ mật khẩu / mã kích hoạt; đăng xuất khi không còn dùng thiết bị chung.

---

## 9. Trẻ em

Ứng dụng phục vụ mục đích vận hành xe / nhà xe, **không** hướng đến trẻ em dưới 13 tuổi (hoặc độ tuổi tương đương theo pháp luật địa phương). Chúng tôi không cố ý thu thập dữ liệu của trẻ em.

---

## 10. Thay đổi chính sách

Chúng tôi có thể cập nhật Chính sách này. Phiên bản mới sẽ được đăng tại URL chính thức và/hoặc thông báo trong Ứng dụng. Ngày hiệu lực được ghi ở đầu tài liệu.

---

## 11. Liên hệ

Mọi câu hỏi về quyền riêng tư, vui lòng liên hệ:

- Email: **[Điền email hỗ trợ]**
- Đơn vị: **[Điền tên công ty / cá nhân]**
- Địa chỉ: **[Điền địa chỉ nếu có]**
