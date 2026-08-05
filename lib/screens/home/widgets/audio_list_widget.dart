import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../../core/app_colors.dart';
import '../../../core/constants.dart';
import '../../../data/models/audio_model.dart';
import '../../../providers/audio_provider.dart';

class AudioListWidget extends StatelessWidget {
  const AudioListWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioProvider>(
      builder: (context, audioProvider, _) {
        final list = audioProvider.audioList;

        if (list.isEmpty) {
          return _EmptyState();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.zero,
              child: Row(
                children: [
                  Icon(Icons.library_music_rounded,
                      color: AppColors.primary, size: 18.sp),
                  SizedBox(width: 8.w),
                  Text(
                    'Danh sách audio (${list.length})',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 12.h),
            ListView.separated(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: list.length,
              separatorBuilder: (_, __) => SizedBox(height: 10.h),
              itemBuilder: (context, index) {
                return _AudioCard(audio: list[index]);
              },
            ),
          ],
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.symmetric(vertical: 32.h),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(
            Icons.cloud_download_outlined,
            color: AppColors.textHint,
            size: 48.sp,
          ),
          SizedBox(height: 12.h),
          Text(
            'Chưa có audio nào',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            'Nhấn nút Đồng bộ để tải audio về',
            style: TextStyle(
              color: AppColors.textHint,
              fontSize: 12.sp,
            ),
          ),
        ],
      ),
    );
  }
}

class _AudioCard extends StatelessWidget {
  final AudioModel audio;

