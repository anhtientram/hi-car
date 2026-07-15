<?php
/**
 * Hướng dẫn sử dụng — Giọng Thương Gia
 * Upload: https://yourdomain.com/huong-dan.php
 */
$APP_NAME       = 'Giọng Thương Gia (Chào Xe Tự Động)';
$SUPPORT_EMAIL  = 'hotro@example.com';
$SUPPORT_PHONE  = '';
$COMPANY_NAME   = 'Điền tên công ty / cá nhân';

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
  <title>Hướng dẫn sử dụng — <?php echo e($APP_NAME); ?></title>
  <style>
    :root {
      --bg: #0f1419; --card: #1a222c; --text: #e8eef4; --muted: #9aa7b5;
      --accent: #4a90e2; --border: #2a3542; --ok: #3dd68c;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: system-ui, -apple-system, "Segoe UI", Roboto, Arial, sans-serif;
      background: var(--bg); color: var(--text); line-height: 1.65;
    }
    .wrap { max-width: 820px; margin: 0 auto; padding: 32px 20px 64px; }
    h1 { font-size: 1.75rem; margin: 0 0 8px; }
    h2 {
      font-size: 1.2rem; margin-top: 2rem; padding-bottom: 6px;
      border-bottom: 1px solid var(--border); color: var(--accent);
    }
    .meta { color: var(--muted); margin-bottom: 1.25rem; }
    table { width: 100%; border-collapse: collapse; margin: 12px 0 20px; font-size: 0.95rem; }
    th, td { border: 1px solid var(--border); padding: 10px 12px; text-align: left; vertical-align: top; }
    th { background: var(--card); }
    ul, ol { padding-left: 1.25rem; }
    a { color: var(--accent); }
    .note {
      background: var(--card); border-left: 3px solid var(--ok);
      padding: 12px 16px; margin: 16px 0; border-radius: 0 8px 8px 0;
    }
    code {
      background: var(--card); padding: 2px 6px; border-radius: 4px; font-size: 0.9em;
    }
  </style>
</head>
<body>
  <div class="wrap">
    <h1>Hướng dẫn sử dụng</h1>
    <p class="meta">
      Ứng dụng: <strong><?php echo e($APP_NAME); ?></strong><br />
      Hỗ trợ:
      <a href="mailto:<?php echo e($SUPPORT_EMAIL); ?>"><?php echo e($SUPPORT_EMAIL); ?></a>
      <?php if ($SUPPORT_PHONE !== ''): ?> — <?php echo e($SUPPORT_PHONE); ?><?php endif; ?>
    </p>

    <h2>1. Ứng dụng dùng để làm gì?</h2>
    <ol>
      <li>Đồng bộ lời chào / tạm biệt về máy và phát <strong>offline</strong></li>
      <li>Tự phát khi Bluetooth / Android Auto / mở app / khởi động Box (tùy chế độ)</li>
      <li>Phát thủ công trong app hoặc bằng <strong>nút nổi</strong></li>
      <li>Studio nghe thử lời chào AI và <strong>gửi cấu hình lên hệ thống quản trị</strong></li>
    </ol>

    <div class="note">
      <strong>Quan trọng:</strong> Ứng dụng <em>không thu tiền trong app</em>.
      Nút “Gửi lên hệ thống” không phải nút mua hàng / không hiện VietQR.
      Mua gói (nếu có) thực hiện ngoài app qua admin / tổng đài / hợp đồng.
    </div>

    <h2>2. Các bước sử dụng</h2>
    <ol>
      <li><strong>Chọn chế độ kết nối:</strong> Bluetooth điện thoại / Android Auto / Màn Android / Android Box</li>
      <li><strong>Cấp quyền:</strong> thông báo, Bluetooth, nút nổi, tối ưu pin (vào Cài đặt hệ thống)</li>
      <li><strong>Đăng nhập:</strong> mã kích hoạt hoặc SĐT + mật khẩu</li>
      <li><strong>Chọn xe</strong> (nếu tài khoản có nhiều xe)</li>
      <li><strong>Đồng bộ nhạc</strong> trên trang chủ</li>
      <li><strong>Đặt lời chào / tạm biệt</strong></li>
      <li>Dùng xe theo chế độ đã chọn (tự phát hoặc bấm nút)</li>
    </ol>

    <h2>3. Bảng chế độ</h2>
    <table>
      <tr><th>Chế độ</th><th>Khi nào dùng</th></tr>
      <tr><td>Điện thoại + Bluetooth</td><td>Điện thoại nối Bluetooth với đầu đĩa / màn xe</td></tr>
      <tr><td>Điện thoại + Android Auto</td><td>Dùng Android Auto có dây / không dây</td></tr>
      <tr><td>Màn Android trên xe</td><td>App chạy trên màn Android gắn xe</td></tr>
      <tr><td>Android Box</td><td>App trên Box; tự phát khi Box khởi động</td></tr>
    </table>

    <h2>4. Studio lời chào AI</h2>
    <ol>
      <li>Chọn mẫu → điền danh xưng, biển số, dòng xe</li>
      <li>Chọn giọng / nhạc nền / âm hiệu, chỉnh mixer</li>
      <li>Bấm <code>Tạo bản nghe thử AI</code> → nghe lại</li>
      <li>Bấm <code>Gửi lên hệ thống</code> để admin xử lý / gán file</li>
    </ol>

    <h2>5. Lưu ý</h2>
    <ul>
      <li>Luôn đồng bộ nhạc trước khi vào vùng sóng yếu</li>
      <li>Box cần đã đăng nhập và có file lời chào trước khi dựa vào tự phát lúc boot</li>
      <li>Nên đặt app “Không hạn chế” trong tối ưu pin trên điện thoại</li>
      <li>Nút nổi cần quyền “Hiển thị trên ứng dụng khác”</li>
    </ul>

    <h2>6. Liên hệ hỗ trợ</h2>
    <p>
      Email: <a href="mailto:<?php echo e($SUPPORT_EMAIL); ?>"><?php echo e($SUPPORT_EMAIL); ?></a><br />
      Đơn vị: <?php echo e($COMPANY_NAME); ?>
    </p>
  </div>
</body>
</html>
