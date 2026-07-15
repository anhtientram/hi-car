import 'dart:io';
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

  final _dio = Dio();

  /// Gets the dedicated audio storage directory.
  Future<Directory> getAudioDir() async {
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
      final rawList = await ApiService.instance.getAudioList();
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
        if (localMatch != null && localMatch.hash == audioModel.hash) {
          final candidates = <String>{
            if (localPath != null && localPath.isNotEmpty) localPath,
            _localPathFor(audioModel.id, audioModel.hash, audioDir.path),
            '${audioDir.path}/${audioModel.id}.mp3',
          };
          for (final candidate in candidates) {
            if (await File(candidate).exists()) {
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

      onProgress?.call('Đồng bộ thành công!', 1.0);
      return syncedList;
    } catch (e) {
      final formattedError = ApiClient.formatError(e);
      onProgress?.call('Lỗi đồng bộ: $formattedError', 1.0);
      AppLogger.instance.log(
        'Lỗi đồng bộ: $e',
        type: 'sync_error',
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
    // ignore: avoid_print
    print('📥 ĐANG TẢI FILE: $url -> $destPath');

    try {
      if (url.startsWith('mock://')) {
        // Handle mock fallback for demo
        final byteData =
            await rootBundle.load('assets/audio/audio_default.MP3');
        final file = File(destPath);
        await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      } else {
        // Real HTTP Download
        await _dio.download(
          url,
          destPath,
          options: Options(
            headers: {'Accept': 'application/json'},
          ),
        );
      }
      return destPath;
    } catch (e) {
      print('Download error: $e');
      AppLogger.instance.log(
        'Lỗi tải file: $url',
        type: 'download_error',
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
    return File(path).exists();
  }

  String _localPathFor(String audioId, String? hash, String dirPath) {
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
      if (await File(candidate).exists()) return candidate;
    }
    return null;
  }

  /// Deletes a local audio file.
  Future<void> deleteLocalFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
