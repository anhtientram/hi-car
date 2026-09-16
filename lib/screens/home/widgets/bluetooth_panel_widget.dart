import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../../core/app_colors.dart';
import '../../../providers/bluetooth_provider.dart';
import '../../../data/models/bluetooth_device_model.dart';
import '../../../core/constants.dart';
import '../../../widgets/premium_loading.dart';

class BluetoothPanelWidget extends StatefulWidget {
  const BluetoothPanelWidget({super.key});

  @override
  State<BluetoothPanelWidget> createState() => _BluetoothPanelWidgetState();
}

class _BluetoothPanelWidgetState extends State<BluetoothPanelWidget> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<BluetoothProvider>(
      builder: (context, btProvider, _) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(
              color: (btProvider.connectedDevice != null ||
                      btProvider.hasTargetDevice)
                  ? AppColors.primary
                  : AppColors.border,
            ),
            boxShadow: (btProvider.connectedDevice != null ||
                    btProvider.hasTargetDevice)
                ? [
                    BoxShadow(
                      color: AppColors.primary,
                      blurRadius: 8,
                      spreadRadius: 0,
                    )
                  ]
                : null,
          ),
          child: Column(
            children: [
              // Header
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                borderRadius: BorderRadius.circular(16.r),
                child: Padding(
                  padding: EdgeInsets.all(16.w),
                  child: Row(
                    children: [
                      Container(
                        width: 40.w,
                        height: 40.w,
                        decoration: BoxDecoration(
                          color: AppColors.brandBackground,
                          borderRadius: BorderRadius.circular(10.r),
                        ),
                        child: Icon(
                          Icons.bluetooth_rounded,
                          color: Colors.white,
                          size: 20.sp,
                        ),
                      ),
                      SizedBox(width: 14.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Thiết bị Bluetooth',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 2.h),
                            Text(
                              _headerSubtitle(btProvider),
                              style: TextStyle(
                                color: btProvider.connectedDevice != null ||
                                        btProvider.hasTargetDevice
                                    ? AppColors.primary
                                    : AppColors.textHint,
                                fontSize: 11.sp,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: AppColors.textSecondary,
                        size: 20.sp,
                      ),
                    ],
                  ),
                ),
              ),

              // Expanded content
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: _expanded
                    ? _BluetoothExpandedContent(provider: btProvider)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        );
      },
    );
  }
}

String _headerSubtitle(BluetoothProvider provider) {
  final connected = provider.connectedDevice;
  if (connected != null) {
    final isTarget = provider.targetDevice?.address.toLowerCase() ==
        connected.address.toLowerCase();
    return isTarget
        ? '${connected.name} · Đã kết nối · tự phát'
        : '${connected.name} · Đã kết nối';
  }
  if (provider.hasTargetDevice) {
    return '${provider.targetDevice!.name} · Chưa kết nối · ${provider.delaySeconds}s';
  }
  return 'Chưa chọn thiết bị';
}

class _BluetoothExpandedContent extends StatefulWidget {
  final BluetoothProvider provider;

  const _BluetoothExpandedContent({required this.provider});

  @override
  State<_BluetoothExpandedContent> createState() =>
      _BluetoothExpandedContentState();
}

