import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_colors.dart';
import '../../native/service_channel.dart';
import '../../providers/permission_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/premium_loading.dart';

class PermissionConfigScreen extends StatefulWidget {
  final bool isFromSettings;

  const PermissionConfigScreen({
    super.key,
    this.isFromSettings = false,
  });

  @override
  State<PermissionConfigScreen> createState() => _PermissionConfigScreenState();
}

class _PermissionConfigScreenState extends State<PermissionConfigScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PermissionProvider>().checkAllPermissions();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<PermissionProvider>().checkAllPermissions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final permissionProvider = context.watch<PermissionProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    final status = permissionProvider.status;
    final activeMode = settingsProvider.pendingConnectionMode ??
        settingsProvider.connectionMode;
    final isBoxMode = activeMode == 'android_box_mode';
    final isXiaomi = permissionProvider.isXiaomi;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Cấu Hình Quyền Hệ Thống',
          style: TextStyle(fontSize: 16.sp),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Platform.isIOS
            ? _buildIOSLayout(context)
            : OrientationBuilder(
          builder: (context, orientation) {
            final isLandscape = orientation == Orientation.landscape;

            if (isLandscape) {
              return Row(
                children: [
                  Container(
                    width: 0.35.sw,
                    padding: EdgeInsets.all(20.w),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cấp Quyền',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        Text(
                          'Cần thiết để Trợ lý tự khởi động và phát âm thanh.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11.sp,
                            height: 1.3,
                          ),
                        ),
                        SizedBox(height: 24.h),
                        _GlowButton(
                          label:
                              widget.isFromSettings ? 'HOÀN TẤT' : 'TIẾP TỤC',
                          onTap: () {
                            if (widget.isFromSettings) {
                              _handleRestart(context);
                            } else {
                              _goToLogin(context);
                            }
                          },
                        ),
                      ],
                    ),
                  ),

                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: AppColors.border.withOpacity(0.3),
                  ),

                  // Cột phải: Grid Permissions
                  Expanded(
                    child: GridView.count(
                      crossAxisCount: 2,
                      padding: EdgeInsets.all(12.w),
                      childAspectRatio: 2.5,
                      mainAxisSpacing: 8.w,
                      crossAxisSpacing: 8.w,
                      children: [
                        _buildPermissionTile(
                          title: 'Bluetooth',
                          subtitle: 'Nhận diện kết nối xe.',
                          icon: Icons.bluetooth_rounded,
                          value: status.bluetoothConnect,
                          onChanged: (val) => val
                              ? permissionProvider.requestBluetoothPermissions()
                              : _showDisableInfo(context),
                          isLandscape: true,
                        ),
                        _buildPermissionTile(
                          title: 'Thông báo',
                          subtitle: 'Hiện trạng thái trợ lý.',
                          icon: Icons.notifications_active_rounded,
                          value: status.notification,
                          onChanged: (val) => val
                              ? permissionProvider
                                  .requestNotificationPermission()
                              : _showDisableInfo(context),
                          isLandscape: true,
                        ),
                        _buildPermissionTile(
                          title: 'Nổi ứng dụng',
                          subtitle: 'Hiện bong bóng hỗ trợ.',
                          icon: Icons.layers_rounded,
                          value: status.overlay,
                          onChanged: (val) => val
                              ? permissionProvider.requestOverlayPermission()
                              : _showDisableInfo(context),
                          isLandscape: true,
                        ),
                        _buildPermissionTile(
                          title: 'Tối ưu pin',
                          subtitle: 'Chạy ngầm không bị tắt.',
                          icon: Icons.battery_charging_full_rounded,
                          value: status.batteryOptimization,
                          onChanged: (val) => val
                              ? permissionProvider
                                  .requestBatteryOptimizationPermission()
                              : _showDisableInfo(context),
                          isLandscape: true,
                        ),
                        _buildPermissionTile(
                          title: 'Chạy ngầm',
                          subtitle: 'Sẵn sàng khi nổ máy.',
                          icon: Icons.bolt_rounded,
                          value: status.bootComplete,
                          onChanged: (val) => val
                              ? _showKeepAliveInfo(context)
                              : _showDisableInfo(context),
                          isLandscape: true,
                        ),
                        if (isBoxMode)
                          _buildPermissionTile(
                            title: 'Autostart',
                            subtitle: 'Tự mở khi bật màn hình.',
                            icon: Icons.auto_mode_rounded,
                            value: false,
                            onChanged: (val) =>
                                permissionProvider.openSettings(),
                            trailingText: 'CÀI',
                            isLandscape: true,
                          ),
                        if (isXiaomi)
                          _buildPermissionTile(
                            title: 'Pop-up nền (MIUI)',
                            subtitle: 'Bắt buộc cho Xiaomi.',
                            icon: Icons.app_registration_rounded,
                            value: false,
                            onChanged: (val) =>
                                permissionProvider.openSettings(),
                            trailingText: 'CÀI',
                            isLandscape: true,
                          ),
                      ],
                    ),
                  ),
                ],
              );
            }

            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(16.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Để ứng dụng hoạt động ổn định và tự động, vui lòng cấp các quyền cần thiết bên dưới.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14.sp,
                          ),
                        ),
                        SizedBox(height: 24.h),
                        _buildPermissionTile(
                          title: 'Bluetooth',
                          subtitle:
                              'Cần thiết để nhận diện khi điện thoại kết nối với xe.',
                          icon: Icons.bluetooth_rounded,
                          value: status.bluetoothConnect,
                          onChanged: (val) {
                            if (val) {
                              permissionProvider.requestBluetoothPermissions();
                            } else {
                              _showDisableInfo(context);
                            }
                          },
                        ),
                        _buildPermissionTile(
                          title: 'Thông báo',
                          subtitle:
                              'Hiển thị trạng thái kết nối và điều khiển nhanh.',
                          icon: Icons.notifications_active_rounded,
                          value: status.notification,
                          onChanged: (val) {
                            if (val) {
                              permissionProvider
                                  .requestNotificationPermission();
                            } else {
                              _showDisableInfo(context);
                            }
                          },
                        ),
                        _buildPermissionTile(
                          title: 'Hiển thị trên ứng dụng khác',
                          subtitle:
                              'Hiển thị bong bóng điều khiển khi bạn đang dùng bản đồ.',
                          icon: Icons.layers_rounded,
                          value: status.overlay,
                          onChanged: (val) {
                            if (val) {
                              permissionProvider.requestOverlayPermission();
                            } else {
                              _showDisableInfo(context);
                            }
                          },
                        ),
                        _buildPermissionTile(
                          title: 'Bỏ qua tối ưu pin',
                          subtitle:
                              'Giúp ứng dụng không bị hệ thống tự động tắt khi chạy ngầm.',
                          icon: Icons.battery_charging_full_rounded,
                          value: status.batteryOptimization,
                          onChanged: (val) {
                            if (val) {
                              permissionProvider
                                  .requestBatteryOptimizationPermission();
                            } else {
                              _showDisableInfo(context);
                            }
                          },
                        ),
                        if (isBoxMode)
                          _buildPermissionTile(
                            title: 'Tự khởi động (Autostart)',
                            subtitle:
                                'Cho phép app tự chào và hiện lên khi vừa bật màn hình xe.',
                            icon: Icons.auto_mode_rounded,
                            value: false,
                            onChanged: (val) {
                              permissionProvider.openSettings();
                            },
                            trailingText: 'CÀI ĐẶT',
                          ),
                        _buildPermissionTile(
                          title: 'Chạy ngầm hệ thống',
                          subtitle:
                              'Giữ cho trợ lý luôn sẵn sàng khi bạn nổ máy xe.',
                          icon: Icons.bolt_rounded,
                          value: status.bootComplete,
                          onChanged: (val) {
                            if (val) {
                              _showKeepAliveInfo(context);
                            } else {
                              _showDisableInfo(context);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(16.w),
                  child: _GlowButton(
                    label: widget.isFromSettings
                        ? 'HOÀN TẤT & KHỞI ĐỘNG LẠI'
                        : 'TIẾP TỤC',
                    onTap: () {
                      if (widget.isFromSettings) {
                        _handleRestart(context);
                      } else {
                        _goToLogin(context);
                      }
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildIOSLayout(BuildContext context) {
    Widget bullet(IconData icon, String title, String desc) => Container(
          margin: EdgeInsets.only(bottom: 12.h),
          padding: EdgeInsets.all(14.w),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(8.w),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 18.sp),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14.sp,
                            fontWeight: FontWeight.bold)),
                    SizedBox(height: 4.h),
                    Text(desc,
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12.sp,
                            height: 1.35)),
                  ],
                ),
              ),
            ],
          ),
        );

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trên iOS không cần các quyền chạy ngầm như Android. Hệ thống tự định tuyến âm thanh ra loa xe khi kết nối CarPlay/Bluetooth.',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 14.sp),
                ),
                SizedBox(height: 16.h),
                const _VehicleRouteStatusCard(),
                SizedBox(height: 4.h),
                bullet(
                  Icons.audiotrack_rounded,
                  'Phát nền tự động',
                  'Ứng dụng đã bật chế độ âm thanh nền — lời chào sẽ phát ra loa xe ngay cả khi màn hình tắt.',
                ),
                bullet(
                  Icons.bolt_rounded,
                  'Thiết lập Phím tắt (nên làm)',
                  'App tự nhận biết khi cắm CarPlay, nhưng nếu iOS đã tắt hẳn app thì cần Phím tắt đánh thức: mở app "Phím tắt" → Tự động hoá → "Khi CarPlay kết nối" → thêm tác vụ "Phát lời chào HiCar", rồi tắt "Hỏi trước khi chạy".',
                ),
                bullet(
                  Icons.mic_rounded,
                  'Gọi bằng Siri (tuỳ chọn)',
                  'Bạn có thể nói "Phát lời chào HiCar" để phát ngay.',
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(16.w),
          child: _GlowButton(
            label: widget.isFromSettings ? 'HOÀN TẤT' : 'TIẾP TỤC',
            onTap: () {
              if (widget.isFromSettings) {
                _handleRestart(context);
              } else {
                _goToLogin(context);
              }
            },
          ),
        ),
      ],
    );
  }

  void _showKeepAliveInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardElevated,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Text(
          'Duy trì hoạt động',
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15.sp,
              fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Hệ thống đã được thiết lập để tự khởi động cùng xe. Để đạt hiệu quả tốt nhất, bạn nên cấp thêm quyền "Bỏ qua tối ưu pin".',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13.sp),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ĐÃ HIỂU',
                style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _showDisableInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardElevated,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Text(
          'Thông báo',
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15.sp,
              fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Để tắt quyền này, vui lòng vào Cài đặt của hệ thống Android để thực hiện.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13.sp),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ĐÃ HIỂU',
                style: TextStyle(color: AppColors.textHint)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<PermissionProvider>().openSettings();
            },
            child: const Text('VÀO CÀI ĐẶT',
                style: TextStyle(
                    color: AppColors.error, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Đi tới màn Login trong luồng cài đặt lần đầu.
  /// 🟢 PHẢI commit chế độ kết nối đang chọn (pending) TRƯỚC khi rời màn này, nếu không
  ///    khi vào app chế độ sẽ luôn về mặc định "Màn hình Android".
  Future<void> _goToLogin(BuildContext context) async {
    await context.read<SettingsProvider>().commitSettings();
    if (context.mounted) context.push('/login');
  }

  void _handleRestart(BuildContext context) async {
    // Commit the settings (especially pending connection mode)
    await context.read<SettingsProvider>().commitSettings();

    if (!mounted) return;

    // Show a loading or success message before "restarting"
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardElevated,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PremiumLoading(size: 36),
            SizedBox(height: 20.h),
            Text(
              'Đang chuẩn hóa hệ thống...',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14.sp),
            ),
            SizedBox(height: 8.h),
            Text(
              'Ứng dụng sẽ khởi động lại để áp dụng cài đặt mới.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12.sp),
            ),
          ],
        ),
      ),
    );

    // Simulate restart by going back to splash and clearing stack
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        context.go('/');
      }
    });
  }

  Widget _buildPermissionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
    String? trailingText,
    bool isLandscape = false,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: isLandscape ? 0 : 12.h),
      padding: EdgeInsets.symmetric(
          horizontal: 4.w, vertical: isLandscape ? 0 : 4.h),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
            color:
                value ? AppColors.primary.withOpacity(0.5) : AppColors.border,
            width: 1.w),
      ),
      child: Center(
        child: ListTile(
          dense: isLandscape,
          contentPadding: EdgeInsets.symmetric(horizontal: 8.w),
          leading: Container(
            padding: EdgeInsets.all(isLandscape ? 6.w : 10.w),
            decoration: BoxDecoration(
              color: value ? AppColors.primary : AppColors.brandBackground,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: isLandscape ? 14.sp : 18.sp,
            ),
          ),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: isLandscape ? 12.sp : 14.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: isLandscape
              ? null
              : Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10.sp,
                  ),
                ),
          trailing: trailingText != null
              ? TextButton(
                  onPressed: () => onChanged(true),
                  child: Text(
                    trailingText,
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 10.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              : Transform.scale(
                  scale: isLandscape ? 0.7 : 0.8,
                  child: Switch(
                    value: value,
                    onChanged: onChanged,
                    activeColor: Colors.white,
                    activeTrackColor: AppColors.primary,
                    inactiveThumbColor: AppColors.textHint,
                    inactiveTrackColor: AppColors.cardElevated,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Hiện đường ra âm thanh hiện tại của iPhone. Khi lời chào không phát, đây là chỗ để
/// người dùng biết máy đã thực sự nối vào xe chưa hay tiếng vẫn đang ra loa điện thoại.
class _VehicleRouteStatusCard extends StatefulWidget {
  const _VehicleRouteStatusCard();

  @override
  State<_VehicleRouteStatusCard> createState() =>
      _VehicleRouteStatusCardState();
}

class _VehicleRouteStatusCardState extends State<_VehicleRouteStatusCard> {
  Timer? _timer;
  bool _connected = false;
  String _route = '';

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final connected = await ServiceChannel.instance.isVehicleConnected();
    final route = await ServiceChannel.instance.getAudioRoute();
    if (!mounted) return;
    if (connected == _connected && route == _route) return;
    setState(() {
      _connected = connected;
      _route = route;
    });
  }

  /// `CarAudio:Toyota Camry` → `Toyota Camry (CarPlay)`.
  String get _label {
    if (_route.isEmpty || _route == 'none') return 'Chưa xác định';
    final first = _route.split(',').first;
    final parts = first.split(':');
    if (parts.length < 2) return first;
    final name = parts[1];
    final kind = switch (parts[0]) {
      'CarAudio' => 'CarPlay',
      'BluetoothA2DPOutput' => 'Bluetooth',
      'BluetoothLE' => 'Bluetooth LE',
      'BluetoothHFP' => 'Bluetooth rảnh tay',
      _ => 'Loa điện thoại',
    };
    return '$name ($kind)';
  }

  @override
  Widget build(BuildContext context) {
    final color = _connected ? AppColors.primary : AppColors.textHint;

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: _connected ? color : AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8.w),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(
              _connected
                  ? Icons.directions_car_filled_rounded
                  : Icons.phone_iphone_rounded,
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
                  _connected ? 'Đã nối loa xe' : 'Chưa nối loa xe',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  'Đang phát ra: $_label',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.sp,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _GlowButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: isLandscape ? 38.h : 56.h, // 🟢 Bé lại hẳn theo ý user
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius:
              BorderRadius.circular(8.r), // 🟢 Bo góc ít hơn cho góc cạnh
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white, // 🟢 BẮT BUỘC TRẮNG
              fontSize: isLandscape ? 12.sp : 15.sp,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}
