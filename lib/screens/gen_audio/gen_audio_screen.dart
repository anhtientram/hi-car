import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_colors.dart';
import '../../core/utils/ui_utils.dart';
import '../../providers/studio_provider.dart';
import '../../data/models/studio_models.dart';
import '../../widgets/premium_loading.dart';

class GenAudioScreen extends StatefulWidget {
  const GenAudioScreen({super.key});

  @override
  State<GenAudioScreen> createState() => _GenAudioScreenState();
}

class _GenAudioScreenState extends State<GenAudioScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _licensePlateController = TextEditingController();
  final _carBrandController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initStudio());
  }

  Future<void> _initStudio() async {
    final studio = context.read<StudioProvider>();
    await studio.reset();
    await studio.loadStudioData();
    if (!mounted) return;
    _nameController.text = studio.initialName;
    _licensePlateController.text = studio.initialPlate;
    _carBrandController.text = studio.initialCar;
    if (studio.status == StudioStatus.error) {
      UiUtils.showError(context, 'Lỗi tải Studio: ${studio.errorMessage}');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _licensePlateController.dispose();
    _carBrandController.dispose();
    super.dispose();
  }

  // ── Playback helpers ───────────────────────────────────────────────────────

  Future<void> _togglePlay(String url, String label) async {
    final studio = context.read<StudioProvider>();
    if (studio.isPlayingUrl(url)) {
      studio.stopPreview();
    } else {
      final err = await studio.playPreviewUrl(url);
      if (err != null && mounted) {
        UiUtils.showError(context, 'Không thể phát "$label": $err');
      }
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _generateMix() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final studio = context.read<StudioProvider>();
    final err = await studio.generateMix(
      customerName: _nameController.text.trim(),
      plateNumber: _licensePlateController.text.trim(),
      vehicleModel: _carBrandController.text.trim(),
    );
    if (!mounted) return;
    if (err == null) {
      UiUtils.showSuccess(context, 'Tạo bản nghe thử thành công!');
    } else {
      UiUtils.showError(context, 'Lỗi Preview: $err');
    }
  }

  Future<void> _submitToSystem() async {
    final studio = context.read<StudioProvider>();
    if (!studio.canOrder) {
      UiUtils.showError(context, 'Vui lòng nhấn Nghe thử trước khi gửi');
      return;
    }
    final err = await studio.submitToSystem(
      customerName: _nameController.text.trim(),
      plateNumber: _licensePlateController.text.trim(),
      vehicleModel: _carBrandController.text.trim(),
    );
    if (!mounted) return;
    if (err == null) {
      UiUtils.showSuccess(context, 'Đã gửi lời chào lên hệ thống!');
    } else {
      UiUtils.showError(context, 'Lỗi gửi hệ thống: $err');
    }
  }

  // ⚠️ TUÂN THỦ CHÍNH SÁCH STORE (Apple 3.1.1 / Google Play Payments):
  //    Không được bán nội dung số (file lời chào) bằng cổng thanh toán ngoài
  //    (VietQR/chuyển khoản) ngay trong app. Việc mua bán được xử lý bên ngoài
  //    qua admin. Toàn bộ luồng đặt mua + thanh toán bên dưới được tạm ẩn để
  //    nộp lên CH Play / App Store. Logic backend (createOrder) vẫn còn nguyên,
  //    chỉ ẩn UI ở client. Bỏ comment nếu phát hành ngoài store.
  /*
  Future<void> _submitOrder() async {
    final studio = context.read<StudioProvider>();
    if (!studio.canOrder) {
      UiUtils.showError(context, 'Vui lòng nhấn Nghe thử trước khi đặt mua');
      return;
    }
    final order = await studio.createOrder(
      customerName: _nameController.text.trim(),
      plateNumber: _licensePlateController.text.trim(),
      vehicleModel: _carBrandController.text.trim(),
    );
    if (!mounted) return;
    if (order != null) {
      _showPaymentDialog(order);
    } else {
      UiUtils.showError(context, 'Lỗi đặt hàng: ${studio.errorMessage}');
    }
  }

  void _showPaymentDialog(StudioOrderResponse order) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardElevated,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
        title: Text('Thanh Toán Đơn Hàng',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Mã đơn: ${order.orderCode}',
                style: TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.bold)),
            SizedBox(height: 16.h),
            ClipRRect(
              borderRadius: BorderRadius.circular(12.r),
              child: Image.network(
                order.paymentQrUrl,
                width: 200.w,
                height: 200.w,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(Icons.qr_code_2_rounded,
                    size: 100.sp, color: AppColors.textHint),
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              'Quét mã VietQR để thanh toán 50.000đ.\nĐơn hàng sẽ được duyệt tự động sau khi nhận tiền.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11.sp),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Đóng', style: TextStyle(color: AppColors.textHint)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Tôi đã thanh toán'),
          ),
        ],
      ),
    );
  }
  */

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer<StudioProvider>(
      builder: (context, studio, _) {
        if (studio.isLoadingData) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const PremiumLoading(size: 36),
                  SizedBox(height: 16.h),
                  Text('Đang khởi tạo Studio...',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13.sp)),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded),
              onPressed: () {
                studio.stopPreview();
                context.pop();
              },
            ),
            title: Text('Studio Lời Chào AI',
                style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
            centerTitle: true,
            // Global stop button when something is playing
            actions: [
              if (studio.isPreviewPlaying)
                IconButton(
                  icon: Container(
                    padding: EdgeInsets.all(6.w),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: const Icon(Icons.stop_rounded,
                        color: AppColors.primary),
                  ),
                  onPressed: studio.stopPreview,
                  tooltip: 'Dừng phát',
                ),
            ],
          ),
          body: SafeArea(
            child: OrientationBuilder(
              builder: (context, orientation) =>
                  orientation == Orientation.landscape
                      ? _buildLandscapeLayout(studio)
                      : _buildPortraitLayout(studio),
            ),
          ),
        );
      },
    );
  }

  // ── Layouts ────────────────────────────────────────────────────────────────

  Widget _buildPortraitLayout(StudioProvider studio) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeading('1. CHỌN MẪU LỜI CHÀO'),
            _buildTemplateCarousel(studio),
            SizedBox(height: 24.h),
            _buildHeading('2. THÔNG TIN CÁ NHÂN'),
            _buildPersonalFields(),
            SizedBox(height: 24.h),
            _buildHeading('3. STUDIO MIXER'),
            _buildMixerPanel(studio),
            SizedBox(height: 32.h),
            _buildActionButtons(studio),
            SizedBox(height: 40.h),
          ],
        ),
      ),
    );
  }

  Widget _buildLandscapeLayout(StudioProvider studio) {
    return Form(
      key: _formKey,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              padding: EdgeInsets.all(20.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeading('1. CHỌN MẪU LỜI CHÀO'),
                  _buildTemplateCarousel(studio, isLandscape: true),
                  SizedBox(height: 20.h),
                  _buildHeading('2. THÔNG TIN CÁ NHÂN'),
                  _buildPersonalFields(),
                ],
              ),
            ),
          ),
          VerticalDivider(
              width: 1, thickness: 1, color: AppColors.border.withOpacity(0.1)),
          Expanded(
            flex: 4,
            child: SingleChildScrollView(
              padding: EdgeInsets.all(20.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeading('3. STUDIO MIXER'),
                  _buildMixerPanel(studio),
                  SizedBox(height: 24.h),
                  _buildActionButtons(studio),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Heading helpers ────────────────────────────────────────────────────────

  Widget _buildHeading(String title) {
    return Padding(
      padding: EdgeInsets.only(bottom: 14.h),
      child: Row(
        children: [
          Container(
            width: 4.w,
            height: 14.h,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2.r),
            ),
          ),
          SizedBox(width: 8.w),
          Text(title,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12.sp,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              )),
        ],
      ),
    );
  }

  Widget _buildSubLabel(String title) => Padding(
        padding: EdgeInsets.only(bottom: 8.h),
        child: Text(title,
            style: TextStyle(
                color: AppColors.textHint,
                fontSize: 10.sp,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1)),
      );

  // ── Template Carousel (IMPROVED) ──────────────────────────────────────────

  Widget _buildTemplateCarousel(StudioProvider studio,
      {bool isLandscape = false}) {
    final templates = studio.templates;
    if (templates.isEmpty) {
      return Container(
        height: 140.h,
        alignment: Alignment.center,
        child: Text('Không có mẫu nào',
            style: TextStyle(color: AppColors.textHint, fontSize: 12.sp)),
      );
    }

    return SizedBox(
      height: isLandscape ? 120.h : 140.h,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: templates.length,
        itemBuilder: (context, index) {
          final item = templates[index];
          final isSelected = studio.selectedTemplate?.id == item.id;

          return GestureDetector(
            onTap: () => context.read<StudioProvider>().selectTemplate(item),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              width: isLandscape ? 145.w : 165.w,
              margin: EdgeInsets.only(right: 12.w, bottom: 4.h),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.primary.withOpacity(0.18),
                          AppColors.primary.withOpacity(0.04),
                        ],
                      )
                    : null,
                color: isSelected ? null : AppColors.card,
                borderRadius: BorderRadius.circular(18.r),
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.border,
                  width: isSelected ? 1.5 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                            color: AppColors.primary.withOpacity(0.12),
                            blurRadius: 12,
                            offset: const Offset(0, 4))
                      ]
                    : null,
              ),
              child: Padding(
                padding: EdgeInsets.all(14.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top: badge only (mẫu chỉ xem / chọn, không phát preview)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 7.w, vertical: 3.h),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.border.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(6.r),
                          ),
                          child: Text(
                            'Mẫu ${index + 1}',
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : AppColors.textSecondary,
                              fontSize: 9.sp,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Icon(Icons.check_circle_rounded,
                              color: AppColors.primary, size: 18.sp),
                      ],
                    ),

                    const Spacer(),

                    // Template name
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),

                    SizedBox(height: 6.h),

                    // Bottom: selected check
                    Row(
                      children: [
                        Icon(
                          isSelected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 14.sp,
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.textHint,
                        ),
                        SizedBox(width: 4.w),
                        Text(
                          isSelected ? 'Đang chọn' : 'Chọn mẫu',
                          style: TextStyle(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.textHint,
                            fontSize: 10.sp,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Personal Fields ───────────────────────────────────────────────────────

  Widget _buildPersonalFields() {
    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          _PremiumField(
            label: 'Danh xưng / Tên chủ xe',
            controller: _nameController,
            hint: 'ví dụ: Giám Đốc, Anh Hải...',
            icon: Icons.person_rounded,
          ),
          SizedBox(height: 16.h),
          _PremiumField(
            label: 'Biển số xe',
            controller: _licensePlateController,
            hint: 'ví dụ: 51A-123.45',
            icon: Icons.tag_rounded,
          ),
          SizedBox(height: 16.h),
          _PremiumField(
            label: 'Dòng xe / Hiệu xe',
            controller: _carBrandController,
            hint: 'ví dụ: Mercedes S450, Lexus LS...',
            icon: Icons.directions_car_filled_rounded,
          ),
        ],
      ),
    );
  }

  // ── Mixer Panel ───────────────────────────────────────────────────────────

  Widget _buildMixerPanel(StudioProvider studio) {
    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSubLabel('GIỌNG ĐỌC AI'),
          _buildVoiceChips(studio),
          SizedBox(height: 20.h),
          _buildSubLabel('NHẠC NỀN'),
          _buildDropdownRow<BackgroundMusic>(
            value: studio.selectedBgMusic,
            items: studio.backgroundMusics,
            itemLabel: (m) => m.name,
            onChanged: context.read<StudioProvider>().selectBgMusic,
          ),
          SizedBox(height: 14.h),
          _buildSubLabel('ÂM HIỆU / CHUÔNG'),
          _buildDropdownRow<SignalSound>(
            value: studio.selectedSignalSound,
            items: studio.signalSounds,
            itemLabel: (s) => s.name,
            onChanged: context.read<StudioProvider>().selectSignalSound,
          ),
          SizedBox(height: 24.h),
          _buildSubLabel('MIXER'),
          _SexySlider(
            label: 'Âm lượng nhạc',
            value: studio.bgMusicVolume,
            onChanged: context.read<StudioProvider>().setBgMusicVolume,
          ),
          SizedBox(height: 10.h),
          _SexySlider(
            label: 'Tốc độ giọng',
            value: (studio.voiceSpeed - 0.5) / 1.5,
            labelDisplay: '${studio.voiceSpeed.toStringAsFixed(1)}x',
            onChanged: (v) =>
                context.read<StudioProvider>().setVoiceSpeed(0.5 + v * 1.5),
          ),
          SizedBox(height: 10.h),
          _SexySlider(
            label: 'Độ trễ bắt đầu',
            value: studio.voiceDelay / 10.0,
            labelDisplay: '${studio.voiceDelay.toStringAsFixed(1)}s',
            onChanged: (v) =>
                context.read<StudioProvider>().setVoiceDelay(v * 10.0),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceChips(StudioProvider studio) {
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children: studio.voiceSamples.map((v) {
        final isSelected = studio.selectedVoice?.id == v.id;

        return GestureDetector(
          onTap: () => context.read<StudioProvider>().selectVoice(v),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary : AppColors.cardElevated,
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  v.gender == 'female'
                      ? Icons.female_rounded
                      : Icons.male_rounded,
                  size: 13.sp,
                  color: isSelected
                      ? Colors.white.withOpacity(0.8)
                      : AppColors.textHint,
                ),
                SizedBox(width: 4.w),
                Text(v.name,
                    style: TextStyle(
                      color:
                          isSelected ? Colors.white : AppColors.textSecondary,
                      fontSize: 12.sp,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    )),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDropdownRow<T>({
    required T? value,
    required List<T> items,
    required String Function(T) itemLabel,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      height: 48.h,
      padding: EdgeInsets.symmetric(horizontal: 14.w),
      decoration: BoxDecoration(
        color: AppColors.cardElevated.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.cardElevated,
          style: TextStyle(
              fontSize: 12.sp,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500),
          items: items
              .map((e) => DropdownMenuItem<T>(
                    value: e,
                    child: Text(itemLabel(e), overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ── Action Buttons ────────────────────────────────────────────────────────

  Widget _buildActionButtons(StudioProvider studio) {
    return Column(
      children: [
        // Generate preview button
        _ScaleButton(
          onTap: studio.isLoadingPreview ? null : _generateMix,
          child: Container(
            width: double.infinity,
            height: 56.h,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6C63FF), Color(0xFF4A90E2)],
              ),
              borderRadius: BorderRadius.circular(16.r),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF6C63FF).withOpacity(0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 6)),
              ],
            ),
            child: Center(
              child: studio.isLoadingPreview
                  ? const PremiumLoading(size: 22, color: Colors.white, strokeWidth: 2.5)
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.auto_awesome_rounded,
                            color: Colors.white, size: 20),
                        SizedBox(width: 10.w),
                        Text('TẠO BẢN NGHE THỬ AI',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 14.sp,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8)),
                      ],
                    ),
            ),
          ),
        ),

        // Play/stop the last preview
        if (studio.previewResponse != null) ...[
          SizedBox(height: 12.h),
          Builder(builder: (context) {
            final previewUrl = studio.previewResponse!.previewUrl;
            final isPlaying = studio.isPlayingUrl(previewUrl);

            return AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: isPlaying
                    ? AppColors.primary.withOpacity(0.12)
                    : AppColors.cardElevated.withOpacity(0.45),
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(
                  color: isPlaying ? AppColors.primary : AppColors.border,
                  width: isPlaying ? 1.5 : 1,
                ),
                boxShadow: isPlaying
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.18),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        )
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 40.w,
                    height: 40.w,
                    decoration: BoxDecoration(
                      color: isPlaying
                          ? AppColors.primary
                          : AppColors.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Icon(
                      isPlaying
                          ? Icons.graphic_eq_rounded
                          : Icons.headphones_rounded,
                      color: isPlaying ? Colors.white : AppColors.primary,
                      size: 20.sp,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isPlaying ? 'Đang phát bản mix' : 'Bản nghe thử AI',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          isPlaying
                              ? 'Nhấn Dừng để tắt preview'
                              : 'Nghe lại trước khi gửi lên hệ thống',
                          style: TextStyle(
                            color: isPlaying
                                ? AppColors.primary
                                : AppColors.textHint,
                            fontSize: 10.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _togglePlay(previewUrl, 'Bản nghe thử'),
                      borderRadius: BorderRadius.circular(12.r),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: EdgeInsets.symmetric(
                            horizontal: 14.w, vertical: 10.h),
                        decoration: BoxDecoration(
                          color: isPlaying
                              ? AppColors.error
                              : AppColors.primary,
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isPlaying
                                  ? Icons.stop_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 18.sp,
                            ),
                            SizedBox(width: 4.w),
                            Text(
                              isPlaying ? 'Dừng' : 'Nghe thử',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],

        // Gửi lời chào lên hệ thống (tạo đơn → recreate). Fire-and-forget, không hiện giá.
        if (studio.canOrder) ...[
          SizedBox(height: 12.h),
          _ScaleButton(
            onTap: studio.isLoadingOrder ? null : _submitToSystem,
            child: Container(
              width: double.infinity,
              height: 56.h,
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(color: AppColors.success, width: 1.5),
              ),
              child: Center(
                child: studio.isLoadingOrder
                    ? const PremiumLoading(
                        size: 22, color: AppColors.success, strokeWidth: 2.5)
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_upload_rounded,
                              color: AppColors.success),
                          SizedBox(width: 10.w),
                          Text('GỬI LÊN HỆ THỐNG',
                              style: TextStyle(
                                  color: AppColors.success,
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8)),
                        ],
                      ),
              ),
            ),
          ),
        ],

        // ⚠️ TUÂN THỦ CHÍNH SÁCH STORE: nút "Đặt mua" + thanh toán VietQR bị ẩn
        //    cho bản phát hành CH Play / App Store (cấm bán nội dung số qua cổng
        //    ngoài). Khách mua qua admin; admin gán file vào tài khoản. Bỏ comment
        //    nếu phát hành ngoài store.
        /*
        // Order button (only when preview exists)
        if (studio.canOrder) ...[
          SizedBox(height: 12.h),
          _ScaleButton(
            onTap: studio.isLoadingOrder ? null : _submitOrder,
            child: Container(
              width: double.infinity,
              height: 56.h,
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(color: AppColors.success, width: 1.5),
              ),
              child: Center(
                child: studio.isLoadingOrder
                    ? const PremiumLoading(
                        size: 22, color: AppColors.success, strokeWidth: 2.5)
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.verified_rounded,
                              color: AppColors.success),
                          SizedBox(width: 10.w),
                          Text('ĐẶT MUA LỜI CHÀO NÀY',
                              style: TextStyle(
                                  color: AppColors.success,
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
              ),
            ),
          ),
        ],
        */
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Private sub-widgets
// ═══════════════════════════════════════════════════════════════════════════

class _PremiumField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final IconData icon;

  const _PremiumField({
    required this.label,
    required this.controller,
    required this.hint,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: AppColors.textHint,
                fontSize: 10.sp,
                fontWeight: FontWeight.w700)),
        SizedBox(height: 8.h),
        TextFormField(
          controller: controller,
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13.sp,
              fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
                color: AppColors.textHint, fontWeight: FontWeight.normal),
            prefixIcon: Icon(icon, size: 18.sp, color: AppColors.primary),
            filled: true,
            fillColor: AppColors.cardElevated.withOpacity(0.3),
            contentPadding:
                EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14.r),
                borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14.r),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14.r),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.2)),
          ),
          validator: (v) => (v?.trim().isEmpty ?? true)
              ? 'Vui lòng cung cấp thông tin'
              : null,
        ),
      ],
    );
  }
}

class _SexySlider extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final String? labelDisplay;

  const _SexySlider({
    required this.label,
    required this.value,
    required this.onChanged,
    this.labelDisplay,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 11.sp)),
            Text(labelDisplay ?? '${(value * 100).toInt()}%',
                style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 11.sp,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 2.5.h,
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6.r),
            overlayShape: RoundSliderOverlayShape(overlayRadius: 16.r),
            activeTrackColor: AppColors.primary,
            inactiveTrackColor: AppColors.border,
            thumbColor: AppColors.primary,
          ),
          child: Slider(value: value.clamp(0.0, 1.0), onChanged: onChanged),
        ),
      ],
    );
  }
}

class _ScaleButton extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;
  const _ScaleButton({required this.child, this.onTap});

  @override
  State<_ScaleButton> createState() => _ScaleButtonState();
}

class _ScaleButtonState extends State<_ScaleButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween<double>(begin: 1.0, end: 0.96)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap != null ? (_) => _ctrl.forward() : null,
      onTapUp: widget.onTap != null
          ? (_) {
              _ctrl.reverse();
              widget.onTap!();
            }
          : null,
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}