  const _AudioCard({required this.audio});

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioProvider>(
      builder: (context, audioProvider, _) {
        final isPlaying = audioProvider.currentlyPlaying?.id == audio.id &&
            audioProvider.isPlaying;
        final isPreparing = audioProvider.isPreparingAudio(audio.id);
        final isActive = isPlaying || isPreparing;

        final typeColor = audio.type == AudioType.greeting
            ? AppColors.primary
            : audio.type == AudioType.goodbye
                ? AppColors.success
                : AppColors.warning;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: isPlaying
                ? AppColors.primary.withOpacity(0.10)
                : isPreparing
                    ? AppColors.primary.withOpacity(0.06)
                    : AppColors.card,
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(
              color: isActive ? AppColors.primary : AppColors.border,
              width: isActive ? 1.5 : 1,
            ),
            boxShadow: isPlaying
                ? [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.18),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 34.w,
                height: 34.w,
                decoration: BoxDecoration(
                  color: typeColor,
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(
                  audio.type == AudioType.greeting
                      ? Icons.waving_hand_rounded
                      : audio.type == AudioType.goodbye
                          ? Icons.directions_car_rounded
                          : Icons.audiotrack_rounded,
                  color: Colors.white,
                  size: 16.sp,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            audio.title,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isPreparing)
                          Padding(
                            padding: EdgeInsets.only(left: 6.w),
                            child: Text(
                              'Đang tải...',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 9.sp,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        else if (isPlaying)
                          Padding(
                            padding: EdgeInsets.only(left: 6.w),
                            child: _PlayingBadge(),
                          ),
                      ],
                    ),
                    SizedBox(height: 4.h),
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 8.w, vertical: 2.h),
                          decoration: BoxDecoration(
                            color: AppColors.brandBackground,
                            borderRadius: BorderRadius.circular(6.r),
                          ),
                          child: Text(
                            audio.type.label,
                            style: TextStyle(
                              color: typeColor,
                              fontSize: 10.sp,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        SizedBox(width: 8.w),
                        if (audio.isActiveGreeting)
                          _StatusBadge(
                              label: '✓ Lời chào', color: AppColors.primary),
                        SizedBox(width: 8.w),
                        if (audio.isActiveGoodbye)
                          _StatusBadge(
                              label: '✓ Tạm biệt', color: AppColors.success),
                      ],
                    ),
                    if (audio.isDownloaded) ...[
                      SizedBox(height: 4.h),
                      Row(
                        children: [
                          Icon(Icons.download_done_rounded,
                              color: AppColors.success, size: 12.sp),
                          SizedBox(width: 4.w),
                          Text(
                            'Đã tải · ${audio.durationSeconds}s',
                            style: TextStyle(
                              color: AppColors.textHint,
                              fontSize: 10.sp,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              _AudioActions(
                audio: audio,
                isPlaying: isPlaying,
                isPreparing: isPreparing,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlayingBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 10.sp),
          SizedBox(width: 3.w),
          Text(
            'Đang phát',
            style: TextStyle(
              color: Colors.white,
              fontSize: 9.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6.r),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 9.sp,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _AudioActions extends StatelessWidget {
  final AudioModel audio;
  final bool isPlaying;
  final bool isPreparing;

  const _AudioActions({
    required this.audio,
    required this.isPlaying,
    required this.isPreparing,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.read<AudioProvider>();
    final isBuiltInGoodbye = audio.id == AppConstants.defaultGoodbyeId;
    final isActive = isPlaying || isPreparing;

    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: 160.w),
      icon: Icon(
        isPlaying
            ? Icons.graphic_eq_rounded
            : isPreparing
                ? Icons.hourglass_top_rounded
                : Icons.more_vert_rounded,
        color: isActive ? AppColors.primary : AppColors.textSecondary,
        size: 20.sp,
      ),
      color: AppColors.cardElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      onSelected: (value) async {
        switch (value) {
          case 'play':
            if (isPlaying || isPreparing) {
              await provider.stopAudio();
            } else {
              await provider.playAudio(audio);
            }
            break;
          case 'set_greeting':
            await provider.setAsGreeting(audio.id);
            _showSnack(context, 'Đã đặt làm lời chào ✓');
            break;
          case 'unset_greeting':
            await provider.unsetGreeting();
            _showSnack(context, 'Đã bỏ làm lời chào');
            break;
          case 'set_goodbye':
            await provider.setAsGoodbye(audio.id);
            _showSnack(context, 'Đã đặt làm lời tạm biệt ✓');
            break;
          case 'unset_goodbye':
            await provider.unsetGoodbye();
            _showSnack(context, 'Đã bỏ làm lời tạm biệt');
            break;
          case 'delete':
            await provider.deleteAudio(audio.id);
            break;
        }
      },
      itemBuilder: (context) => [
        if (audio.hasLocalFile)
          _popupItem(
            value: 'play',
            icon: isPlaying || isPreparing
                ? Icons.stop_rounded
                : Icons.play_arrow_rounded,
            label: isPlaying || isPreparing ? 'Dừng' : 'Nghe thử',
          ),
        _popupItem(
          value: audio.isActiveGreeting ? 'unset_greeting' : 'set_greeting',
          icon: audio.isActiveGreeting
              ? Icons.do_not_disturb_on_outlined
              : Icons.waving_hand_rounded,
          label:
              audio.isActiveGreeting ? 'Bỏ làm lời chào' : 'Đặt làm lời chào',
          color: AppColors.primary,
        ),
        if (!isBuiltInGoodbye || !audio.isActiveGoodbye)
          _popupItem(
            value: audio.isActiveGoodbye ? 'unset_goodbye' : 'set_goodbye',
            icon: audio.isActiveGoodbye
                ? Icons.do_not_disturb_on_outlined
                : Icons.directions_car_rounded,
            label: audio.isActiveGoodbye
                ? 'Bỏ làm tạm biệt'
                : 'Đặt làm tạm biệt',
            color: AppColors.success,
          ),
        if (!isBuiltInGoodbye)
          _popupItem(
            value: 'delete',
            icon: Icons.delete_outline_rounded,
            label: 'Xoá',
            color: const Color(0xFFFF5252),
          ),
      ],
    );
  }

  PopupMenuItem<String> _popupItem({
    required String value,
    required IconData icon,
    required String label,
    Color color = AppColors.textPrimary,
  }) {
    return PopupMenuItem(
      value: value,
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18.sp),
          SizedBox(width: 10.w),
          Text(label, style: TextStyle(color: color, fontSize: 13.sp)),
        ],
      ),
    );
  }

  void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
