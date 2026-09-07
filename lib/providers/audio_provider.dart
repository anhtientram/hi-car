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
  StreamSubscription<PlayerState>? _playerStateSub;

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
  /// 'greeting' | 'goodbye' khi đang chờ native/service bắt đầu phát.
  String? _preparingNativeType;
  /// Audio id đang chuẩn bị phát local (Nghe thử).
  String? _preparingAudioId;
  /// Token để hủy request native cũ khi user bấm phát cái khác.
  int _nativePlaybackToken = 0;
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

  AudioModel _buildDefaultGreetingAudio() {
    return AudioModel(
      id: AppConstants.defaultGreetingId,
      title: 'Lời chào mặc định',
      type: AudioType.custom,
      remoteUrl: '',
      assetPath: AppConstants.defaultAudioAsset,
      description: 'Có sẵn trong app (không cần mạng)',
      isActiveGreeting: _activeGreetingId == AppConstants.defaultGreetingId,
      isActiveGoodbye: false,
    );
  }

  List<AudioModel> get audioList {
    final mappedList = _audioList
        .where((a) =>
            a.id != AppConstants.defaultGoodbyeId &&
            a.id != AppConstants.defaultGreetingId)
        .map((a) {
      return a.copyWith(
        isActiveGreeting: _activeGreetingId == a.id,
        isActiveGoodbye: _effectiveGoodbyeId == a.id,
      );
    }).toList();

    final defaultGoodbye = _buildDefaultGoodbyeAudio();

    // Lời chào mặc định chỉ hiện khi bật Demo (Beta). Fallback phát khi mất mạng
    // vẫn dùng bản dựng sẵn ngầm (playGreetingViaNative / _syncNativePaths).
    if (!_isBetaMode) return [defaultGoodbye, ...mappedList];

    return [
      _buildDefaultGreetingAudio(),
      defaultGoodbye,
      ...mappedList,
    ];
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
  bool get isPreparingGreeting => _preparingNativeType == 'greeting';
  bool get isPreparingGoodbye => _preparingNativeType == 'goodbye';
  bool get isPreparingNativePlayback => _preparingNativeType != null;
  String? get preparingAudioId => _preparingAudioId;

  bool isPreparingAudio(String audioId) => _preparingAudioId == audioId;

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

    ServiceChannel.instance.onPlaybackComplete = (isManual) {
      debugPrint(
          '🔔 [AudioProvider] NHẬN TÍN HIỆU: PHÁT XONG TỪ NATIVE (isManual=$isManual)');
      // isManual=true → người dùng bấm STOP ở nút nổi (đi thẳng native, không qua
      // isolate chính) → KHÔNG được coi là phát xong tự nhiên, tránh thu nhỏ app.
      _stopNativePlaybackState(isManual: isManual);
    };

    ServiceChannel.instance.onPlaybackStarted = (type) {
      debugPrint(
          '🔔 [AudioProvider] NHẬN TÍN HIỆU: BẮT ĐẦU PHÁT TỪ NATIVE ($type)');
      _preparingNativeType = null;
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

    // Đảm bảo file đã tải về trước khi ghi path cho CarPlay/native.
    final audio = activeGreeting;
    if (audio != null &&
        (audio.localPath == null || !await File(audio.localPath!).exists()) &&
        audio.remoteUrl.isNotEmpty &&
        audio.assetPath == null) {
      final path = await SyncService.instance.downloadSingleFile(
        audioId: audio.id,
        remoteUrl: audio.remoteUrl,
      );
      if (path != null) {
        _audioList = _audioList
            .map((a) => a.id == audio.id
                ? a.copyWith(
                    localPath: path,
                    isDownloaded: true,
                    downloadedAt: DateTime.now(),
                    isActiveGreeting: true,
                  )
                : a)
            .toList();
        await AudioRepository.instance.saveLocalList(_audioList);
      }
    }

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
      // Dừng native nếu đang phát/chuẩn bị — tránh 2 nguồn audio chồng nhau.
      if (_isNativeGreetingPlaying ||
          _isNativeGoodbyePlaying ||
          _preparingNativeType != null) {
        _nativePlaybackToken++;
        await ServiceChannel.instance.stopAudio();
        _preparingNativeType = null;
        _isNativeGreetingPlaying = false;
        _isNativeGoodbyePlaying = false;
      }

      // Chuyển UI ngay sang card mới (tắt highlight card cũ).
      _preparingAudioId = audio.id;
      _currentlyPlaying = audio;
      _isPlaying = false;
      notifyListeners();

      await _player.stop();
      await _playerStateSub?.cancel();
      _playerStateSub = null;

      if (audio.assetPath != null && audio.assetPath!.isNotEmpty) {
        await _player.setAsset(audio.assetPath!);
      } else if (audio.hasLocalFile &&
          audio.localPath != null &&
          await File(audio.localPath!).exists()) {
        await _player.setFilePath(audio.localPath!);
      } else {
        await _player.setUrl(audio.remoteUrl);
      }

      // Nếu user đã bấm audio khác trong lúc load → bỏ request này.
      if (_preparingAudioId != audio.id || _currentlyPlaying?.id != audio.id) {
        return;
      }

      // ⚠️ just_audio: Future của play() chỉ complete khi phát XONG / bị stop.
      //    Không được await ở đây — nếu await thì UI kẹt "Đang tải..." suốt lúc đang nghe.
      _preparingAudioId = null;
      _currentlyPlaying = audio;
      _isPlaying = true;
      notifyListeners();

      _playerStateSub = _player.playerStateStream.listen((state) {
        if (_currentlyPlaying?.id != audio.id) return;
        if (state.processingState == ProcessingState.completed) {
          _isPlaying = false;
          _currentlyPlaying = null;
          _preparingAudioId = null;
          notifyListeners();
        }
      });

      // Fire-and-forget: bắt đầu phát, trạng thái kết thúc do stream lo.
      unawaited(_player.play());
    } catch (e) {
      if (_currentlyPlaying?.id == audio.id) {
        _preparingAudioId = null;
        _isPlaying = false;
        _currentlyPlaying = null;
      }
      AppLogger.instance.log(
        'Lỗi phát nhạc: ${audio.title}',
        type: 'playback_error',
        details: {'audioId': audio.id, 'error': e.toString()},
      );
      notifyListeners();
    }
  }

  Future<void> stopAudio() async {
    await _playerStateSub?.cancel();
    _playerStateSub = null;
    await _player.stop();
    _preparingAudioId = null;
    _isPlaying = false;
    _currentlyPlaying = null;
    notifyListeners();
  }

  Future<bool> playGreetingViaNative({bool allowAutostartRetry = false}) async {
    final audio = activeGreeting;
    String? path;

    if (audio != null) {
      path = await AudioRepository.instance.getGreetingAudioPath(audio);
    }

    if (path == null || path.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('greeting_audio_path');
      if (await SyncService.instance.isValidAudioFile(saved)) path = saved;
      debugPrint('AudioProvider: greeting fallback path=$path');
    }

    // Đã cấu hình lời chào nhưng file chưa về được (máy mới cài / mất mạng / file hỏng):
    // phát bản dựng sẵn còn hơn im lặng.
    if ((path == null || path.isEmpty) &&
        (_activeGreetingId?.isNotEmpty ?? false)) {
      path = await AudioRepository.instance.prepareBundledGreetingPath();
      debugPrint('AudioProvider: dùng lời chào dựng sẵn, path=$path');
    }

    if (path == null || path.isEmpty) {
      debugPrint('AudioProvider: No active greeting found');
      return false;
    }

    debugPrint('AudioProvider: playGreetingViaNative path=$path');

    // Hủy request native cũ + dừng local preview.
    final token = ++_nativePlaybackToken;
    await _cancelLocalPreview();
    try {
      await ServiceChannel.instance.stopAudio();
    } catch (_) {}

    _isStartingPlayback = true;
    _preparingNativeType = 'greeting';
    _isNativeGoodbyePlaying = false;
    _isNativeGreetingPlaying = false;
    notifyListeners();

    try {
      await _waitForAudioFocus();

      // User đã bấm phát cái khác trong lúc chờ → bỏ.
      if (token != _nativePlaybackToken) return false;

      await ServiceChannel.instance.playGreeting(audioPath: path);

      if (token != _nativePlaybackToken) return false;

      // Method channel đã nhận lệnh phát → thoát "chuẩn bị", vào "đang phát".
      // (onPlaybackStarted sẽ xác nhận lại; không phụ thuộc 100% vào callback).
      _preparingNativeType = null;
      _isNativeGreetingPlaying = true;
      _isNativeGoodbyePlaying = false;
      notifyListeners();

      _startWatchdog(audio?.durationSeconds ?? 15);
      return true;
    } catch (e) {
      if (token != _nativePlaybackToken) return false;
      debugPrint('AudioProvider: playGreetingViaNative error: $e');
      AppLogger.instance.log(
        'Lỗi phát lời chào (Native): $e',
        type: 'native_playback_error',
        details: {'path': path, 'error': e.toString()},
      );
      _stopNativePlaybackState();
      if (allowAutostartRetry) {
        debugPrint('AudioProvider: autostart retry sau 15s...');
        await Future.delayed(const Duration(seconds: 15));
        return playGreetingViaNative(allowAutostartRetry: false);
      }
      return false;
    } finally {
      if (token == _nativePlaybackToken) {
        _isStartingPlayback = false;
      }
    }
  }

  Future<bool> playGoodbyeViaNative() async {
    final audio = activeGoodbye;
    var path = await AudioRepository.instance.getGoodbyeAudioPath(audio);

    if (path == null || path.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      path = prefs.getString('goodbye_audio_path');
      debugPrint('AudioProvider: goodbye fallback path=$path');
    }

    if (path == null || path.isEmpty) {
      debugPrint('AudioProvider: No active goodbye found');
      return false;
    }

    final token = ++_nativePlaybackToken;
    await _cancelLocalPreview();
    try {
      await ServiceChannel.instance.stopAudio();
    } catch (_) {}

    _isStartingPlayback = true;
    _preparingNativeType = 'goodbye';
    _isNativeGreetingPlaying = false;
    _isNativeGoodbyePlaying = false;
    notifyListeners();

    try {
      await _waitForAudioFocus();

      if (token != _nativePlaybackToken) return false;

      await ServiceChannel.instance.playGoodbye(audioPath: path);

      if (token != _nativePlaybackToken) return false;

      _preparingNativeType = null;
      _isNativeGoodbyePlaying = true;
      _isNativeGreetingPlaying = false;
      notifyListeners();

      _startWatchdog(audio.durationSeconds > 0 ? audio.durationSeconds : 15);
      return true;
    } catch (e) {
      if (token != _nativePlaybackToken) return false;
      debugPrint('AudioProvider: playGoodbyeViaNative error: $e');
      AppLogger.instance.log(
        'Lỗi phát lời tạm biệt (Native): $e',
        type: 'native_playback_error',
        details: {'path': path, 'error': e.toString()},
      );
      _stopNativePlaybackState();
      return false;
    } finally {
      if (token == _nativePlaybackToken) {
        _isStartingPlayback = false;
      }
    }
  }

  /// Nhịp chờ trước khi ra lệnh phát cho native.
  ///
  /// Android cần ~1.5s để audio focus của màn hình xe ổn định (Box khởi động thì native tự
  /// lo nên bỏ qua). iOS KHÔNG cần: `HiCarAudioPlayer` đã tự chờ đúng lúc route xe sẵn sàng
  /// rồi mới phát, thêm 1.5s ở đây chỉ làm bấm nút xong phải đợi cả giây mới nghe thấy.
  Future<void> _waitForAudioFocus() async {
    if (Platform.isIOS) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('connection_mode') == 'android_box_mode') return;
    await Future.delayed(const Duration(milliseconds: 1500));
  }

  Future<void> _cancelLocalPreview() async {
    await _playerStateSub?.cancel();
    _playerStateSub = null;
    try {
      await _player.stop();
    } catch (_) {}
    _preparingAudioId = null;
    _isPlaying = false;
    _currentlyPlaying = null;
  }

  Future<void> stopNativeAudio({bool isManual = true}) async {
    try {
      debugPrint('AudioProvider: stopNativeAudio (isManual=$isManual)');
      _nativePlaybackToken++;
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
          type: 'native_warning',
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
    _preparingAudioId = null;
    _preparingNativeType = null;
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
    var greetingSource =
        await AudioRepository.instance.getGreetingAudioPath(activeGreeting);
    // Đã chọn lời chào nhưng file chưa tải về / hỏng → ghim bản dựng sẵn để native (kể cả
    // luồng boot khi app chưa mở) luôn có file hợp lệ để phát.
    if ((greetingSource == null || greetingSource.isEmpty) &&
        (_activeGreetingId?.isNotEmpty ?? false)) {
      greetingSource =
          await AudioRepository.instance.prepareBundledGreetingPath();
    }
    final goodbyeSource =
        await AudioRepository.instance.getGoodbyeAudioPath(activeGoodbye);

    // Pin sang tên cố định để CarPlay/App Intent luôn tìm được file.
    final greetingPath = await AudioRepository.instance.pinActiveAudio(
      sourcePath: greetingSource,
      destFileName: AudioRepository.activeGreetingFileName,
    );
    final goodbyePath = await AudioRepository.instance.pinActiveAudio(
      sourcePath: goodbyeSource,
      destFileName: AudioRepository.activeGoodbyeFileName,
    );

    final prefs = await SharedPreferences.getInstance();

    if (greetingPath != null && greetingPath.isNotEmpty) {
      await prefs.setString('greeting_audio_path', greetingPath);
    } else {
      await prefs.remove('greeting_audio_path');
    }
    if (goodbyePath != null && goodbyePath.isNotEmpty) {
      await prefs.setString('goodbye_audio_path', goodbyePath);
    } else {
      await prefs.remove('goodbye_audio_path');
    }

    // Đồng bộ sang native (Android Direct Boot + iOS UserDefaults flush)
    await ServiceChannel.instance.syncPrefs();
  }

  @override
  void dispose() {
    _playerStateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  void setBetaMode(bool value) {
    _isBetaMode = value;
    notifyListeners();
  }
}
