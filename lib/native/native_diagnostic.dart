/// Interprets evidence, never infers a device type from a substring such as boot=false.
class NativeDiagnostic {
  static String idFor(String line) {
    var hash = 0x811c9dc5;
    for (final unit in line.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return 'native-${hash.toRadixString(16)}';
  }

  static String? modeIn(String line) => RegExp(
        r'\b(?:mode|connectionMode)=(phone_bluetooth|phone_android_auto|android_screen_mode|android_box_mode|ios_carplay)\b',
      ).firstMatch(line)?.group(1);

  static String message(String line) {
    final lower = line.toLowerCase();
    if (lower.contains('what=100')) {
      return 'Dịch vụ phát âm thanh của thiết bị bị gián đoạn. Ứng dụng không phát tiếp được nhạc; hãy thử lại hoặc gửi báo lỗi.';
    }
    if (lower.contains('extra=-32') || lower.contains('extra=-38')) {
      return 'Bộ phát âm thanh gặp lỗi khi đang phát. Hãy gửi báo lỗi để kiểm tra đường âm thanh và khả năng phục hồi của thiết bị.';
    }
    if (lower.contains('securityexception') ||
        lower.contains('permission denied') ||
        lower.contains('thiếu quyền')) {
      if (lower.contains('bluetooth_connect')) {
        return 'Thiếu quyền Thiết bị ở gần (BLUETOOTH_CONNECT). Hãy cấp quyền này trong Cài đặt ứng dụng để kết nối xe.';
      }
      if (lower.contains('system_alert_window')) {
        return 'Thiếu quyền Hiển thị trên ứng dụng khác (SYSTEM_ALERT_WINDOW), nên chưa hiện được bong bóng nổi.';
      }
      return 'Hệ thống từ chối quyền thực hiện thao tác. Kiểm tra quyền ứng dụng và gửi báo lỗi để xem quyền cụ thể.';
    }
    if (lower.contains('fgs_start_denied') ||
        lower.contains('foregroundservicestartnotallowed')) {
      return 'Hệ điều hành chưa cho phép ứng dụng chạy dịch vụ âm thanh ở nền. Mở ứng dụng để thử lại; kiểm tra cài đặt chạy nền/tự khởi động và gửi báo lỗi.';
    }
    if (lower.contains('path is empty') ||
        lower.contains('file does not exist') ||
        lower.contains('no valid audio') || lower.contains('no greeting audio file') ||
        lower.contains('file_invalid')) {
      return 'File nhạc chưa có hoặc không hợp lệ. Hãy đồng bộ hoặc chọn lại nhạc.';
    }
    if (line.contains('BOOT_PLAYBACK_MISSED')) {
      return 'Lượt phát tự động khi Android Box khởi động chưa hoàn tất. Gửi báo lỗi để kiểm tra.';
    }
    if (lower.contains('mediaplayer') || lower.contains('playback_failed')) {
      return 'Thiết bị chưa phát được nhạc sau khi thử phục hồi. Bạn có thể thử lại hoặc gửi báo lỗi.';
    }
    if (lower.contains('copyfile') ||
        lower.contains('hicar sync') ||
        lower.contains('hicarsync')) {
      return 'Không cập nhật được file nhạc trên thiết bị. Hãy gửi báo lỗi để kiểm tra bộ nhớ và file nguồn.';
    }
    return 'Ứng dụng gặp lỗi khi thực hiện thao tác. Gửi báo lỗi để kiểm tra chi tiết.';
  }

  static bool needsAction(String line, String currentMode, String fullLog) {
    if (!RegExp(r'\bE (?:HiCar\w*|OverlayBridge):').hasMatch(line))
      return false;
    final eventMode = modeIn(line);
    if (eventMode != null && eventMode != currentMode) return false;
    if (line.contains('BOOT_PLAYBACK_MISSED') &&
        currentMode != 'android_box_mode') return false;
    if (line.contains('state=retrying')) return false;
    final job = RegExp(r'\bjob=([^\s]+)').firstMatch(line)?.group(1);
    if (job != null &&
        fullLog.split('\n').any((entry) =>
            entry.contains('job=$job ') &&
            (entry.contains('state=completed') ||
                entry.contains('state=cancelled')))) {
      return false;
    }
    return true;
  }
}
