import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/app_colors.dart';
import '../../../providers/audio_provider.dart';
import '../../../widgets/premium_loading.dart';

class PlaybackControllerWidget extends StatelessWidget {
  const PlaybackControllerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioProvider>(
      builder: (context, audioProvider, _) {
        final hasGreeting = audioProvider.activeGreeting != null;

        return Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
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
                  Expanded(
                    child: _ControllerButton(
                      label: audioProvider.isPreparingGreeting
                          ? 'Đang chuẩn bị...'
                          : audioProvider.isNativeGreetingPlaying
                              ? 'Đang phát lời chào'
                              : 'Phát lời chào',
                      subLabel: hasGreeting
                          ? audioProvider.activeGreeting!.title
                          : 'Chưa cài đặt',
                      icon: Icons.waving_hand_rounded,
                      color: AppColors.primary,
                      isEnabled: hasGreeting &&
                          !audioProvider.isPreparingNativePlayback,
                      isPlaying: audioProvider.isNativeGreetingPlaying,
                      isPreparing: audioProvider.isPreparingGreeting,
                      onTap: () => audioProvider.playGreetingViaNative(),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: _ControllerButton(
                      label: audioProvider.isPreparingGoodbye
                          ? 'Đang chuẩn bị...'
                          : audioProvider.isNativeGoodbyePlaying
                              ? 'Đang phát tạm biệt'
                              : 'Phát tạm biệt',
                      subLabel: audioProvider.activeGoodbye.title,
                      icon: Icons.directions_car_rounded,
                      color: AppColors.success,
                      isEnabled: !audioProvider.isPreparingNativePlayback,
                      isPlaying: audioProvider.isNativeGoodbyePlaying,
                      isPreparing: audioProvider.isPreparingGoodbye,
                      onTap: () => audioProvider.playGoodbyeViaNative(),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8.h),
              _ScaleButton(
                onTap: () => audioProvider.stopNativeAudio(),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12.r),
                  child: Material(
                    color: AppColors.cardElevated.withBlue(80),
                    child: InkWell(
                      onTap: () => audioProvider.stopNativeAudio(),
                      splashColor: AppColors.primary.withOpacity(0.3),
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(vertical: 8.h),
                        decoration: BoxDecoration(
                          border:
                              Border.all(color: AppColors.primary, width: 1.5),
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: EdgeInsets.all(4.w),
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.power_settings_new_rounded,
                                  color: Colors.white, size: 14.sp),
                            ),
                            SizedBox(width: 8.w),
                            Text(
                              'DỪNG PHÁT',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 11.sp,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ControllerButton extends StatelessWidget {
  final String label;
  final String subLabel;
  final IconData icon;
  final Color color;
  final bool isEnabled;
  final bool isPlaying;
  final bool isPreparing;
  final VoidCallback onTap;

  const _ControllerButton({
    required this.label,
    required this.subLabel,
    required this.icon,
    required this.color,
    required this.isEnabled,
    this.isPlaying = false,
    this.isPreparing = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = isPlaying || isPreparing;

    return _ScaleButton(
      onTap: isEnabled ? onTap : null,
      child: Opacity(
        opacity: isEnabled || isPreparing ? 1.0 : 0.4,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12.r),
          child: Material(
            color: isPreparing
                ? color.withOpacity(0.08)
                : isPlaying
                    ? color.withOpacity(0.12)
                    : AppColors.cardElevated,
            child: InkWell(
              onTap: isEnabled ? onTap : null,
              splashColor: color.withOpacity(0.3),
              highlightColor: color.withOpacity(0.1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(
                    color: active ? color : AppColors.border,
                    width: active ? 2 : 1,
                  ),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: color.withOpacity(0.28),
                            blurRadius: 8,
                            spreadRadius: 1,
                          )
                        ]
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: EdgeInsets.all(8.w),
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, color: Colors.white, size: 20.sp),
                        ),
                        if (isPreparing)
                          PremiumLoading(size: 18.sp, color: color, strokeWidth: 2)
                        else if (isPlaying)
                          _PulseIcon(
                            key: const ValueKey('playing_icon'),
                            color: color,
                          )
                        else
                          Icon(
                            key: const ValueKey('stopped_icon'),
                            Icons.play_circle_filled_rounded,
                            color: color,
                            size: 18.sp,
                          ),
                      ],
                    ),
                    SizedBox(height: 12.h),
                    Text(
                      label,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      isPreparing ? 'Chờ service phản hồi...' : subLabel,
                      style: TextStyle(
                        color: isPreparing ? color : AppColors.textHint,
                        fontSize: 10.sp,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _ScaleButton({required this.child, this.onTap});

  @override
  State<_ScaleButton> createState() => _ScaleButtonState();
}

class _ScaleButtonState extends State<_ScaleButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (widget.onTap != null) {
          _controller.forward().then((_) => _controller.reverse());
          HapticFeedback.lightImpact();
          widget.onTap!();
        }
      },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return ScaleTransition(
            scale: _scaleAnimation,
            child: Container(
              foregroundDecoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05 * _controller.value),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: child,
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _PulseIcon extends StatefulWidget {
  final Color color;
  const _PulseIcon({super.key, required this.color});

  @override
  State<_PulseIcon> createState() => _PulseIconState();
}

class _PulseIconState extends State<_PulseIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(0.4 * _controller.value),
                blurRadius: 8 * _controller.value,
                spreadRadius: 4 * _controller.value,
              ),
            ],
          ),
          child: Icon(
            Icons.pause_circle_filled_rounded,
            color: widget.color,
            size: 20.sp,
          ),
        );
      },
    );
  }
}
