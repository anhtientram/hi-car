import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/audio_model.dart';
import '../data/repositories/audio_repository.dart';
import '../data/services/sync_service.dart';
import '../data/services/api_client.dart';
import '../native/service_channel.dart';
import '../core/constants.dart';
import '../core/logger.dart';

enum SyncStatus { idle, syncing, success, error }

class AudioProvider extends ChangeNotifier {
  final _player = AudioPlayer();

  List<AudioModel> _audioList = [];
  AudioModel? _currentlyPlaying;
  bool _isPlaying = false;
  SyncStatus _syncStatus = SyncStatus.idle;
  String _syncMessage = '';
  double _syncProgress = 0;
  String? _syncError;
  DateTime? _lastSyncTime;
  bool _isBetaMode = false;
  String? _activeGreetingId;
  String? _activeGoodbyeId;
  bool _isNativeGreetingPlaying = false;
  bool _isNativeGoodbyePlaying = false;
  void Function(bool isManual)?
      onNativePlaybackComplete; // Callback for UI to react
  Timer? _playbackWatchdog;

  // 🟢 Chặn kích hoạt phát chồng lấn trong khoảng thời gian khởi động (boot + mở app +
  //    resume có thể gọi gần như đồng thời). Tránh ngắt/phát lại từ đầu.
  bool _isStartingPlayback = false;

  String? get _effectiveGoodbyeId =>
      (_activeGoodbyeId == null || _activeGoodbyeId!.isEmpty)
          ? AppConstants.defaultGoodbyeId
          : _activeGoodbyeId;

  AudioModel _buildDefaultGoodbyeAudio() {
    return AudioModel(
      id: AppConstants.defaultGoodbyeId,
      title: 'Lời tạm biệt mặc định',
      type: AudioType.goodbye,
      remoteUrl: '',
      assetPath: AppConstants.defaultGoodbyeAsset,
      description: 'Nhạc có sẵn trong app',
      isActiveGoodbye: _effectiveGoodbyeId == AppConstants.defaultGoodbyeId,
    );
  }

  List<AudioModel> get audioList {
    final mappedList =
        _audioList.where((a) => a.id != AppConstants.defaultGoodbyeId).map((a) {
      return a.copyWith(
        isActiveGreeting: _activeGreetingId == a.id,
        isActiveGoodbye: _effectiveGoodbyeId == a.id,
      );
    }).toList();

    final defaultGoodbye = _buildDefaultGoodbyeAudio();

    if (!_isBetaMode) return [defaultGoodbye, ...mappedList];

    final demoAudio = AudioModel(
      id: 'demo_default',
      title: 'Giọng Mặc Định (Demo)',
      type: AudioType.custom,
      remoteUrl: '',
      assetPath: AppConstants.defaultAudioAsset,
      description: 'Lấy từ bộ nhớ máy (Không cần mạng)',
      isActiveGreeting: _activeGreetingId == 'demo_default',
      isActiveGoodbye: false,
    );

    return [demoAudio, defaultGoodbye, ...mappedList];
  }

  AudioModel? get currentlyPlaying => _currentlyPlaying;
  bool get isPlaying => _isPlaying;
  SyncStatus get syncStatus => _syncStatus;
  String get syncMessage => _syncMessage;
  double get syncProgress => _syncProgress;
  String? get syncError => _syncError;
  DateTime? get lastSyncTime => _lastSyncTime;
  bool get isSyncing => _syncStatus == SyncStatus.syncing;
  bool get isNativeGreetingPlaying => _isNativeGreetingPlaying;
  bool get isNativeGoodbyePlaying => _isNativeGoodbyePlaying;

  AudioModel? get activeGreeting =>
      audioList.where((a) => a.isActiveGreeting).firstOrNull;
  AudioModel get activeGoodbye {
    if (_effectiveGoodbyeId == AppConstants.defaultGoodbyeId) {
      return _buildDefaultGoodbyeAudio();
    }
    return audioList.firstWhere(
      (a) => a.isActiveGoodbye,
      orElse: () => _buildDefaultGoodbyeAudio(),
    );
  }

