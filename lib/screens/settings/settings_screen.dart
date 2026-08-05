import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_colors.dart';
import '../../core/constants.dart';
import '../../core/utils/ui_utils.dart';
import '../../providers/auth_provider.dart';
import '../../providers/audio_provider.dart';
import '../../providers/overlay_provider.dart';
import '../../providers/settings_provider.dart';
import '../../data/services/api_client.dart';
import '../../core/logger.dart';
import '../../native/service_channel.dart';
import 'package:intl/intl.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = info.version;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Cấu Hình Hệ Thống',
          style: TextStyle(fontSize: 16.sp),
        ),
      ),
      body: SafeArea(
        child: OrientationBuilder(
          builder: (context, orientation) {
            final isLandscape = orientation == Orientation.landscape;

            if (isLandscape) {
              return SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.w),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Cột trái
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionTitle('CHỨC NĂNG HỆ THỐNG'),
                            _SettingsTile(
                              icon: Icons.bolt_rounded,
                              iconColor: AppColors.primary,
                              title: 'Tạo Giọng Nói AI',
                              subtitle: 'Soạn lời chào cá nhân hóa cho xe',
                              onTap: () => context.push('/gen-audio'),
                            ),
                            _buildSectionTitle('CHẾ ĐỘ KẾT NỐI XE'),
                            _buildConnectionModeCard(context, settings),
                            _buildSectionTitle('CẤU HÌNH TỰ ĐỘNG PHÁT'),
                            _SettingsSwitchTile(
                              icon: Icons.power_rounded,
                              iconColor: AppColors.success,
                              title: 'Tự động phát lời chào',
                              subtitle: 'Phát âm thanh tự động',
                              value: settings.autoPlayEnabled,
                              onChanged: (val) => settings.setAutoPlay(val),
                            ),
                          ],
                        ),
                      ),
                      // Cột phải
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionTitle('HỖ TRỢ & TÀI KHOẢN'),
                            _SettingsTile(
                              icon: Icons.bug_report_rounded,
                              iconColor: AppColors.warning,
                              title: 'Báo cáo lỗi (Gửi Bug)',
                              subtitle: 'Gửi logs lỗi hệ thống',
                              onTap: () => _showBugReportDialog(context),
                            ),
                            _SettingsTile(
                              icon: Icons.logout_rounded,
                              iconColor: AppColors.textHint,
                              title: 'Đăng xuất tài khoản',
                              subtitle: 'Thoát hệ thống',
                              onTap: () => _showLogoutConfirm(context, auth),
                            ),
                            _buildSectionTitle('CÀI ĐẶT NÂNG CAO'),
                            _SettingsTile(
                              icon: Icons.security_rounded,
                              iconColor: AppColors.info,
                              title: 'Quyền Hệ Thống',
                              subtitle: 'Cấp lại quyền ứng dụng',
                              onTap: () => context
                                  .push('/permission-config?fromSettings=true'),
                            ),
                            _SettingsSwitchTile(
                              icon: Icons.bug_report_rounded,
                              iconColor: Colors.amber,
                              title: 'Chế độ Demo (Beta)',
                              subtitle: 'Thử nghiệm giọng mặc định',
                              value: settings.isBetaMode,
                              onChanged: (v) {
                                settings.setBetaMode(v);
                                context.read<AudioProvider>().setBetaMode(v);
                              },
                            ),
                            SizedBox(height: 32.h),
                            Center(
                              child: Text(
                                'Giọng Thương Gia v$_appVersion',
                                style: TextStyle(
                                  color: AppColors.textHint,
                                  fontSize: 9.sp,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            // Dạng dọc mặc định
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 16.h),
                  _buildSectionTitle('CHỨC NĂNG HỆ THỐNG'),
                  _SettingsTile(
                    icon: Icons.bolt_rounded,
                    iconColor: AppColors.primary,
                    title: 'Tạo Giọng Nói AI',
                    subtitle: 'Soạn lời chào cá nhân hóa cho xe',
                    onTap: () => context.push('/gen-audio'),
                  ),
                  _buildSectionTitle('CHẾ ĐỘ KẾT NỐI XE'),
                  _buildConnectionModeCard(context, settings),
                  _buildSectionTitle('CẤU HÌNH TỰ ĐỘNG PHÁT'),
                  _SettingsSwitchTile(
                    icon: Icons.power_rounded,
                    iconColor: AppColors.success,
                    title: 'Tự động phát lời chào',
                    subtitle:
                        'Kích hoạt phát âm thanh tự động theo chế độ kết nối',
                    value: settings.autoPlayEnabled,
                    onChanged: (val) => settings.setAutoPlay(val),
                  ),
                  _buildSectionTitle('HỖ TRỢ & TÀI KHOẢN'),
                  _SettingsTile(
                    icon: Icons.bug_report_rounded,
                    iconColor: AppColors.warning,
                    title: 'Báo cáo lỗi (Gửi Bug)',
                    subtitle: 'Gửi logs và thông tin lỗi hệ thống xe',
                    onTap: () => _showBugReportDialog(context),
                  ),
                  _SettingsTile(
                    icon: Icons.logout_rounded,
                    iconColor: AppColors.textHint,
                    title: 'Đăng xuất tài khoản',
                    subtitle: 'Thoát hệ thống trên thiết bị này',
                    onTap: () => _showLogoutConfirm(context, auth),
                  ),
                  _buildSectionTitle('CÀI ĐẶT NÂNG CAO'),
                  _SettingsTile(
                    icon: Icons.security_rounded,
                    iconColor: AppColors.info,
                    title: 'Cấu Hình Quyền Hệ Thống',
                    subtitle: 'Kiểm tra và cấp lại các quyền ứng dụng',
                    onTap: () =>
                        context.push('/permission-config?fromSettings=true'),
                  ),
                  _SettingsSwitchTile(
                    icon: Icons.bug_report_rounded,
                    iconColor: Colors.amber,
                    title: 'Chế độ Demo (Beta)',
                    subtitle: 'Sử dụng thử nghiệm giọng mặc định',
                    value: settings.isBetaMode,
                    onChanged: (v) {
                      settings.setBetaMode(v);
                      context.read<AudioProvider>().setBetaMode(v);
                    },
                  ),
                  SizedBox(height: 20.h),
                  Center(
                    child: Text(
                      'Giọng Thương Gia v$_appVersion (Limited Edition)',
                      style: TextStyle(
                        color: AppColors.textHint,
                        fontSize: 11.sp,
                      ),
                    ),
                  ),
                  SizedBox(height: 20.h),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: EdgeInsets.only(left: 16.w, top: 18.h, bottom: 6.h),
      child: Text(
        title,
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 10.sp,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildConnectionModeCard(
      BuildContext context, SettingsProvider settings) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Container(
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: AppColors.primary.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8.w),
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _connectionModeIcon(settings.connectionMode),
                color: Colors.white,
                size: 18.sp,
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Chế độ hiện tại',
                    style: TextStyle(color: AppColors.textHint, fontSize: 9.sp),
                  ),
                  Text(
                    _connectionModeLabel(settings.connectionMode),
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            ActionChip(
              label: const Text('ĐỔI'),
              onPressed: () =>
                  context.push('/connection-mode?fromSettings=true'),
              backgroundColor: AppColors.primary,
              side: BorderSide.none,
              labelStyle: TextStyle(
                color: Colors.white,
                fontSize: 9.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _connectionModeIcon(String mode) {
    switch (mode) {
      case 'phone_bluetooth':
        return Icons.bluetooth_rounded;
      case 'phone_android_auto':
        return Icons.directions_car_filled_rounded;
      case AppConstants.iosCarplayMode:
        return Icons.phone_iphone_rounded;
      case 'android_box_mode':
        return Icons.developer_board_rounded;
      case 'android_screen_mode':
        return Icons.tablet_android_rounded;
      default:
        return Icons.directions_car_rounded;
    }
  }

  String _connectionModeLabel(String mode) {
    switch (mode) {
      case 'phone_bluetooth':
        return 'Điện thoại + Bluetooth';
      case 'phone_android_auto':
        return 'Android Auto';
      case AppConstants.iosCarplayMode:
        return 'iPhone + CarPlay';
      case 'android_box_mode':
        return 'Android Box';
      case 'android_screen_mode':
        return 'Màn hình Android';
      default:
        return mode;
    }
  }

  Future<void> _showBugReportDialog(BuildContext context) async {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    await ServiceChannel.instance.importNativeDiagnostics();
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: AppLogger.instance,
        builder: (context, _) {
          final logs = AppLogger.instance.errorLogs;

          return AlertDialog(
            backgroundColor: AppColors.cardElevated,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.r)),
            insetPadding: EdgeInsets.symmetric(
                horizontal: isLandscape ? 80.w : 20.w, vertical: 16.h),
            contentPadding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
            titlePadding: EdgeInsets.fromLTRB(16.w, 16.h, 8.w, 0),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    'Báo cáo lỗi hệ thống',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14.sp,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                if (logs.isNotEmpty)
                  TextButton(
                    onPressed: () => AppLogger.instance.clear(),
                    child: Text('Xóa hết',
                        style:
                            TextStyle(color: AppColors.error, fontSize: 10.sp)),
                  ),
              ],
            ),
            content: SizedBox(
              width: isLandscape ? 0.55.sw : double.maxFinite,
              child: logs.isEmpty
                  ? FutureBuilder<String>(
                      future: ServiceChannel.instance.getDiagnosticLogFull(),
                      builder: (context, fullSnap) {
                        final fullLog = fullSnap.data?.trim() ?? '';
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_outline_rounded,
                                color: AppColors.success, size: 48.sp),
                            SizedBox(height: 16.h),
                            Text(
                              'Chưa ghi nhận lỗi nào.\nLỗi từ API/native sẽ hiện ở đây.',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13.sp),
                              textAlign: TextAlign.center,
                            ),
                            if (fullLog.isNotEmpty) ...[
                              SizedBox(height: 16.h),
                              OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _showSendBugSheet(
                                    context,
                                    AppLog(
                                      id: 'native-full-log',
                                      timestamp: DateTime.now(),
                                      message:
                                          '[Log kỹ thuật native] Boot/service — gửi log đầy đủ từ thiết bị.',
                                      type: 'native_error',
                                    ),
                                  );
                                },
                                icon: Icon(Icons.bug_report_outlined,
                                    size: 16.sp),
                                label: Text('Gửi log kỹ thuật',
                                    style: TextStyle(fontSize: 12.sp)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                  side: BorderSide(color: AppColors.primary),
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    )
                  : ConstrainedBox(
                      constraints: BoxConstraints(
                          maxHeight: isLandscape ? 320.h : 360.h),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: logs.length,
                        separatorBuilder: (_, __) =>
                            Divider(color: AppColors.border, height: 12.h),
                        itemBuilder: (context, index) {
                          final log = logs[index];
                          final timeStr =
                              DateFormat('HH:mm:ss').format(log.timestamp);

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 6.w, vertical: 2.h),
                                    decoration: BoxDecoration(
                                      color: _getLogColor(log.type)
                                          .withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4.r),
                                    ),
                                    child: Text(
                                      log.type?.toUpperCase() ?? 'ERROR',
                                      style: TextStyle(
                                        color: _getLogColor(log.type),
                                        fontSize: 9.sp,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 8.w),
                                  Text(
                                    timeStr,
                                    style: TextStyle(
                                        color: AppColors.textHint,
                                        fontSize: 10.sp),
                                  ),
                                ],
                              ),
                              SizedBox(height: 6.h),
                              Text(
                                log.message,
                                style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 12.sp),
                              ),
                              SizedBox(height: 8.h),
                              Align(
                                alignment: Alignment.centerRight,
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _showSendBugSheet(context, log);
                                  },
                                  icon: Icon(Icons.send_rounded, size: 14.sp),
                                  label: Text('Gửi báo cáo',
                                      style: TextStyle(fontSize: 11.sp)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.primary,
                                    side: BorderSide(color: AppColors.primary),
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 12.w, vertical: 6.h),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Đóng',
                    style: TextStyle(color: AppColors.textHint)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSendBugSheet(BuildContext context, AppLog log) {
    final noteController = TextEditingController();
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
      ),
      builder: (sheetContext) {
        return FutureBuilder<String>(
          future: ServiceChannel.instance.getDiagnosticLogErrors(),
          builder: (context, snapshot) {
            final adbLog = snapshot.data ?? '';
            final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;

            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 40.w,
                        height: 4.h,
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(2.r),
                        ),
                      ),
                    ),
                    SizedBox(height: 12.h),
                    Text(
                      'Gửi báo cáo lỗi',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Container(
                      padding: EdgeInsets.all(10.w),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(8.r),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        log.message,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.sp,
                        ),
                      ),
                    ),
                    SizedBox(height: 12.h),
                    TextField(
                      controller: noteController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Mô tả thêm (tuỳ chọn)',
                        hintText:
                            'Ví dụ: Tắt xe qua đêm, sáng không tự phát...',
                        labelStyle: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12.sp),
                        hintStyle: TextStyle(
                            color: AppColors.textHint, fontSize: 11.sp),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10.r),
                        ),
                        filled: true,
                        fillColor: AppColors.background,
                      ),
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 13.sp),
                    ),
                    if (adbLog.isNotEmpty) ...[
                      SizedBox(height: 12.h),
                      Text(
                        'Log kỹ thuật (adb)',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 6.h),
                      Container(
                        constraints: BoxConstraints(
                          maxHeight: isLandscape ? 120.h : 160.h,
                        ),
                        padding: EdgeInsets.all(8.w),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            adbLog,
                            style: TextStyle(
                              color: const Color(0xFFB5CEA8),
                              fontSize: 9.sp,
                              fontFamily: 'monospace',
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
                    ],
                    SizedBox(height: 16.h),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            child: const Text('Huỷ',
                                style: TextStyle(color: AppColors.textHint)),
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              await _sendLog(
                                sheetContext,
                                log,
                                userNote: noteController.text,
                                diagnosticLog: adbLog,
                              );
                            },
                            icon: Icon(Icons.send_rounded, size: 16.sp),
                            label:
                                Text('Gửi', style: TextStyle(fontSize: 13.sp)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 12.h),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10.r),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Color _getLogColor(String? type) {
    switch (type) {
      case 'native_error':
      case 'network_error':
      case 'native_playback_error':
        return AppColors.error;
      case 'sync_error':
        return AppColors.warning;
      case 'playback_error':
        return Colors.orange;
      default:
        return AppColors.info;
    }
  }

  Future<void> _sendLog(
    BuildContext context,
    AppLog log, {
    String? userNote,
    String? diagnosticLog,
  }) async {
    EasyLoading.show(status: 'Đang gửi...');
    try {
      await AppLogger.instance.sendReport(
        log,
        userNote: userNote,
        diagnosticLog: diagnosticLog,
      );
      EasyLoading.dismiss();
      if (context.mounted) {
        Navigator.pop(context);
        UiUtils.showSuccess(context, 'Đã gửi báo cáo lỗi thành công!');
      }
    } catch (e) {
      EasyLoading.dismiss();
      if (context.mounted) {
        UiUtils.showError(context, 'Lỗi khi gửi: ${ApiClient.formatError(e)}');
      }
    }
  }

  void _showLogoutConfirm(BuildContext context, AuthProvider auth) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.cardElevated,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Text('Đăng xuất?',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15.sp,
                fontWeight: FontWeight.bold)),
        content: Text('Bạn có chắc chắn muốn đăng xuất khỏi ứng dụng không?',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13.sp)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Không',
                style: TextStyle(color: AppColors.textHint)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);

              // 🟢 Lấy sẵn các tham chiếu TRƯỚC khi await để không phụ thuộc
              //    context sau này (tránh logout "không ăn" do context bị gỡ).
              final audio = context.read<AudioProvider>();
              final overlay = context.read<OverlayProvider>();
              final router = GoRouter.of(context);

              EasyLoading.show(status: 'Đang đăng xuất...');

              // 🟢 CHỈ await đúng việc đăng xuất (đã bọc timeout bên trong nên
              //    KHÔNG THỂ treo). Thêm timeout tổng làm lưới an toàn.
              try {
                await auth.logout().timeout(const Duration(seconds: 6));
              } catch (_) {
                // Bất kể lỗi/timeout gì cũng vẫn đưa về Login.
              }

              EasyLoading.dismiss();

              // 🟢 Dọn dẹp phụ (tắt nút nổi, dừng nhạc) chạy NGẦM — KHÔNG await để
              //    tránh kẹt loading nếu plugin overlay/just_audio không phản hồi.
              overlay.setBubbleEnabled(false);
              audio.stopNativeAudio();
              audio.stopAudio();

              // 🟢 LUÔN điều hướng về Login (dùng router đã giữ sẵn).
              router.go('/login');
            },
            child: const Text('Đăng xuất',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4.w),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 38.w,
          height: 38.w,
          decoration: BoxDecoration(
            color: AppColors.brandBackground,
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(color: AppColors.primary, width: 1),
          ),
          child: Icon(icon, color: Colors.white, size: 18.sp),
        ),
        title: Text(
          title,
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13.sp,
              fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: AppColors.textHint, fontSize: 11.sp),
        ),
        trailing: Icon(Icons.arrow_forward_ios_rounded,
            color: AppColors.textHint, size: 14.sp),
      ),
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitchTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4.w),
      child: ListTile(
        leading: Container(
          width: 38.w,
          height: 38.w,
          decoration: BoxDecoration(
            color: AppColors.brandBackground,
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(color: AppColors.primary, width: 1),
          ),
          child: Icon(icon, color: Colors.white, size: 18.sp),
        ),
        title: Text(
          title,
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13.sp,
              fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: AppColors.textHint, fontSize: 11.sp),
        ),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
          activeColor: Colors.white,
          activeTrackColor: AppColors.primary,
          inactiveThumbColor: AppColors.textHint,
          inactiveTrackColor: AppColors.cardElevated,
        ),
      ),
    );
  }
}
