import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/audio_model.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../../core/constants.dart';

class AudioRepository {
  AudioRepository._();
  static final AudioRepository instance = AudioRepository._();

  // ===== Load Local =====

  /// Loads the saved audio list from SharedPreferences.
  Future<List<AudioModel>> loadLocalAudioList() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(AppConstants.keyAudioList);
    if (jsonString == null || jsonString.isEmpty) return [];
    try {
      return AudioModel.fromJsonList(jsonString);
    } catch (_) {
      return [];
    }
  }

  // ===== Sync =====

  /// Full sync: fetch from server → download files → save metadata locally.
  Future<List<AudioModel>> syncFromServer({
    void Function(String message, double progress)? onProgress,
  }) async {
    final audioList = await SyncService.instance.syncAudioFromServer(
      onProgress: onProgress,
    );

    // Restore active states from saved prefs
    final prefs = await SharedPreferences.getInstance();
    final greetingId = prefs.getString(AppConstants.keyGreetingAudioId) ?? '';
    final goodbyeId = prefs.getString(AppConstants.keyGoodbyeAudioId) ?? '';

    final updated = audioList.map((a) {
      return a.copyWith(
        isActiveGreeting: a.id == greetingId,
        isActiveGoodbye: a.id == goodbyeId,
      );
    }).toList();

    await saveLocalList(updated);
    return updated;
  }

  // ===== Set Active Audio =====

  Future<List<AudioModel>> setGreetingAudio(
    String audioId,
    List<AudioModel> currentList,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyGreetingAudioId, audioId);

    final updated = currentList.map((a) {
      return a.copyWith(isActiveGreeting: a.id == audioId);
    }).toList();

    await saveLocalList(updated);
    return updated;
  }

  Future<List<AudioModel>> setGoodbyeAudio(
    String audioId,
    List<AudioModel> currentList,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyGoodbyeAudioId, audioId);

    final updated = currentList.map((a) {
      return a.copyWith(isActiveGoodbye: a.id == audioId);
    }).toList();

    await saveLocalList(updated);
    return updated;
  }

  /// Bỏ đặt lời chào: xoá id đang lưu + tắt cờ active cho mọi audio.
  Future<List<AudioModel>> clearGreetingAudio(
    List<AudioModel> currentList,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.keyGreetingAudioId);
    await prefs.remove('greeting_audio_path');

    final updated =
        currentList.map((a) => a.copyWith(isActiveGreeting: false)).toList();
    await saveLocalList(updated);
    return updated;
  }

  /// Bỏ đặt lời tạm biệt: xoá id đang lưu + tắt cờ active cho mọi audio.
  Future<List<AudioModel>> clearGoodbyeAudio(
    List<AudioModel> currentList,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.keyGoodbyeAudioId);
    await prefs.remove('goodbye_audio_path');

    final updated =
        currentList.map((a) => a.copyWith(isActiveGoodbye: false)).toList();
    await saveLocalList(updated);
    return updated;
  }

  // ===== Generate Audio =====

  Future<AudioModel> generateAudio({
    required String ownerName,
    required String licensePlate,
    required String carBrand,
    required String type,
  }) async {
    final raw = await ApiService.instance.generateAudio(
      ownerName: ownerName,
      licensePlate: licensePlate,
      carBrand: carBrand,
      type: type,
    );
    return AudioModel.fromJson(raw);
  }

  // ===== Get Active Paths =====

  static const String activeGreetingFileName = 'active_greeting.mp3';
  static const String activeGoodbyeFileName = 'active_goodbye.mp3';

  Future<String?> getGreetingAudioPath(AudioModel? audio) async {
    if (audio == null) return null;
    if (audio.assetPath != null && audio.assetPath!.isNotEmpty) {
      return await _prepareAssetFile(audio.assetPath!);
    }
    if (!audio.hasLocalFile || audio.localPath == null) return null;
    final exists = await SyncService.instance.fileExists(audio.localPath);
    return exists ? audio.localPath : null;
  }

  Future<String?> getGoodbyeAudioPath(AudioModel? audio) async {
    if (audio == null) return null;
    if (audio.assetPath != null && audio.assetPath!.isNotEmpty) {
      return await _prepareAssetFile(audio.assetPath!);
    }
    if (!audio.hasLocalFile || audio.localPath == null) return null;
    final exists = await SyncService.instance.fileExists(audio.localPath);
    return exists ? audio.localPath : null;
  }

  /// Sao chép file lời chào/tạm biệt sang tên cố định trong Documents.
  /// CarPlay/App Intent đọc path này ngay cả khi app không mở.
  Future<String?> pinActiveAudio({
    required String? sourcePath,
    required String destFileName,
  }) async {
    if (sourcePath == null || sourcePath.isEmpty) return null;
    // Không ghim file hỏng: active_*.mp3 còn được nhân bản tiếp sang boot_*.mp3 ở vùng
    // device-protected, nên một file cụt sẽ làm hỏng cả luồng phát lúc khởi động.
    if (!await SyncService.instance.isValidAudioFile(sourcePath)) return null;
    final source = File(sourcePath);

    final audioDir = await SyncService.instance.getAudioDir();
    final dest = File('${audioDir.path}/$destFileName');
    if (source.path == dest.path) return dest.path;

    // Ghi qua file tạm rồi đổi tên: nếu bị ngắt giữa chừng thì bản đang dùng vẫn nguyên vẹn,
    // và không bao giờ ghi đè lên file mà MediaPlayer đang đọc dở.
    final temp = File('${dest.path}.tmp');
    await source.copy(temp.path);
    await temp.rename(dest.path);
    return dest.path;
  }

  /// Lời chào dự phòng dựng sẵn trong app — dùng khi file đã chọn chưa tải về được
  /// (máy vừa cài, mất mạng, hoặc file tải hỏng) để thiết bị nào cũng có tiếng.
  Future<String?> prepareBundledGreetingPath() async {
    final path = await _prepareAssetFile(AppConstants.defaultAudioAsset);
    return path.isEmpty ? null : path;
  }

  /// Copy asset vào Documents (không dùng temp — iOS có thể xóa temp bất kỳ lúc nào).
  Future<String> _prepareAssetFile(String assetPath) async {
    try {
      final audioDir = await SyncService.instance.getAudioDir();
      final fileName = assetPath.split('/').last;
      final destFile = File('${audioDir.path}/$fileName');

      if (await SyncService.instance.isValidAudioFile(destFile.path)) {
        return destFile.path;
      }

      final byteData = await rootBundle.load(assetPath);
      final buffer = byteData.buffer;
      await destFile.writeAsBytes(
        buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
        flush: true,
      );
      return destFile.path;
    } catch (e) {
      debugPrint('Error preparing asset file: $e');
      return '';
    }
  }

  // ===== Delete =====

  Future<List<AudioModel>> deleteAudio(
    String audioId,
    List<AudioModel> currentList,
  ) async {
    final audio = currentList.where((a) => a.id == audioId).firstOrNull;
    if (audio?.localPath != null) {
      await SyncService.instance.deleteLocalFile(audio!.localPath!);
    }
    final updated = currentList.where((a) => a.id != audioId).toList();
    await saveLocalList(updated);
    return updated;
  }

  // ===== Save Local List =====

  Future<void> saveLocalList(List<AudioModel> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        AppConstants.keyAudioList, AudioModel.toJsonList(list));
  }
}
