import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hi_car/providers/permission_provider.dart';
import 'package:hi_car/providers/settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_colors.dart';
import '../../core/utils/ui_utils.dart';
import '../../providers/auth_provider.dart';
import '../../providers/audio_provider.dart';
import '../../providers/overlay_provider.dart';
import 'widgets/audio_list_widget.dart';
import 'widgets/bluetooth_panel_widget.dart';
import 'widgets/permission_status_widget.dart';
import 'widgets/playback_controller_widget.dart';
import '../../widgets/premium_loading.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // 🟢 Giữ tham chiếu trực tiếp để gỡ listener an toàn trong dispose().
  //    KHÔNG dùng context.read trong dispose() vì element đã bị defunct → crash
  //    "Null check operator used on a null value".
  AudioProvider? _audioProviderRef;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _checkAll();
      _audioProviderRef = context.read<AudioProvider>();
      _audioProviderRef?.addListener(_audioListener);
    });
  }

  void _audioListener() {
    if (!mounted) return;
    final audio = _audioProviderRef ?? context.read<AudioProvider>();
    if (audio.syncStatus == SyncStatus.error && audio.syncError != null) {
      UiUtils.showError(context, audio.syncError!);
    } else if (audio.syncStatus == SyncStatus.success) {
      UiUtils.showSuccess(context, audio.syncMessage);
    }
  }

  @override
  void dispose() {
    _audioProviderRef?.removeListener(_audioListener);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAll();
      // 🟢 KHÔNG tự phát lại lời chào ở chế độ Box khi resume.
      //    Box do BootReceiver/Service phát ngầm khi Box khởi động — nếu phát thêm
      //    ở đây sẽ gây "đang phát bị ngắt rồi phát lại từ đầu" hoặc "phát xong lại
      //    phát tiếp" mỗi lần app quay lại tiền cảnh.
    }
  }

  void _checkAll() {
    if (mounted) {
      context.read<PermissionProvider>().checkAllPermissions();
      final overlayProvider = context.read<OverlayProvider>();
      overlayProvider.checkPermission();
      overlayProvider.syncOverlayState();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final audioProvider = context.watch<AudioProvider>();
    final overlayProvider = context.watch<OverlayProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    final user = authProvider.user;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 32.w,
              height: 32.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary, width: 1.5),
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/images/logo_thuongia.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
            SizedBox(width: 10.w),
            Text(
              'Giọng Thương Gia',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        actions: [
          _SyncButton(audioProvider: audioProvider),
          IconButton(
            icon: Icon(Icons.settings_rounded,
                color: AppColors.primary, size: 22.sp),
            onPressed: () => context.push('/settings'),
          ),
          SizedBox(width: 8.w),
        ],
      ),
      body: SafeArea(
        child: OrientationBuilder(
          builder: (context, orientation) {
            final isLandscape = orientation == Orientation.landscape;
            if (isLandscape) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cột trái: Trạng thái & Điều khiển
                  SizedBox(
                    width: 0.48.sw,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(16.w, 12.h, 8.w, 12.h),
                      physics: const ClampingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (user != null) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: _UserProfileCard(
                                      user: user, isCompact: true),
                                ),
                                SizedBox(width: 10.w),
                                if (io.Platform.isAndroid)
                                  Expanded(
                                    child: _FloatingBubbleToggleCard(
                                        overlayProvider: overlayProvider,
                                        isCompact: true),
                                  ),
                              ],
                            ),
                          ],
                          SizedBox(height: 10.h),
                          const PermissionStatusWidget(),
                          if (io.Platform.isAndroid &&
                              settingsProvider.connectionMode ==
                                  'phone_bluetooth') ...[
                            SizedBox(height: 10.h),
                            const BluetoothPanelWidget(),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // Đường chia ngăn nhẹ
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: AppColors.border.withOpacity(0.3),
                  ),

                  // Cột phải: Playback Controller (Top) + Danh sách Audio (Bottom)
                  Expanded(
                    child: _HomeRefreshScroll(
                      onRefresh: () => audioProvider.syncFromServer(),
                      padding: EdgeInsets.fromLTRB(8.w, 12.h, 16.w, 12.h),
                      child: Column(
                        children: [
                          const PlaybackControllerWidget(),
                          SizedBox(height: 12.h),
                          const AudioListWidget(),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }

            return _HomeRefreshScroll(
              onRefresh: () => audioProvider.syncFromServer(),
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 16.h),
                  if (user != null)
                    Row(
                      children: [
                        Expanded(
                            child:
                                _UserProfileCard(user: user, isCompact: true)),
                        SizedBox(width: 10.w),
                        if (io.Platform.isAndroid)
                          Expanded(
                            child: _FloatingBubbleToggleCard(
                              overlayProvider: overlayProvider,
                              isCompact: true,
                            ),
                          ),
                      ],
                    ),
                  SizedBox(height: 16.h),
                  const PermissionStatusWidget(),
                  if (io.Platform.isAndroid &&
                      settingsProvider.connectionMode == 'phone_bluetooth') ...[
                    SizedBox(height: 16.h),
                    const BluetoothPanelWidget(),
                  ],
                  SizedBox(height: 16.h),
                  const PlaybackControllerWidget(),
                  SizedBox(height: 24.h),
                  const AudioListWidget(),
                  SizedBox(height: 40.h),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Refresh + scroll không stretch/bounce đen đè lên content.
class _HomeRefreshScroll extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final EdgeInsetsGeometry padding;
  final Widget child;

  const _HomeRefreshScroll({
    required this.onRefresh,
    required this.padding,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: const _NoStretchScrollBehavior(),
      child: RefreshIndicator(
        onRefresh: onRefresh,
        color: AppColors.primary,
        backgroundColor: AppColors.card,
        displacement: 40,
        child: CustomScrollView(
          // Clamping: không rubber-band → không lộ vùng đen che list khi kéo mạnh.
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          slivers: [
            SliverPadding(
              padding: padding,
              sliver: SliverToBoxAdapter(child: child),
            ),
            // Đủ chiều cao để kéo refresh khi content ngắn, không vẽ khối đen đè list.
            const SliverFillRemaining(
              hasScrollBody: false,
              child: SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoStretchScrollBehavior extends MaterialScrollBehavior {
  const _NoStretchScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // Tắt glow/stretch Material 3 — chính là vùng đen khi kéo mạnh.
    return child;
  }
}

class _SyncButton extends StatelessWidget {
  final AudioProvider audioProvider;
  const _SyncButton({required this.audioProvider});

  @override
  Widget build(BuildContext context) {
    if (audioProvider.isSyncing) {
      return Container(
        margin: EdgeInsets.only(right: 8.w),
        width: 32.w,
        height: 32.w,
        padding: EdgeInsets.all(6.w),
        child: const PremiumLoading(size: 16, color: AppColors.primary),
      );
    }
    return IconButton(
      icon: Icon(Icons.sync_rounded, color: AppColors.primary, size: 22.sp),
      onPressed: () => audioProvider.syncFromServer(),
      tooltip: 'Đồng bộ dữ liệu',
    );
  }
}

class _UserProfileCard extends StatelessWidget {
  final dynamic user;
  final bool isCompact;

  const _UserProfileCard({required this.user, this.isCompact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: isCompact ? 40.h : 60.h, // 🟢 Smaller height for compactness
      padding: EdgeInsets.symmetric(horizontal: 10.w),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: isCompact ? 28.w : 38.w,
            height: isCompact ? 28.w : 38.w,
            decoration: BoxDecoration(
              color: AppColors.brandBackground,
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: AppColors.primary, width: 1),
            ),
            child: Icon(Icons.person_rounded,
                color: Colors.white, size: isCompact ? 16.sp : 22.sp),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment:
                  MainAxisAlignment.center, // 🟢 Center for alignment
              children: [
                Text(
                  user.name,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: isCompact ? 11.sp : 15.sp,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  user.phone,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: isCompact ? 8.sp : 12.sp,
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

class _FloatingBubbleToggleCard extends StatelessWidget {
  final OverlayProvider overlayProvider;
  final bool isCompact;

  const _FloatingBubbleToggleCard({
    required this.overlayProvider,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final status = overlayProvider.isBubbleEnabled;

    return Container(
      height: isCompact ? 40.h : 60.h, // 🟢 Matching height
      padding: EdgeInsets.symmetric(horizontal: 10.w),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12.r),
        border:
            Border.all(color: status ? AppColors.success : AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: isCompact ? 28.w : 38.w,
            height: isCompact ? 28.w : 38.w,
            decoration: BoxDecoration(
              color: AppColors.brandBackground,
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(
                  color: status ? AppColors.success : AppColors.primary,
                  width: 1),
            ),
            child: Icon(
              Icons.widgets_rounded,
              color: Colors.white,
              size: isCompact ? 16.sp : 22.sp,
            ),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              'Nút nổi',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: isCompact ? 11.sp : 13.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Transform.scale(
            scale: isCompact ? 0.6 : 0.8,
            child: Switch(
              value: status,
              inactiveThumbColor: AppColors.textHint,
              onChanged: (val) => overlayProvider.setBubbleEnabled(val),
              activeColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _OverlayDebugCard extends StatelessWidget {
  const _OverlayDebugCard();
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: OverlayDebugStore.notifier,
      builder: (context, message, _) {
        if (message == null || message.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: EdgeInsets.all(14.w),
          color: AppColors.brandBackground,
          child: Text(message, style: const TextStyle(color: Colors.white)),
        );
      },
    );
  }
}