  Future<void> _ensureDefaultGoodbye() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getString(AppConstants.keyGoodbyeAudioId);
    if (current == null || current.isEmpty) {
      _activeGoodbyeId = AppConstants.defaultGoodbyeId;
      await prefs.setString(
          AppConstants.keyGoodbyeAudioId, AppConstants.defaultGoodbyeId);
    }
  }

  // ===== Init =====

  Future<void> init() async {
    _audioList = await AudioRepository.instance.loadLocalAudioList();

    final prefs = await SharedPreferences.getInstance();
    _isBetaMode = prefs.getBool('is_beta_mode') ?? false;
    _activeGreetingId = prefs.getString(AppConstants.keyGreetingAudioId);
    _activeGoodbyeId = prefs.getString(AppConstants.keyGoodbyeAudioId);
    await _ensureDefaultGoodbye();

    notifyListeners();

    // Initialize ServiceChannel listener
    ServiceChannel.instance.init();

    // Đảm bảo boot_greeting.mp3 luôn được cập nhật mỗi khi app khởi động.
    // Dùng Future.delayed để tránh MissingPluginException do plugin chưa attach xong
    // khi initState() chạy (race condition trong release mode).
    Future.delayed(const Duration(milliseconds: 800), () {
      _syncNativePaths().catchError((_) {});
      ServiceChannel.instance.syncPrefs().catchError((_) {});
      // Kéo lỗi native lúc boot (BootReceiver/Service chạy khi app chưa mở) vào danh sách
      // "Báo cáo lỗi" để hiện thẻ + gửi được bằng nút cũ, kể cả khi không có lỗi Flutter nào.
      ServiceChannel.instance.importNativeDiagnostics().catchError((_) {});
    });

    ServiceChannel.instance.onPlaybackComplete = () {
      debugPrint('🔔 [AudioProvider] NHẬN TÍN HIỆU: PHÁT XONG TỪ NATIVE');
      // Nếu là tự động phát xong (không phải bấm dừng thủ công)
      _stopNativePlaybackState(isManual: false);
    };

    ServiceChannel.instance.onPlaybackStarted = (type) {
      debugPrint(
          '🔔 [AudioProvider] NHẬN TÍN HIỆU: BẮT ĐẦU PHÁT TỪ NATIVE ($type)');
      _isNativeGreetingPlaying = type == 'greeting';
      _isNativeGoodbyePlaying = type == 'goodbye';
      notifyListeners();
    };

    // Auto-sync on startup if logged in
    if (prefs.containsKey('auth_token')) {
      syncFromServer();
    }
  }

  // ===== Storage & State Management =====

  /// Xoá cache danh sách audio.
  ///
  /// [keepActiveSelection] = true: GIỮ LẠI lựa chọn lời chào/tạm biệt đã setup
  /// (id + path + file boot) để sau khi đăng nhập lại 2 nút vẫn còn nhạc. Danh sách
  /// sẽ được nạp lại từ server và cờ active được khôi phục theo id đã lưu.
  Future<void> clearCache({bool keepActiveSelection = false}) async {
    _audioList = [];
    _currentlyPlaying = null;
    _isPlaying = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.keyAudioList);
    await prefs.remove('cached_audio_list');

    if (!keepActiveSelection) {
      _activeGreetingId = null;
      _activeGoodbyeId = AppConstants.defaultGoodbyeId;
      await prefs.remove(AppConstants.keyGreetingAudioId);
      await prefs.setString(
          AppConstants.keyGoodbyeAudioId, AppConstants.defaultGoodbyeId);
      await prefs.remove('greeting_audio_path');
      await prefs.remove('goodbye_audio_path');
    }

    notifyListeners();
  }

  // ===== Sync =====

  Future<void> syncFromServer() async {
    if (_syncStatus == SyncStatus.syncing) return;

    _syncStatus = SyncStatus.syncing;
    _syncError = null;
    _syncProgress = 0;
    notifyListeners();

    try {
      final updated = await AudioRepository.instance.syncFromServer(
        onProgress: (msg, progress) {
          _syncMessage = msg;
          _syncProgress = progress;
          notifyListeners();
        },
      );

      _audioList = updated;
      _lastSyncTime = DateTime.now();
      _syncStatus = SyncStatus.success;
      _syncMessage = 'Đồng bộ hoàn tất (${updated.length} file)';

      // 🟢 Khôi phục lựa chọn lời chào/tạm biệt đã setup từ prefs để 2 nút giữ nguyên
      //    cấu hình sau khi đăng nhập lại / đồng bộ.
      final prefs = await SharedPreferences.getInstance();
      _activeGreetingId = prefs.getString(AppConstants.keyGreetingAudioId);
      _activeGoodbyeId = prefs.getString(AppConstants.keyGoodbyeAudioId);
      await _ensureDefaultGoodbye();

      // Update native service
      await _syncNativePaths();
    } catch (e) {
      _syncStatus = SyncStatus.error;
      _syncError = ApiClient.formatError(e);
      _syncMessage = _syncError!;
      if (_audioList.isEmpty) {
        _audioList = await AudioRepository.instance.loadLocalAudioList();
      }
      AppLogger.instance.log(
        'Lỗi đồng bộ server: $e',
        type: 'sync_error',
        details: {'error': e.toString()},
      );
    }

    notifyListeners();
    Future.delayed(const Duration(seconds: 3), () {
      if (_syncStatus != SyncStatus.syncing) {
        _syncStatus = SyncStatus.idle;
        notifyListeners();
      }
    });
  }

  // ===== Actions =====

  Future<void> setAsGreeting(String audioId) async {
    _activeGreetingId = audioId;
    _audioList =
        await AudioRepository.instance.setGreetingAudio(audioId, _audioList);
    await _syncNativePaths();
    notifyListeners();
  }

  Future<void> setAsGoodbye(String audioId) async {
    _activeGoodbyeId = audioId;
    if (audioId == AppConstants.defaultGoodbyeId) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.keyGoodbyeAudioId, audioId);
      _audioList =
          _audioList.map((a) => a.copyWith(isActiveGoodbye: false)).toList();
      await AudioRepository.instance.saveLocalList(_audioList);
    } else {
      _audioList =
          await AudioRepository.instance.setGoodbyeAudio(audioId, _audioList);
    }
    await _syncNativePaths();
    notifyListeners();
  }

  /// Bỏ đặt làm lời chào (xoá khỏi cấu hình + vùng nhớ native + file boot).
  Future<void> unsetGreeting() async {
    _activeGreetingId = null;
    _audioList = await AudioRepository.instance.clearGreetingAudio(_audioList);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('greeting_audio_path');
    await ServiceChannel.instance.clearGreetingConfig();
    notifyListeners();
  }

  /// Bỏ đặt làm lời tạm biệt → quay về bản mặc định có sẵn trong app.
  Future<void> unsetGoodbye() async {
    if (_effectiveGoodbyeId == AppConstants.defaultGoodbyeId) return;
    await setAsGoodbye(AppConstants.defaultGoodbyeId);
  }

  // ===== Playback =====

  Future<void> playAudio(AudioModel audio) async {
    try {
      await _player.stop();

      if (audio.assetPath != null && audio.assetPath!.isNotEmpty) {
        await _player.setAsset(audio.assetPath!);
      } else if (audio.hasLocalFile &&
          audio.localPath != null &&
          await File(audio.localPath!).exists()) {
        await _player.setFilePath(audio.localPath!);
      } else {
        await _player.setUrl(audio.remoteUrl);
      }

      await _player.play();
      _currentlyPlaying = audio;
      _isPlaying = true;
      notifyListeners();

      _player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          _isPlaying = false;
          _currentlyPlaying = null;
          notifyListeners();
        }
      });
    } catch (e) {
      _isPlaying = false;
      _currentlyPlaying = null;
      AppLogger.instance.log(
        'Lỗi phát nhạc: ${audio.title}',
        type: 'playback_error',
        details: {'audioId': audio.id, 'error': e.toString()},
      );
      notifyListeners();
    }
  }

  Future<void> stopAudio() async {
    await _player.stop();
    _isPlaying = false;
    _currentlyPlaying = null;
    notifyListeners();
  }

  Future<bool> playGreetingViaNative({bool allowAutostartRetry = false}) async {
    // 🟢 Đang trong quá trình khởi động phát khác → bỏ qua để tránh phát chồng/ngắt.
    if (_isStartingPlayback) {
      debugPrint('AudioProvider: playGreeting bỏ qua (đang khởi động phát)');
      return false;
    }

    final audio = activeGreeting;
    String? path;

    if (audio != null) {
      path = await AudioRepository.instance.getGreetingAudioPath(audio);
    } else {
      // Fallback: audioList may not be loaded yet, read persisted path
      final prefs = await SharedPreferences.getInstance();
      path = prefs.getString('greeting_audio_path');
      debugPrint(
          'AudioProvider: No active greeting in list, fallback path=$path');
    }

    if (path == null || path.isEmpty) {
      debugPrint('AudioProvider: No active greeting found');
      final prefs = await SharedPreferences.getInstance();
      AppLogger.instance.log(
        'Không có file nhạc chào để phát',
        type: 'incident_error',
        userMessage:
            'Chưa có nhạc chào hợp lệ trên thiết bị. Hãy đồng bộ nhạc hoặc chọn lại nhạc chào.',
        requiresAction: true,
        details: {
          'mode': prefs.getString('connection_mode') ?? 'unknown',
        },
      );
      return false;
    }

    debugPrint('AudioProvider: playGreetingViaNative path=$path');

    _isStartingPlayback = true;
    try {
      // Trạng thái "đang phát" chỉ bật khi native gọi onPlaybackStarted — tránh UI ảo.
      _isNativeGoodbyePlaying = false;

      // Delay ngắn (~1.5s) cho BT/AA/Màn Độ để audio focus ổn định. Box boot do native xử lý riêng.
      final prefs = await SharedPreferences.getInstance();
      final mode = prefs.getString('connection_mode');
      if (mode != 'android_box_mode') {
        await Future.delayed(const Duration(milliseconds: 1500));
      }

      await ServiceChannel.instance.playGreeting(audioPath: path);
      _startWatchdog(audio?.durationSeconds ?? 15);
      return true;
    } catch (e) {
      debugPrint('AudioProvider: playGreetingViaNative error: $e');
      AppLogger.instance.log(
        'Lỗi phát lời chào (Native): $e',
        type: 'native_playback_error',
        userMessage:
            'Thiết bị không phát được nhạc chào. Hãy kiểm tra quyền âm thanh và kết nối xe.',
        requiresAction: true,
        details: {
          'path': path,
          'error': e.toString(),
          'mode': (await SharedPreferences.getInstance())
                  .getString('connection_mode') ??
              'unknown',
        },
      );
      _stopNativePlaybackState();
      if (allowAutostartRetry) {
        debugPrint('AudioProvider: autostart retry sau 15s...');
        await Future.delayed(const Duration(seconds: 15));
        return playGreetingViaNative(allowAutostartRetry: false);
      }
      return false;
    } finally {
      _isStartingPlayback = false;
    }
  }

  Future<bool> playGoodbyeViaNative() async {
    // 🟢 Đang trong quá trình khởi động phát khác → bỏ qua để tránh phát chồng/ngắt.
    if (_isStartingPlayback) {
      debugPrint('AudioProvider: playGoodbye bỏ qua (đang khởi động phát)');
      return false;
    }

    final audio = activeGoodbye;
    var path = await AudioRepository.instance.getGoodbyeAudioPath(audio);

    if (path == null || path.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      path = prefs.getString('goodbye_audio_path');
      debugPrint('AudioProvider: goodbye fallback path=$path');
    }

    if (path == null || path.isEmpty) {
      debugPrint('AudioProvider: No active goodbye found');
      final prefs = await SharedPreferences.getInstance();
      AppLogger.instance.log(
        'Không có file nhạc tạm biệt để phát',
        type: 'incident_error',
        userMessage: 'Chưa có file nhạc tạm biệt hợp lệ trên thiết bị.',
        requiresAction: true,
        details: {
          'mode': prefs.getString('connection_mode') ?? 'unknown',
        },
      );
      return false;
    }

    _isStartingPlayback = true;
    try {
      // Trạng thái "đang phát" chỉ bật khi native gọi onPlaybackStarted.
      _isNativeGreetingPlaying = false;

      // Add a small delay for non-box modes to ensure connection is stable and audio focus is granted
      final prefs = await SharedPreferences.getInstance();
      final mode = prefs.getString('connection_mode');
      if (mode != 'android_box_mode') {
        await Future.delayed(const Duration(milliseconds: 1500));
      }

      await ServiceChannel.instance.playGoodbye(audioPath: path);
      _startWatchdog(audio.durationSeconds > 0 ? audio.durationSeconds : 15);
      return true;
    } catch (e) {
      debugPrint('AudioProvider: playGoodbyeViaNative error: $e');
      AppLogger.instance.log(
        'Lỗi phát lời tạm biệt (Native): $e',
        type: 'native_playback_error',
        userMessage:
            'Thiết bị không phát được nhạc tạm biệt. Hãy kiểm tra kết nối xe.',
        requiresAction: true,
        details: {
          'path': path,
          'error': e.toString(),
          'mode': (await SharedPreferences.getInstance())
                  .getString('connection_mode') ??
              'unknown',
        },
      );
      _stopNativePlaybackState();
      return false;
    } finally {
      _isStartingPlayback = false;
    }
  }

  Future<void> stopNativeAudio({bool isManual = true}) async {
    try {
      debugPrint('AudioProvider: stopNativeAudio (isManual=$isManual)');
      _stopNativePlaybackState(isManual: isManual);
      await ServiceChannel.instance.stopAudio();
    } catch (e) {
      debugPrint('Native stopAudio error: $e');
      AppLogger.instance.log(
        'Lỗi dừng nhạc Native: $e',
        type: 'native_error',
        details: {'error': e.toString()},
      );
    }
  }

  void _startWatchdog(int durationSeconds) {
    _playbackWatchdog?.cancel();
    // Use duration + 5s buffer, or default 60s if duration is unknown/zero
    final timeout = (durationSeconds > 0) ? durationSeconds + 5 : 60;
    _playbackWatchdog = Timer(Duration(seconds: timeout), () {
      if (_isNativeGreetingPlaying || _isNativeGoodbyePlaying) {
        debugPrint(
            '⚠️ [AudioProvider] Watchdog triggered: Force stopping animation');
        AppLogger.instance.log(
          'Watchdog kích hoạt: Force stop animation (Native)',
          type: 'native_playback_error',
          userMessage:
              'Ứng dụng không nhận được tín hiệu phát nhạc hoàn tất từ thiết bị.',
          requiresAction: true,
        );
        _stopNativePlaybackState(isManual: false);
      }
    });
  }

  bool _isStoppingManually = false;

  void _stopNativePlaybackState({bool isManual = false}) {
    if (isManual) {
      _isStoppingManually = true;
      // Reset flag sau 2 giây để đón nhận các sự kiện tiếp theo
      Future.delayed(const Duration(seconds: 2), () {
        _isStoppingManually = false;
      });
    }

    _playbackWatchdog?.cancel();
    _player.stop();
    _isPlaying = false;
    _currentlyPlaying = null;
    _isNativeGreetingPlaying = false;
    _isNativeGoodbyePlaying = false;
    notifyListeners();

    // Nếu nhận tín hiệu tự động dừng từ Native nhưng ta vừa bấm dừng thủ công trước đó
    // thì vẫn coi là dừng thủ công để tránh bị minimize app.
    final finalIsManual = isManual || _isStoppingManually;
    onNativePlaybackComplete?.call(finalIsManual);
  }

  // ===== Action Methods =====

  Future<void> deleteAudio(String audioId) async {
    if (audioId == AppConstants.defaultGoodbyeId) return;
    _audioList =
        await AudioRepository.instance.deleteAudio(audioId, _audioList);
    notifyListeners();
  }

  Future<AudioModel> addAndDownloadGeneratedAudio(AudioModel audio) async {
    final localPath = await SyncService.instance.downloadSingleFile(
      audioId: audio.id,
      remoteUrl: audio.remoteUrl,
    );

    final updatedAudio = audio.copyWith(
      localPath: localPath,
      isDownloaded: localPath != null,
      downloadedAt: localPath != null ? DateTime.now() : null,
    );

    _audioList = [updatedAudio, ..._audioList];
    await AudioRepository.instance.saveLocalList(_audioList);
    notifyListeners();
    return updatedAudio;
  }

  // ===== Lifecycle =====

  Future<void> _syncNativePaths() async {
    final greetingPath =
        await AudioRepository.instance.getGreetingAudioPath(activeGreeting);
    final goodbyePath =
        await AudioRepository.instance.getGoodbyeAudioPath(activeGoodbye);
    final prefs = await SharedPreferences.getInstance();

    if (greetingPath != null)
      await prefs.setString('greeting_audio_path', greetingPath);
    if (goodbyePath != null)
      await prefs.setString('goodbye_audio_path', goodbyePath);

    // 🟢 Đồng bộ sang vùng nhớ an toàn cho khởi động (Direct Boot)
    await ServiceChannel.instance.syncPrefs();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void setBetaMode(bool value) {
    _isBetaMode = value;
    notifyListeners();
  }
}
