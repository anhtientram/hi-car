import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/audio_model.dart';
import '../services/api_service.dart';
import '../services/api_client.dart';
import '../../core/constants.dart';
import '../../core/logger.dart';

/// SyncService - Performs optimized background synchronization of audio files.
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  Dio _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 20)));
  Future<List<dynamic>> Function()? _fetchAudio;
  Future<Directory> Function()? _audioDirectory;
  final List<String> lastSyncFailures = [];

  @visibleForTesting
  SyncService.testing({
    required Future<List<dynamic>> Function() fetchAudio,
    required Future<Directory> Function() audioDirectory,
    Dio? dio,
  }) {
    _fetchAudio = fetchAudio;
    _audioDirectory = audioDirectory;
    if (dio != null) _dio = dio;
  }

  /// Gets the dedicated audio storage directory.
  Future<Directory> getAudioDir() async {
    if (_audioDirectory != null) return _audioDirectory!();
    final docs = await getApplicationDocumentsDirectory();
    final audioDir = Directory('${docs.path}/hicar_audio');
    if (!await audioDir.exists()) {
      await audioDir.create(recursive: true);
    }
    // ignore: avoid_print
    print('📂 THƯ MỤC AUDIO LƯU TẠI: ${audioDir.path}');
    return audioDir;
  }

  /// Synchronizes audio metadata and files from server.
  /// Performance optimization: Only downloads if hash changes.
  Future<List<AudioModel>> syncAudioFromServer({
    void Function(String message, double progress)? onProgress,
  }) async {
    onProgress?.call('Đang kiểm tra dữ liệu từ máy chủ...', 0.1);

    try {
      // 1. Fetch live list from API
      lastSyncFailures.clear();
      final rawList =
          await (_fetchAudio?.call() ?? ApiService.instance.getAudioList());
      final audioDir = await getAudioDir();
      final prefs = await SharedPreferences.getInstance();

      // Load last known state to compare hashes (gộp cả cache sync + danh sách chính
      // để không mất metadata file cũ khi server chỉ trả về nhạc mới).
      final cachedJson = prefs.getString('cached_audio_list');
      final mainJson = prefs.getString(AppConstants.keyAudioList);
      final List<AudioModel> localPool = [];
      void addToPool(List<AudioModel> items) {
        for (final item in items) {
          if (!localPool.any((e) => e.id == item.id)) {
            localPool.add(item);
          }
        }
      }

      if (cachedJson != null) {
        addToPool(AudioModel.fromJsonList(cachedJson));
      }
      if (mainJson != null) {
        addToPool(AudioModel.fromJsonList(mainJson));
      }

      final List<AudioModel> syncedList = [];
      final total = rawList.length;

      for (int i = 0; i < total; i++) {
        final audioModel = AudioModel.fromJson(rawList[i]);
        final progress = 0.1 + (i / total) * 0.9;

        onProgress?.call('Đang xử lý: ${audioModel.title}...', progress);

        // Find match in local pool to check hash
        final localMatch = localPool.cast<AudioModel?>().firstWhere(
              (e) => e?.id == audioModel.id,
              orElse: () => null,
            );

        String? localPath = localMatch?.localPath;
        bool needsDownload = true;

        // Giữ file cũ: nếu hash không đổi, dùng bất kỳ bản local nào còn trên disk.
        if (localMatch != null &&
            audioModel.hash?.isNotEmpty == true &&
            localMatch.hash == audioModel.hash) {
          final candidates = <String>{
            if (localPath != null && localPath.isNotEmpty) localPath,
            _localPathFor(audioModel.id, audioModel.hash, audioDir.path),
            '${audioDir.path}/${audioModel.id}.mp3',
          };
          for (final candidate in candidates) {
            if (await _isValidAudioFile(File(candidate))) {
              localPath = candidate;
              needsDownload = false;
              break;
            }
          }
        }

        if (needsDownload) {
          onProgress?.call('Đang tải mới: ${audioModel.title}...', progress);
          localPath = await _downloadFile(
            audioId: audioModel.id,
            url: audioModel.remoteUrl,
            audioDir: audioDir,
            contentHash: audioModel.hash,
          );
          if (localPath == null) {
            lastSyncFailures.add(audioModel.id);
            // Keep BOTH the old path and old hash. Next sync must retry the new revision.
            final previous = localMatch == null
                ? null
                : await _resolveExistingLocalPath(localMatch, audioDir);
            if (localMatch != null && previous != null) {
              syncedList.add(
                  localMatch.copyWith(localPath: previous, isDownloaded: true));
              AppLogger.instance.log(
                  'Giữ audio hợp lệ cũ sau khi tải bản mới thất bại',
                  type: 'sync_error',
                  details: {'audioId': audioModel.id, 'path': previous});
              continue;
            }
          }
        }

        syncedList.add(audioModel.copyWith(
          localPath: localPath,
          isDownloaded: localPath != null,
          downloadedAt: localPath != null ? DateTime.now() : null,
        ));
      }

      // Giữ file nhạc cũ: server chỉ trả về bản mới thì các mục local-only (đã tải
      // trước đó / Studio / không còn trên API) vẫn được giữ nếu file còn trên disk.
      final serverIds = syncedList.map((a) => a.id).toSet();
      for (final local in localPool) {
        if (serverIds.contains(local.id)) continue;

        final path = await _resolveExistingLocalPath(local, audioDir);
        if (path == null) continue;

        syncedList.add(local.copyWith(
          localPath: path,
          isDownloaded: true,
        ));
      }

      // Persist the synced state
      await prefs.setString(
          'cached_audio_list', AudioModel.toJsonList(syncedList));

      if (lastSyncFailures.isNotEmpty) {
        AppLogger.instance.log(
            'Đồng bộ chưa đủ: ${lastSyncFailures.length} file tải lỗi',
            type: 'sync_error',
            requiresAction: true,
            userMessage:
                'Một số file chưa tải được. Nhạc cũ được giữ lại; hãy đồng bộ lại khi có mạng.',
            details: {'failed_audio_ids': List.of(lastSyncFailures)});
      }
      onProgress?.call(
          lastSyncFailures.isEmpty
              ? 'Đồng bộ thành công!'
              : 'Còn file chưa tải được, đã giữ nhạc cũ.',
          1.0);
      return syncedList;
    } catch (e) {
      final formattedError = ApiClient.formatError(e);
      onProgress?.call('Lỗi đồng bộ: $formattedError', 1.0);
      AppLogger.instance.log(
        'Lỗi đồng bộ: $e',
        type: 'sync_error',
        userMessage:
            'Không thể đồng bộ nhạc từ máy chủ. Hãy kiểm tra mạng rồi thử lại.',
        requiresAction: true,
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }

  Future<String?> _downloadFile({
    required String audioId,
    required String url,
    required Directory audioDir,
    String? contentHash,
  }) async {
    final destPath = _localPathFor(audioId, contentHash, audioDir.path);
    final partPath = '$destPath.${DateTime.now().microsecondsSinceEpoch}.part';
    // ignore: avoid_print
    print('📥 ĐANG TẢI FILE: $url -> $destPath');

    try {
      // Không bao giờ ghi trực tiếp vào file đang được player dùng. File .part
      // giúp app không nhìn thấy một MP3 nửa chừng sau khi mạng/box bị ngắt.
      final partFile = File(partPath);
      if (await partFile.exists()) {
        await partFile.delete();
      }

      if (url.startsWith('mock://')) {
        // Handle mock fallback for demo
        final byteData =
            await rootBundle.load('assets/audio/audio_default.MP3');
        await partFile.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      } else {
        // Real HTTP Download
        await _dio.download(
          url,
          partPath,
          options: Options(
            headers: {'Accept': 'application/json'},
            receiveTimeout: const Duration(seconds: 45),
            sendTimeout: const Duration(seconds: 20),
            responseType: ResponseType.bytes,
          ),
          deleteOnError: true,
        );
      }

      if (!await _isValidAudioFile(partFile)) {
        throw const FormatException(
            'File audio tải về không hợp lệ hoặc bị rỗng');
      }

      final destination = File(destPath);
      // Same-directory rename replaces atomically on Android/iOS; never delete good audio first.
      await partFile.rename(destPath);
      AppLogger.instance.log(
        'Tải audio thành công: $audioId (${destination.lengthSync()} bytes)',
        type: 'download_complete',
        details: {'audioId': audioId, 'path': destPath},
      );
      return destPath;
    } catch (e) {
      print('Download error: $e');
      try {
        final partFile = File(partPath);
        if (await partFile.exists()) await partFile.delete();
      } catch (_) {
        // Không che lỗi gốc khi dọn file tạm thất bại.
      }
      AppLogger.instance.log(
        'Lỗi tải file: $url',
        type: 'download_error',
        userMessage: 'Không tải được file nhạc. Vui lòng thử đồng bộ lại.',
        details: {'url': url, 'error': e.toString()},
      );
      return null;
    }
  }

  /// Downloads and caches a single audio file (e.g. from studio).
  Future<String?> downloadSingleFile({
    required String audioId,
    required String remoteUrl,
  }) async {
    final audioDir = await getAudioDir();
    return _downloadFile(
      audioId: audioId,
      url: remoteUrl,
      audioDir: audioDir,
    );
  }

  /// Checks if a file exists on disk.
  Future<bool> fileExists(String? path) async {
    if (path == null) return false;
    return _isValidAudioFile(File(path));
  }

  String _localPathFor(String audioId, String? hash, String dirPath) {
    audioId = Uri.encodeComponent(audioId);
    hash = hash == null ? null : Uri.encodeComponent(hash);
    if (hash != null && hash.isNotEmpty) {
      return '$dirPath/${audioId}_$hash.mp3';
    }
    return '$dirPath/$audioId.mp3';
  }

  /// Tìm đường dẫn file local còn tồn tại trên disk (dùng khi giữ nhạc cũ sau sync).
  Future<String?> _resolveExistingLocalPath(
    AudioModel audio,
    Directory audioDir,
  ) async {
    final candidates = <String>{
      if (audio.localPath != null && audio.localPath!.isNotEmpty)
        audio.localPath!,
      _localPathFor(audio.id, audio.hash, audioDir.path),
      '${audioDir.path}/${audio.id}.mp3',
    };
    for (final candidate in candidates) {
      if (await _isValidAudioFile(File(candidate))) return candidate;
    }
    return null;
  }

  /// Deletes a local audio file.
  Future<void> deleteLocalFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      AppLogger.instance.log(
        'Không xoá được file audio local',
        type: 'storage_error',
        details: {'path': path, 'error': e.toString()},
      );
    }
  }

  /// Kiểm tra tối thiểu để không đưa file HTML/JSON hoặc file đang tải dở vào player.
  /// Không khóa cứng vào một codec duy nhất vì server có thể trả MP3, WAV, M4A hoặc OGG.
  Future<bool> _isValidAudioFile(File file) async {
    try {
      if (!await file.exists() || await file.length() < 128) return false;
      final handle = await file.open();
      try {
        final header = await handle.read(12);
        if (header.length < 4) return false;
        final ascii = String.fromCharCodes(header);
        final isId3 = ascii.startsWith('ID3');
        final isRiff = ascii.startsWith('RIFF') && ascii.contains('WAVE');
        final isFlac = ascii.startsWith('fLaC');
        final isOgg = ascii.startsWith('OggS');
        final isMp4 = ascii.substring(4).contains('ftyp');
        final isMp3Frame = header[0] == 0xFF && (header[1] & 0xE0) == 0xE0;
        return isId3 || isRiff || isFlac || isOgg || isMp4 || isMp3Frame;
      } finally {
        await handle.close();
      }
    } catch (_) {
      return false;
    }
  }
}
