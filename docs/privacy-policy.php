<?php
/**
 * Chính sách quyền riêng tư — Giọng Thương Gia (Chào Xe Tự Động)
 * Upload file này lên hosting, ví dụ: https://yourdomain.com/privacy-policy.php
 *
 * CHỈNH SỬA CÁC HẰNG SỐ BÊN DƯỚI TRƯỚC KHI ĐƯA LÊN:
 */
$APP_NAME       = 'Giọng Thương Gia (Chào Xe Tự Động)';
$PACKAGE_NAME   = 'com.hicar.ora.limited';
$EFFECTIVE_DATE = '15/07/2026';
$COMPANY_NAME   = 'Điền tên công ty / cá nhân';
$SUPPORT_EMAIL  = 'hotro@example.com';
$SUPPORT_PHONE  = ''; // Ví dụ: 0900 000 000 — để trống nếu không có
$COMPANY_ADDR   = 'Điền địa chỉ (nếu có)';
$SITE_URL       = ''; // Ví dụ: https://yourdomain.com

header('Content-Type: text/html; charset=UTF-8');
header('X-Content-Type-Options: nosniff');

function e(string $s): string
{
    return htmlspecialchars($s, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}
?>
<!DOCTYPE html>
<html lang="vi">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <meta name="robots" content="index,follow" />
  <title>Chính sách quyền riêng tư — <?php echo e($APP_NAME); ?></title>
  <style>
    :root {
      --bg: #0f1419;
      --card: #1a222c;
      --text: #e8eef4;
      --muted: #9aa7b5;
      --accent: #4a90e2;
      --border: #2a3542;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      background: var(--bg);
      color: var(--text);
      line-height: 1.65;
    }
    .wrap {
      max-width: 820px;
      margin: 0 auto;
      padding: 32px 20px 64px;
    }
    h1 { font-size: 1.75rem; margin: 0 0 8px; }
    h2 {
      font-size: 1.2rem;
      margin-top: 2rem;
      padding-bottom: 6px;
      border-bottom: 1px solid var(--border);
      color: var(--accent);
    }
    h3 { font-size: 1.05rem; margin-top: 1.25rem; color: var(--text); }
    .meta { color: var(--muted); font-size: 0.95rem; margin-bottom: 1.5rem; }
    table {
      width: 100%;
      border-collapse: collapse;
      margin: 12px 0 20px;
      font-size: 0.95rem;
    }
    th, td {
      border: 1px solid var(--border);
      padding: 10px 12px;
      text-align: left;
      vertical-align: top;
    }
    th { background: var(--card); }
    ul { padding-left: 1.25rem; }
    a { color: var(--accent); }
    .note {
      background: var(--card);
      border-left: 3px solid var(--accent);
      padding: 12px 16px;
      margin: 16px 0;
      border-radius: 0 8px 8px 0;
    }
    footer {
      margin-top: 3rem;
      padding-top: 1rem;
      border-top: 1px solid var(--border);
      color: var(--muted);
      font-size: 0.9rem;
    }
  </style>
</head>
<body>
  <div class="wrap">
    <h1>Chính sách quyền riêng tư</h1>
    <p class="meta">
      Ứng dụng: <strong><?php echo e($APP_NAME); ?></strong><br />
      Package Android: <?php echo e($PACKAGE_NAME); ?><br />
      Ngày hiệu lực: <?php echo e($EFFECTIVE_DATE); ?><br />
      Đơn vị vận hành: <?php echo e($COMPANY_NAME); ?><br />
      Liên hệ:
      <a href="mailto:<?php echo e($SUPPORT_EMAIL); ?>"><?php echo e($SUPPORT_EMAIL); ?></a>
      <?php if ($SUPPORT_PHONE !== ''): ?>
        — <?php echo e($SUPPORT_PHONE); ?>
      <?php endif; ?>
    </p>

    <div class="note">
      Chính sách này giải thích dữ liệu nào được thu thập khi bạn dùng ứng dụng
      <strong><?php echo e($APP_NAME); ?></strong>, mục đích sử dụng, cách lưu trữ / chia sẻ
      và quyền của bạn. Bằng việc sử dụng ứng dụng, bạn đồng ý với nội dung dưới đây.
    </div>

    <h2>1. Giới thiệu</h2>
    <p>
      Ứng dụng hỗ trợ tài xế / nhà xe phát lời chào và lời tạm biệt tự động trên
      điện thoại Android, màn hình Android trên xe, Android Box hoặc Android Auto.
      Ứng dụng đồng bộ file âm thanh về máy để phát offline, hỗ trợ nút nổi điều khiển
      và Studio gửi cấu hình lời chào lên hệ thống quản trị.
    </p>

    <h2>2. Dữ liệu chúng tôi thu thập</h2>

    <h3>2.1. Tài khoản và định danh</h3>
    <table>
      <tr><th>Dữ liệu</th><th>Mục đích</th></tr>
      <tr><td>Số điện thoại</td><td>Đăng nhập / đăng ký tài khoản tài xế</td></tr>
      <tr><td>Họ tên</td><td>Hiển thị tài khoản, gắn với lời chào / vận hành</td></tr>
      <tr><td>Mật khẩu</td><td>Xác thực đăng nhập (xử lý phía máy chủ; không lưu plaintext trên thiết bị)</td></tr>
      <tr><td>Mã kích hoạt (nếu dùng)</td><td>Đăng nhập theo gói B2B / bán lẻ</td></tr>
      <tr><td>Token đăng nhập (Bearer)</td><td>Duy trì phiên đăng nhập trên thiết bị</td></tr>
    </table>

    <h3>2.2. Thông tin xe / vận hành</h3>
    <table>
      <tr><th>Dữ liệu</th><th>Mục đích</th></tr>
      <tr><td>Biển số xe</td><td>Gán xe đang vận hành, điền Studio lời chào</td></tr>
      <tr><td>Danh sách xe được phép</td><td>Cho phép chọn xe khi tài xế có nhiều xe</td></tr>
      <tr><td>Tên / danh xưng chủ xe (do bạn nhập)</td><td>Tạo bản nghe thử / gửi cấu hình lời chào</td></tr>
    </table>

    <h3>2.3. Thông tin thiết bị</h3>
    <p>Khi đăng nhập hoặc gửi báo cáo lỗi, ứng dụng có thể gửi:</p>
    <ul>
      <li>Mã định danh thiết bị (Android ID / tương đương)</li>
      <li>Tên thiết bị, model</li>
      <li>Phiên bản hệ điều hành</li>
      <li>Phiên bản ứng dụng</li>
    </ul>
    <p>
      <strong>Mục đích:</strong> chống dùng chung tài khoản trên nhiều thiết bị cùng lúc,
      hỗ trợ bảo mật và hỗ trợ kỹ thuật.
    </p>

    <h3>2.4. Âm thanh và cấu hình phát</h3>
    <ul>
      <li>Danh sách file âm thanh được phép phát (metadata từ máy chủ)</li>
      <li>File âm thanh tải về lưu cục bộ trên thiết bị để phát offline</li>
      <li>Cấu hình lời chào / tạm biệt đang chọn</li>
      <li>Chế độ kết nối (Bluetooth, Android Auto, màn độ, Android Box)</li>
      <li>Địa chỉ / tên thiết bị Bluetooth đã chọn (lưu trên thiết bị)</li>
      <li>Cài đặt độ trễ phát, tự phát khi mở app / khi kết nối</li>
    </ul>

    <h3>2.5. Nhật ký lỗi (khi bạn gửi báo cáo)</h3>
    <p>Nếu bạn bấm gửi báo cáo lỗi, ứng dụng có thể gửi:</p>
    <ul>
      <li>Mô tả lỗi / ghi chú của bạn</li>
      <li>Loại lỗi (audio, bluetooth, sync, khác…)</li>
      <li>Thông tin thiết bị (như mục 2.3)</li>
      <li>Đoạn nhật ký kỹ thuật nội bộ liên quan sự cố</li>
    </ul>

    <h3>2.6. Dữ liệu chúng tôi không thu thập</h3>
    <ul>
      <li>Vị trí GPS liên tục để theo dõi hành trình</li>
      <li>Danh bạ, SMS, nhật ký cuộc gọi</li>
      <li>Ảnh / camera / microphone để thu âm người dùng</li>
      <li>Dữ liệu thanh toán thẻ trong app (không tích hợp cổng thanh toán trong app)</li>
    </ul>
    <p class="meta">
      Trên một số phiên bản Android, hệ thống có thể yêu cầu quyền vị trí khi quét Bluetooth;
      ứng dụng không dùng kết quả quét BLE để suy ra vị trí người dùng.
    </p>

    <h2>3. Cách chúng tôi sử dụng dữ liệu</h2>
    <ul>
      <li>Cung cấp đăng nhập, đồng bộ nhạc, phát lời chào</li>
      <li>Gán đúng tài khoản ↔ thiết bị theo quy tắc hệ thống</li>
      <li>Hỗ trợ Studio tạo / gửi cấu hình lời chào lên hệ thống quản trị</li>
      <li>Chẩn đoán sự cố khi bạn chủ động gửi báo cáo lỗi</li>
      <li>Cải thiện độ ổn định (không bán dữ liệu cá nhân)</li>
    </ul>

    <h2>4. Lưu trữ dữ liệu</h2>
    <table>
      <tr><th>Loại</th><th>Nơi lưu</th></tr>
      <tr><td>Token, cấu hình, metadata audio</td><td>Bộ nhớ cục bộ thiết bị</td></tr>
      <tr><td>File nhạc offline</td><td>Thư mục riêng của ứng dụng trên thiết bị</td></tr>
      <tr><td>Tài khoản, danh sách audio được gán</td><td>Máy chủ của đơn vị vận hành</td></tr>
      <tr><td>Nhật ký chẩn đoán</td><td>Cục bộ trên thiết bị; chỉ gửi khi bạn báo cáo lỗi</td></tr>
    </table>
    <p>
      Dữ liệu trên máy chủ được lưu trong thời gian cần thiết để cung cấp dịch vụ,
      tuân thủ pháp luật, hoặc phục vụ hỗ trợ / khiếu nại.
    </p>

    <h2>5. Chia sẻ dữ liệu</h2>
    <p>Chúng tôi <strong>không bán</strong> dữ liệu cá nhân.</p>
    <p>Dữ liệu có thể được xử lý / chia sẻ khi:</p>
    <ul>
      <li>Nhà xe / quản trị viên hệ thống liên kết với tài khoản của bạn</li>
      <li>Nhà cung cấp hạ tầng (hosting, lưu trữ file) chỉ để vận hành dịch vụ</li>
      <li>Cơ quan có thẩm quyền yêu cầu hợp pháp</li>
    </ul>

    <h2>6. Quyền hệ thống Android và lý do</h2>
    <table>
      <tr><th>Quyền / khả năng</th><th>Lý do</th></tr>
      <tr><td>Internet</td><td>Đăng nhập, đồng bộ nhạc, gửi báo cáo lỗi</td></tr>
      <tr><td>Bluetooth</td><td>Nhận diện kết nối đầu đĩa / màn xe / Android Auto</td></tr>
      <tr><td>Thông báo</td><td>Duy trì dịch vụ phát nhạc nền</td></tr>
      <tr><td>Hiển thị trên ứng dụng khác</td><td>Nút nổi Chào / Tạm biệt khi đang điều hướng</td></tr>
      <tr><td>Foreground Service / Boot</td><td>Phát ổn định; Box tự sẵn sàng khi bật máy</td></tr>
      <tr><td>Tối ưu pin (hướng dẫn Cài đặt)</td><td>Người dùng tự chọn để app không bị hệ thống tắt nền</td></tr>
    </table>

    <h2>7. Thanh toán trong ứng dụng</h2>
    <p>
      Ứng dụng <strong>không bán nội dung số</strong> và <strong>không thu tiền</strong> trong app
      (không hiển thị VietQR / giá / cổng thanh toán). Nút gửi cấu hình Studio chỉ gửi thông tin
      lên hệ thống quản trị. Việc mua gói / kích hoạt dịch vụ (nếu có) được thực hiện
      <strong>ngoài ứng dụng</strong> (hợp đồng, tổng đài, admin).
    </p>

    <h2>8. Quyền của người dùng</h2>
    <ul>
      <li>Đăng xuất để xoá token phiên trên thiết bị</li>
      <li>Xóa dữ liệu ứng dụng trong Cài đặt Android</li>
      <li>Yêu cầu hỗ trợ chỉnh sửa / xóa dữ liệu tài khoản qua email hỗ trợ</li>
      <li>Từ chối gửi báo cáo lỗi (chỉ gửi khi bạn chủ động thao tác)</li>
    </ul>

    <h2>9. Bảo mật</h2>
    <p>
      Chúng tôi áp dụng biện pháp hợp lý để bảo vệ dữ liệu (HTTPS, token xác thực, giới hạn truy cập máy chủ).
      Không có phương thức truyền hoặc lưu trữ nào tuyệt đối an toàn 100%.
      Không chia sẻ mật khẩu / mã kích hoạt; đăng xuất khi dùng thiết bị chung.
    </p>

    <h2>10. Trẻ em</h2>
    <p>
      Ứng dụng phục vụ vận hành xe / nhà xe, không hướng đến trẻ em dưới 13 tuổi
      (hoặc độ tuổi tương đương theo pháp luật địa phương). Chúng tôi không cố ý thu thập dữ liệu của trẻ em.
    </p>

    <h2>11. Thay đổi chính sách</h2>
    <p>
      Chúng tôi có thể cập nhật Chính sách này. Phiên bản mới sẽ được đăng tại URL này
      và/hoặc thông báo trong ứng dụng. Ngày hiệu lực được ghi ở đầu trang.
    </p>

    <h2>12. Liên hệ</h2>
    <p>
      Email:
      <a href="mailto:<?php echo e($SUPPORT_EMAIL); ?>"><?php echo e($SUPPORT_EMAIL); ?></a><br />
      Đơn vị: <?php echo e($COMPANY_NAME); ?><br />
      Địa chỉ: <?php echo e($COMPANY_ADDR); ?>
      <?php if ($SUPPORT_PHONE !== ''): ?>
        <br />Điện thoại: <?php echo e($SUPPORT_PHONE); ?>
      <?php endif; ?>
      <?php if ($SITE_URL !== ''): ?>
        <br />Website: <a href="<?php echo e($SITE_URL); ?>"><?php echo e($SITE_URL); ?></a>
      <?php endif; ?>
    </p>

    <footer>
      &copy; <?php echo date('Y'); ?> <?php echo e($COMPANY_NAME); ?>.
      Mọi quyền được bảo lưu. — <?php echo e($APP_NAME); ?>
    </footer>
  </div>
</body>
</html>
