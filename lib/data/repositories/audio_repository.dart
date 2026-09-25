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

    var updated = audioList.map((a) {
      return a.copyWith(
        isActiveGreeting: a.id == greetingId,
        isActiveGoodbye: a.id == goodbyeId,
      );
    }).toList();

    // Nếu người dùng chưa có nhạc chào, tự chọn một audio greeting vừa đồng bộ.
    // Khi đã có lựa chọn, tuyệt đối giữ nguyên để sync không đổi cấu hình của người dùng.
    // Không lấy goodbye/custom làm greeting nếu server không trả về audio greeting.
    if (greetingId.isEmpty) {
      final greetingCandidates = updated
          .where((audio) =>
              audio.type == AudioType.greeting &&
              audio.isDownloaded &&
              audio.localPath != null)
          .toList();
      if (greetingCandidates.isEmpty) {
        await saveLocalList(updated);
        return updated;
      }

      final greeting = greetingCandidates.first;

      await prefs.setString(AppConstants.keyGreetingAudioId, greeting.id);
      updated = updated
          .map((audio) => audio.copyWith(
                isActiveGreeting: audio.id == greeting.id,
              ))
          .toList();
    }

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

  Future<String> _prepareAssetFile(String assetPath) async {
    try {
      final tempDir = await SyncService.instance.getAudioDir();
      final fileName = assetPath.split('/').last;
      final tempFile = File('${tempDir.path}/$fileName');

      if (await SyncService.instance.fileExists(tempFile.path))
        return tempFile.path;

      final byteData = await rootBundle.load(assetPath);
      final buffer = byteData.buffer;
      final staging = File(
          '${tempFile.path}.${DateTime.now().microsecondsSinceEpoch}.part');
      await staging.writeAsBytes(
          buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
          flush: true);
      await staging.rename(tempFile.path);
      return tempFile.path;
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
