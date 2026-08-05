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
              color: btProvider.hasTargetDevice
                  ? AppColors.primary
                  : AppColors.border,
            ),
            boxShadow: btProvider.hasTargetDevice
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
                              btProvider.hasTargetDevice
                                  ? '${btProvider.targetDevice!.name} · ${btProvider.delaySeconds}s delay'
                                  : 'Chưa chọn thiết bị',
                              style: TextStyle(
                                color: btProvider.hasTargetDevice
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
              onTap: () => provider.toggleDeviceConnection(device),
              onClear: provider.hasTargetDevice &&
                      provider.targetDevice?.address == device.address
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
              onTap: () => provider.toggleDeviceConnection(device),
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
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _DeviceItem({
    required this.device,
    required this.isConnecting,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    String statusText = '';
    Color statusColor = AppColors.textHint;
    Widget? trailingWidget;

    if (isConnecting) {
      statusText = device.isConnected ? 'Đang ngắt...' : 'Đang kết nối...';
      statusColor = AppColors.primary;
      trailingWidget = PremiumLoading(size: 14.w, strokeWidth: 2);
    } else if (device.isConnected) {
      statusText = 'Đã kết nối';
      statusColor = AppColors.success;
      trailingWidget = Container(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
        decoration: BoxDecoration(
          color: AppColors.error.withOpacity(0.8),
          borderRadius: BorderRadius.circular(8.r),
        ),
        child: Text(
          'Ngắt kết nối',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10.sp,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    } else {
      statusText = 'Chưa kết nối';
      statusColor = AppColors.textHint;
      trailingWidget = Container(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(color: AppColors.primary.withOpacity(0.3)),
        ),
        child: Text(
          'Kết nối',
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 10.sp,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return InkWell(
      onTap: isConnecting ? null : onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
        child: Row(
          children: [
            Icon(
              device.isConnected
                  ? Icons.bluetooth_connected_rounded
                  : Icons.bluetooth_rounded,
              color: device.isSelected ? AppColors.primary : AppColors.textHint,
              size: 18.sp,
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
                          device.name,
                          style: TextStyle(
                            color: device.isSelected
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                            fontSize: 13.sp,
                            fontWeight: device.isSelected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      if (device.isSelected) ...[
                        SizedBox(width: 6.w),
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 6.w, vertical: 2.h),
                          decoration: BoxDecoration(
                            color: AppColors.success,
                            borderRadius: BorderRadius.circular(6.r),
                          ),
                          child: Text(
                            'Tự phát',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9.sp,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: 2.h),
                  Row(
                    children: [
                      Text(
                        device.address,
                        style: TextStyle(
                          color: AppColors.textHint,
                          fontSize: 10.sp,
                        ),
                      ),
                      Text(
                        '  ·  $statusText',
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 10.sp,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(width: 10.w),
            trailingWidget,
            if (device.isSelected && onClear != null && !isConnecting) ...[
              SizedBox(width: 8.w),
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close_rounded,
                    color: AppColors.textSecondary, size: 16.sp),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