class _BluetoothExpandedContentState extends State<_BluetoothExpandedContent> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.provider.pairedDevices.isEmpty) {
        widget.provider.loadPairedDevices();
      }
      // Auto-start scan when expanding
      widget.provider.startScan();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: AppColors.divider, height: 1),
        SizedBox(height: 12.h),

        // Delay selector
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Độ trễ phát (giây)',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              SizedBox(height: 10.h),
              Row(
                children: AppConstants.delayOptions.map((delay) {
                  final selected = provider.delaySeconds == delay;
                  return Padding(
                    padding: EdgeInsets.only(right: 8.w),
                    child: GestureDetector(
                      onTap: () => provider.setDelaySeconds(delay),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: EdgeInsets.symmetric(
                            horizontal: 14.w, vertical: 8.h),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.brandBackground
                              : AppColors.cardElevated,
                          borderRadius: BorderRadius.circular(10.r),
                          border: Border.all(
                            color:
                                selected ? AppColors.primary : AppColors.border,
                          ),
                        ),
                        child: Text(
                          '${delay}s',
                          style: TextStyle(
                            color: selected
                                ? AppColors.primary
                                : AppColors.textSecondary,
                            fontSize: 13.sp,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),

        SizedBox(height: 16.h),

        // Paired devices header
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Thiết bị đã ghép đôi',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              InkWell(
                onTap: () => provider.loadPairedDevices(),
                borderRadius: BorderRadius.circular(8.r),
                child: Padding(
                  padding: EdgeInsets.all(4.w),
                  child: provider.isLoading
                      ? PremiumLoading(size: 14.w, strokeWidth: 2)
                      : Icon(
                          Icons.refresh_rounded,
                          color: AppColors.primary,
                          size: 18.sp,
                        ),
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: 8.h),

        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: Text(
            'Tự phát = xe được chào khi nối. Kết nối / Ngắt chỉ bật tắt Bluetooth.',
            style: TextStyle(
              color: AppColors.textHint,
              fontSize: 10.sp,
            ),
          ),
        ),

        SizedBox(height: 8.h),

        if (provider.pairedDevices.isEmpty && !provider.isLoading)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
            child: GestureDetector(
              onTap: () => provider.loadPairedDevices(),
              child: Text(
                'Nhấn làm mới để tải danh sách',
                style: TextStyle(
                  color: AppColors.textHint,
                  fontSize: 12.sp,
                ),
              ),
            ),
          )
        else
          ...provider.pairedDevices.map((device) {
            final isConnecting =
                provider.connectingDevices[device.address] == true;
            return _DeviceItem(
              device: device,
              isConnecting: isConnecting,
              onConnectToggle: () => provider.toggleDeviceConnection(device),
              onSetAutoPlay: () => provider.setTargetDevice(device),
              onClearAutoPlay: device.isSelected
                  ? () => provider.clearTargetDevice()
                  : null,
            );
          }),

        SizedBox(height: 16.h),

        // Scanned devices header
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Thiết bị tìm thấy',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              InkWell(
                onTap: () => provider.isScanning
                    ? provider.stopScan()
                    : provider.startScan(),
                borderRadius: BorderRadius.circular(8.r),
                child: Padding(
                  padding: EdgeInsets.all(4.w),
                  child: provider.isScanning
                      ? PremiumLoading(size: 14.w, strokeWidth: 2)
                      : Text(
                          'Tìm kiếm',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 11.sp,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: 8.h),

        if (provider.scannedDevices.isEmpty && !provider.isScanning)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nhấn Tìm kiếm để tìm thiết bị mới',
                  style: TextStyle(
                    color: AppColors.textHint,
                    fontSize: 11.sp,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  'Lưu ý: Bạn có thể cần bật GPS để quét thiết bị.',
                  style: TextStyle(
                    color: AppColors.textHint.withOpacity(0.6),
                    fontSize: 9.sp,
                  ),
                ),
              ],
            ),
          )
        else
          ...provider.scannedDevices.map((device) {
            final isConnecting =
                provider.connectingDevices[device.address] == true;
            return _DeviceItem(
              device: device,
              isConnecting: isConnecting,
              onConnectToggle: () => provider.toggleDeviceConnection(device),
              onSetAutoPlay: () => provider.setTargetDevice(device),
            );
          }),

        SizedBox(height: 12.h),
      ],
    );
  }
}

class _DeviceItem extends StatelessWidget {
  final BluetoothDeviceModel device;
  final bool isConnecting;
  final VoidCallback onConnectToggle;
  final VoidCallback onSetAutoPlay;
  final VoidCallback? onClearAutoPlay;

  const _DeviceItem({
    required this.device,
    required this.isConnecting,
    required this.onConnectToggle,
    required this.onSetAutoPlay,
    this.onClearAutoPlay,
  });

  @override
  Widget build(BuildContext context) {
    final String statusText;
    final Color statusColor;
    if (isConnecting) {
      statusText = device.isConnected ? 'Đang ngắt...' : 'Đang kết nối...';
      statusColor = AppColors.primary;
    } else if (device.isConnected) {
      statusText = 'Đã kết nối';
      statusColor = AppColors.success;
    } else {
      statusText = 'Chưa kết nối';
      statusColor = AppColors.textHint;
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      child: Row(
        children: [
          Icon(
            device.isConnected
                ? Icons.bluetooth_connected_rounded
                : Icons.bluetooth_rounded,
            color: device.isSelected || device.isConnected
                ? AppColors.primary
                : AppColors.textHint,
            size: 18.sp,
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: device.isSelected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontSize: 13.sp,
                    fontWeight:
                        device.isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  '${device.address}  ·  $statusText',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 8.h),
                Row(
                  children: [
                    if (device.isSelected)
                      _AutoPlayBadge(onClear: onClearAutoPlay)
                    else
                      _SmallActionChip(
                        label: 'Tự phát',
                        filled: false,
                        onTap: isConnecting ? null : onSetAutoPlay,
                      ),
                    const Spacer(),
                    if (isConnecting)
                      PremiumLoading(size: 14.w, strokeWidth: 2)
                    else
                      _SmallActionChip(
                        label: device.isConnected ? 'Ngắt' : 'Kết nối',
                        filled: device.isConnected,
                        danger: device.isConnected,
                        onTap: onConnectToggle,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AutoPlayBadge extends StatelessWidget {
  final VoidCallback? onClear;

  const _AutoPlayBadge({this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.success,
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.only(left: 8.w, top: 4.h, bottom: 4.h),
            child: Text(
              'Đang tự phát',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            onPressed: onClear,
            tooltip: 'Bỏ tự phát',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(minWidth: 32.w, minHeight: 32.w),
            icon: Icon(Icons.close_rounded, color: Colors.white, size: 16.sp),
          ),
        ],
      ),
    );
  }
}

class _SmallActionChip extends StatelessWidget {
  final String label;
  final bool filled;
  final bool danger;
  final VoidCallback? onTap;

  const _SmallActionChip({
    required this.label,
    required this.filled,
    this.danger = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : AppColors.primary;
    return Material(
      color: filled ? color : color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8.r),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
          child: Text(
            label,
            style: TextStyle(
              color: filled ? Colors.white : color,
              fontSize: 10.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
