import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../data/models/studio_models.dart';
import '../data/services/api_service.dart';
import '../data/services/api_client.dart';

enum StudioStatus {
  idle,
  loadingData,
  loadingPreview,
  loadingOrder,
  success,
  error
}

class StudioProvider extends ChangeNotifier {
  // ── Dedicated preview player (separate from main audio system) ─────────────
  final AudioPlayer _previewPlayer = AudioPlayer();

  // ── State ──────────────────────────────────────────────────────────────────
  StudioStatus _status = StudioStatus.idle;
  String? _errorMessage;

  StudioData? _studioData;
  VoiceTemplate? _selectedTemplate;
  VoiceSample? _selectedVoice;
  BackgroundMusic? _selectedBgMusic;
  SignalSound? _selectedSignalSound;

  double _bgMusicVolume = 0.5;
  double _voiceSpeed = 1.0;
  double _voiceDelay = 1.5;

  StudioPreviewResponse? _previewResponse;
  StudioOrderResponse? _orderResponse;

  // Preview playback state
  bool _isPreviewPlaying = false;
  String? _playingUrl;

  // Auto-fill text (populated from server, used to initialise TextControllers)
  String initialName = '';
  String initialPlate = '';
  String initialCar = '';

  StudioProvider() {
    _previewPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _isPreviewPlaying = false;
        _playingUrl = null;
        notifyListeners();
      } else if (state.playing != _isPreviewPlaying) {
        // Sync state if it changed externally or loaded
        _isPreviewPlaying = state.playing;
        notifyListeners();
      }
    });
  }

  // ── Getters ────────────────────────────────────────────────────────────────
  StudioStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isLoadingData => _status == StudioStatus.loadingData;
  bool get isLoadingPreview => _status == StudioStatus.loadingPreview;
  bool get isLoadingOrder => _status == StudioStatus.loadingOrder;
  bool get isPreviewPlaying => _isPreviewPlaying;
  String? get playingUrl => _playingUrl;

  StudioData? get studioData => _studioData;
  VoiceTemplate? get selectedTemplate => _selectedTemplate;
  VoiceSample? get selectedVoice => _selectedVoice;
  BackgroundMusic? get selectedBgMusic => _selectedBgMusic;
  SignalSound? get selectedSignalSound => _selectedSignalSound;

  double get bgMusicVolume => _bgMusicVolume;
  double get voiceSpeed => _voiceSpeed;
  double get voiceDelay => _voiceDelay;

  StudioPreviewResponse? get previewResponse => _previewResponse;
  StudioOrderResponse? get orderResponse => _orderResponse;

  bool get canOrder => _previewResponse != null;
  bool get hasData => _studioData != null;

  List<VoiceTemplate> get templates => _studioData?.templates ?? [];
  List<VoiceSample> get voiceSamples => _studioData?.voiceSamples ?? [];
  List<BackgroundMusic> get backgroundMusics =>
      _studioData?.backgroundMusics ?? [];
  List<SignalSound> get signalSounds => _studioData?.signalSounds ?? [];

  // ── Preview Playback ───────────────────────────────────────────────────────

  Future<String?> playPreviewUrl(String url) async {
    if (url.isEmpty) return 'URL trống, không thể phát';

    // 1. Eager UI update for instant feedback
    _playingUrl = url;
    _isPreviewPlaying = true;
    notifyListeners();

    try {
      // 2. Stop current audio if any, but don't block
      await _previewPlayer.stop();

      // 3. Immediately set state to play so it plays as soon as it's buffered
      _previewPlayer.play();

      // 4. Set the new URL
      await _previewPlayer.setUrl(url);

      return null;
    } catch (e) {
      // Revert eager update on failure if the user hasn't already clicked another url
      if (_playingUrl == url) {
        _isPreviewPlaying = false;
        _playingUrl = null;
        notifyListeners();
      }
      return 'Không thể phát: ${ApiClient.formatError(e)}';
    }
  }

  void stopPreview() {
    // Eagerly stop UI
    _isPreviewPlaying = false;
    _playingUrl = null;
    notifyListeners();

    // Stop player in background
    _previewPlayer.stop();
  }

  bool isPlayingUrl(String url) => _isPreviewPlaying && _playingUrl == url;

  // ── Data Loading ───────────────────────────────────────────────────────────

  Future<void> loadStudioData() async {
    _status = StudioStatus.loadingData;
    _errorMessage = null;
    notifyListeners();

    try {
      final raw = await ApiService.instance.getStudioTemplates();
      _studioData = StudioData.fromJson(raw);

      if (_studioData!.templates.isNotEmpty) {
        _selectedTemplate = _studioData!.templates.first;
      }
      if (_studioData!.voiceSamples.isNotEmpty) {
        _selectedVoice = _studioData!.voiceSamples.first;
      }
      if (_studioData!.backgroundMusics.isNotEmpty) {
        _selectedBgMusic = _studioData!.backgroundMusics.firstWhere(
          (e) => e.isDefault,
          orElse: () => _studioData!.backgroundMusics.first,
        );
      }
      if (_studioData!.signalSounds.isNotEmpty) {
        _selectedSignalSound = _studioData!.signalSounds.firstWhere(
          (e) => e.isDefault,
          orElse: () => _studioData!.signalSounds.first,
        );
      }

      final v = _studioData!.currentVehicle;
      initialName = v['customer_name'] ?? '';
      initialPlate = v['plate_number'] ?? '';
      initialCar = v['vehicle_model'] ?? '';

      _status = StudioStatus.success;
    } catch (e) {
      _status = StudioStatus.error;
      _errorMessage = ApiClient.formatError(e);
    }
    notifyListeners();
  }

  // ── Generate Preview (AI mix) ──────────────────────────────────────────────

  /// Returns null on success (and starts playing preview). Returns error string on failure.
  Future<String?> generateMix({
    required String customerName,
    required String plateNumber,
    required String vehicleModel,
  }) async {
    if (_selectedTemplate == null || _selectedVoice == null) {
      return 'Vui lòng chọn mẫu và giọng đọc';
    }

    _status = StudioStatus.loadingPreview;
    _errorMessage = null;
    notifyListeners();

    try {
      final params = {
        'customer_name': customerName,
        'plate_number': plateNumber,
        'vehicle_model': vehicleModel,
        'voice_template_id': _selectedTemplate!.id,
        'voice_sample_id': _selectedVoice!.id,
        'background_music_id': _selectedBgMusic?.id,
        'signal_sound_id': _selectedSignalSound?.id,
        'bg1_volume': _bgMusicVolume,
        'voice_speed': _voiceSpeed,
        'voice_delay': _voiceDelay,
      };

      final res = await ApiService.instance.previewVoice(params);
      _previewResponse = StudioPreviewResponse.fromJson(res);
      _status = StudioStatus.success;
      notifyListeners();

      // Auto-play the result
      await playPreviewUrl(_previewResponse!.previewUrl);
      return null;
    } catch (e) {
      _status = StudioStatus.error;
      _errorMessage = ApiClient.formatError(e);
      notifyListeners();
      return _errorMessage;
    }
  }

  // ── Create Order ───────────────────────────────────────────────────────────

  Future<StudioOrderResponse?> createOrder({
    required String customerName,
    required String plateNumber,
    required String vehicleModel,
  }) async {
    if (_previewResponse == null) return null;

    _status = StudioStatus.loadingOrder;
    _errorMessage = null;
    notifyListeners();

    try {
      final params = {
        'customer_name': customerName,
        'plate_number': plateNumber,
        'vehicle_model': vehicleModel,
        'voice_template_id': _selectedTemplate!.id,
        'voice_sample_id': _selectedVoice!.id,
        'background_music_id': _selectedBgMusic?.id,
        'signal_sound_id': _selectedSignalSound?.id,
        'bg1_volume': _bgMusicVolume,
        'voice_speed': _voiceSpeed,
        'voice_delay': _voiceDelay,
        'draft_audio_url': _previewResponse!.previewUrl,
      };

      final res = await ApiService.instance.createOrder(params);
      _orderResponse = StudioOrderResponse.fromJson(res);
      _status = StudioStatus.success;
      notifyListeners();
      return _orderResponse;
    } catch (e) {
      _status = StudioStatus.error;
      _errorMessage = ApiClient.formatError(e);
      notifyListeners();
      return null;
    }
  }

  // ── Gửi lên hệ thống (Order → Recreate) ─────────────────────────────────────

  /// Gửi lời chào vừa nghe thử lên hệ thống.
  ///
  /// Luồng: tạo đơn (POST /orders) để lấy `order_id` trong response, rồi gọi ngay
  /// recreate (POST /orders/{order_id}/recreate) với cùng cấu hình. Không hiển thị
  /// thanh toán/giá — chỉ báo thành công/thất bại.
  ///
  /// Trả về `null` nếu thành công, hoặc chuỗi lỗi nếu thất bại.
  Future<String?> submitToSystem({
    required String customerName,
    required String plateNumber,
    required String vehicleModel,
  }) async {
    if (_previewResponse == null) {
      return 'Vui lòng nhấn Nghe thử trước khi gửi';
    }

    _status = StudioStatus.loadingOrder;
    _errorMessage = null;
    notifyListeners();

    try {
      final params = {
        'customer_name': customerName,
        'plate_number': plateNumber,
        'vehicle_model': vehicleModel,
        'voice_template_id': _selectedTemplate!.id,
        'voice_sample_id': _selectedVoice!.id,
        'background_music_id': _selectedBgMusic?.id,
        'signal_sound_id': _selectedSignalSound?.id,
        'bg1_volume': _bgMusicVolume,
        'voice_speed': _voiceSpeed,
        'voice_delay': _voiceDelay,
        'draft_audio_url': _previewResponse!.previewUrl,
      };

      // 1. Tạo đơn để lấy order_id từ response.
      final orderRaw = await ApiService.instance.createOrder(params);
      final order = StudioOrderResponse.fromJson(orderRaw);
      _orderResponse = order;

      // 2. Gửi lên hệ thống qua recreate với order_id vừa nhận (không quan tâm
      //    nội dung response/giá tiền trả về).
      if (order.orderId > 0) {
        await ApiService.instance
            .recreateOrder(order.orderId.toString(), params);
      }

      _status = StudioStatus.success;
      notifyListeners();
      return null;
    } catch (e) {
      _status = StudioStatus.error;
      _errorMessage = ApiClient.formatError(e);
      notifyListeners();
      return _errorMessage;
    }
  }

  // ── Selection Setters ──────────────────────────────────────────────────────

  void selectTemplate(VoiceTemplate t) {
    _selectedTemplate = t;
    _previewResponse = null;
    notifyListeners();
  }

  void selectVoice(VoiceSample v) {
    _selectedVoice = v;
    _previewResponse = null;
    notifyListeners();
  }

  void selectBgMusic(BackgroundMusic? m) {
    _selectedBgMusic = m;
    _previewResponse = null;
    notifyListeners();
  }

  void selectSignalSound(SignalSound? s) {
    _selectedSignalSound = s;
    _previewResponse = null;
    notifyListeners();
  }

  void setBgMusicVolume(double v) {
    _bgMusicVolume = v;
    notifyListeners();
  }

  void setVoiceSpeed(double v) {
    _voiceSpeed = v;
    notifyListeners();
  }

  void setVoiceDelay(double v) {
    _voiceDelay = v;
    notifyListeners();
  }

  // ── Reset ──────────────────────────────────────────────────────────────────

  Future<void> reset() async {
    await _previewPlayer.stop();
    _studioData = null;
    _selectedTemplate = null;
    _selectedVoice = null;
    _selectedBgMusic = null;
    _selectedSignalSound = null;
    _previewResponse = null;
    _orderResponse = null;
    _bgMusicVolume = 0.5;
    _voiceSpeed = 1.0;
    _voiceDelay = 1.5;
    _status = StudioStatus.idle;
    _errorMessage = null;
    _isPreviewPlaying = false;
    _playingUrl = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _previewPlayer.dispose();
    super.dispose();
  }
}
