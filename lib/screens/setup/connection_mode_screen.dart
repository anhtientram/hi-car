import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_colors.dart';
import '../../core/constants.dart';
import '../../providers/settings_provider.dart';

class ConnectionModeScreen extends StatefulWidget {
  final bool isFromSettings;

  const ConnectionModeScreen({
    super.key,
    this.isFromSettings = false,
  });

  @override
  State<ConnectionModeScreen> createState() => _ConnectionModeScreenState();
}

class _ConnectionModeScreenState extends State<ConnectionModeScreen> {
  String? _selectedMode;

  @override
  void initState() {
    super.initState();
    // iOS chỉ có 1 chế độ duy nhất: CarPlay.
    if (Platform.isIOS) {
      _selectedMode = AppConstants.iosCarplayMode;
    } else {
      _selectedMode = context.read<SettingsProvider>().pendingConnectionMode ??
          context.read<SettingsProvider>().connectionMode;
    }
  }

  Widget _buildIOSLayout(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trên iPhone, ứng dụng hoạt động cùng CarPlay. Khi điện thoại kết nối với xe, âm thanh sẽ tự phát ra loa xe. Tự động hóa không mở app cần iOS 16 trở lên; iOS cũ có thể cần mở app thủ công.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14.sp,
                  ),
                ),
                SizedBox(height: 24.h),
                _buildModeCard(
                  context,
                  mode: AppConstants.iosCarplayMode,
                  title: 'iPhone + CarPlay',
                  description:
                      'Phát lời chào/tạm biệt khi kết nối CarPlay. Dùng app Phím tắt để tự động phát khi lên xe.',
                  icon: Icons.directions_car_filled_rounded,
                  activeMode: AppConstants.iosCarplayMode,
                  onTap: () {},
                ),
                SizedBox(height: 24.h),
                _buildShortcutGuide(),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(16.w),
          child: _GlowButton(
            label: 'TIẾP TỤC',
            onTap: () => _handleContinue(context),
          ),
        ),
      ],
    );
  }

  Widget _buildShortcutGuide() {
    Widget step(String n, String text) => Padding(
          padding: EdgeInsets.only(bottom: 10.h),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 22.w,
                height: 22.w,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Text(n,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11.sp,
                        fontWeight: FontWeight.bold)),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(text,
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5.sp,
                        height: 1.35)),
              ),
            ],
          ),
        );

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_rounded, color: AppColors.primary, size: 18.sp),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  'Tự động phát khi lên xe (qua Phím tắt)',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 14.h),
          step('1', 'Mở app "Phím tắt" (Shortcuts) → tab "Tự động hoá" → "+".'),
          step('2', 'Chọn "Tạo Tự động hoá Cá nhân" → "CarPlay" → "Khi kết nối".'),
          step('3',
              'Chọn "Thêm tác vụ", tìm ứng dụng này và chọn "Phát lời chào HiCar".'),
          step('4',
              'Tắt "Hỏi trước khi chạy" để xe tự phát lời chào ngay khi kết nối.'),
          SizedBox(height: 4.h),
          Text(
            'Mẹo: tạo thêm một Tự động hoá "Khi ngắt kết nối" → "Phát lời tạm biệt HiCar".',
            style: TextStyle(
                color: AppColors.textHint,
                fontSize: 11.5.sp,
                fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final activeMode = _selectedMode ?? settings.connectionMode;

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          context.read<SettingsProvider>().cancelPendingSettings();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: widget.isFromSettings
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_rounded),
                  onPressed: () => context.pop(),
                )
              : null,
          title: Text(
            'Chọn Chế Độ Kết Nối',
            style: TextStyle(fontSize: 16.sp),
          ),
          centerTitle: true,
          automaticallyImplyLeading: widget.isFromSettings,
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
                    // Cột trái: Tiêu đề & Mô tả
                    Container(
                      width: 0.35.sw,
                      padding: EdgeInsets.all(24.w),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Chọn Chế Độ',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 20.sp,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 12.h),
                          Text(
                            'Cấu hình cách bạn kết nối với xe để Trợ lý hoạt động chính xác nhất.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12.sp,
                              height: 1.4,
                            ),
                          ),
                          SizedBox(height: 32.h),
                          _GlowButton(
                            label: 'LƯU & TIẾP TỤC',
                            onTap: () => _handleContinue(context),
                          ),
                        ],
                      ),
                    ),

                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: AppColors.border.withOpacity(0.3),
                    ),

                    // Cột phải: Grid các lựa chọn
                    Expanded(
                      child: GridView.count(
                        crossAxisCount: 2,
                        padding: EdgeInsets.all(12.w),
                        childAspectRatio: 2.5,
                        mainAxisSpacing: 8.w,
                        crossAxisSpacing: 8.w,
                        children: [
                          _buildModeCard(
                            context,
                            mode: 'phone_bluetooth',
                            title: 'Bluetooth',
                            description: 'Phát khi kết nối xe.',
                            icon: Icons.bluetooth_rounded,
                            activeMode: activeMode,
                            onTap: () => setState(
                                () => _selectedMode = 'phone_bluetooth'),
                            isLandscape: true,
                          ),
                          _buildModeCard(
                            context,
                            mode: 'phone_android_auto',
                            title: 'Android Auto',
                            description: 'Phát qua màn hình AA.',
                            icon: Icons.directions_car_filled_rounded,
                            activeMode: activeMode,
                            onTap: () => setState(
                                () => _selectedMode = 'phone_android_auto'),
                            isLandscape: true,
                          ),
                          _buildModeCard(
                            context,
                            mode: 'android_screen_mode',
                            title: 'Màn hình Độ',
                            description: 'Cài trên màn xe độ.',
                            icon: Icons.developer_board_rounded,
                            activeMode: activeMode,
                            onTap: () => setState(
                                () => _selectedMode = 'android_screen_mode'),
                            isLandscape: true,
                          ),
                          _buildModeCard(
                            context,
                            mode: 'android_box_mode',
                            title: 'Android Box',
                            description: 'Cài trên cục Box xe.',
                            icon: Icons.settings_input_hdmi_rounded,
                            activeMode: activeMode,
                            onTap: () => setState(
                                () => _selectedMode = 'android_box_mode'),
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
                            'Hệ thống cần biết cách bạn kết nối với xe để tối ưu hóa việc phát lời chào.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14.sp,
                            ),
                          ),
                          SizedBox(height: 24.h),
                          _buildModeCard(
                            context,
                            mode: 'phone_bluetooth',
                            title: 'Điện thoại + Bluetooth',
                            description:
                                'Tự động phát lời chào khi điện thoại kết nối Bluetooth với xe.',
                            icon: Icons.bluetooth_rounded,
                            activeMode: activeMode,
                            onTap: () => setState(
                                () => _selectedMode = 'phone_bluetooth'),
                          ),
                          SizedBox(height: 16.h),
                          _buildModeCard(
                            context,
                            mode: 'phone_android_auto',
                            title: 'Điện thoại + Android Auto',
                            description:
                                'Chỉ tự động phát khi xe kích hoạt màn hình Android Auto.',
                            icon: Icons.directions_car_filled_rounded,
                            activeMode: activeMode,
                            onTap: () => setState(
                                () => _selectedMode = 'phone_android_auto'),
                          ),
                          SizedBox(height: 16.h),
                          _buildModeCard(
                            context,
                            mode: 'android_screen_mode',
                            title: 'Màn hình Android độ',
                            description:
                                'Cài trên màn hình xe. Tự mở app khi nổ máy và tự ẩn sau khi phát nhạc xong.',
                            icon: Icons.developer_board_rounded,
                            activeMode: activeMode,
                            onTap: () => setState(
                                () => _selectedMode = 'android_screen_mode'),
                          ),
                          SizedBox(height: 16.h),
                          _buildModeCard(
                            context,
                            mode: 'android_box_mode',
                            title: 'Android Box',
                            description:
                                'Cài trên cục Box. Tự phát nhạc ngầm ngay khi Box khởi động.',
                            icon: Icons.settings_input_hdmi_rounded,
                            activeMode: activeMode,
                            onTap: () => setState(
                                () => _selectedMode = 'android_box_mode'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(16.w),
                    child: _GlowButton(
                      label: 'TIẾP TỤC',
                      onTap: () => _handleContinue(context),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _handleContinue(BuildContext context) async {
    if (_selectedMode != null) {
      final settings = context.read<SettingsProvider>();
      await settings.setConnectionMode(_selectedMode!);
    }

    if (!context.mounted) return;
    if (widget.isFromSettings) {
      context.push('/permission-config?fromSettings=true');
    } else {
      context.push('/permission-config');
    }
  }

  Widget _buildModeCard(
    BuildContext context, {
    required String mode,
    required String title,
    required String description,
    required IconData icon,
    required String activeMode,
    required VoidCallback onTap,
    bool isLandscape = false,
  }) {
    final isSelected = mode == activeMode;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(isLandscape ? 6.w : 16.w),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brandBackground : AppColors.card,
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 2.w : 1.w,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(isLandscape ? 6.w : 10.w),
              decoration: BoxDecoration(
                color:
                    isSelected ? AppColors.primary : AppColors.brandBackground,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: isLandscape ? 14.sp : 20.sp,
              ),
            ),
            SizedBox(width: isLandscape ? 8.w : 16.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                      fontSize: isLandscape ? 12.sp : 15.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (!isLandscape) ...[
                    SizedBox(height: 4.h),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.sp,
                        height: 1.2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
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
        height: isLandscape ? 38.h : 56.h,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(8.r),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: isLandscape ? 12.sp : 15.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
