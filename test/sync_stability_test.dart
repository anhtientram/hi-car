import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hi_car/core/constants.dart';
import 'package:hi_car/core/logger.dart';
import 'package:hi_car/data/models/audio_model.dart';
import 'package:hi_car/data/services/sync_service.dart';

class MemoryAudioAdapter implements HttpClientAdapter {
  List<int> bytes = [73, 68, 51, ...List.filled(253, 2)];
  bool fail = false;
  int calls = 0;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls++;
    if (fail)
      throw DioException(
          requestOptions: options, type: DioExceptionType.connectionError);
    return ResponseBody.fromBytes(bytes, 200, headers: {
      Headers.contentLengthHeader: ['${bytes.length}']
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late File old;
  late MemoryAudioAdapter adapter;
  late SyncService service;
  setUp(() async {
    await AppLogger.instance.flush();
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('hicar-sync-test-');
    old = File('${dir.path}/audio_old.mp3');
    await old.writeAsBytes([73, 68, 51, ...List.filled(253, 1)]);
    final local = AudioModel(
        id: 'audio',
        title: 'Old',
        type: AudioType.greeting,
        remoteUrl: 'https://audio.invalid/file',
        localPath: old.path,
        hash: 'old',
        isDownloaded: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        AppConstants.keyAudioList, AudioModel.toJsonList([local]));
    adapter = MemoryAudioAdapter();
    service = SyncService.testing(
        fetchAudio: () async => [
              {
                'id': 'audio',
                'title': 'New',
                'type': 'greeting',
                'url': local.remoteUrl,
                'hash': 'new'
              }
            ],
        audioDirectory: () async => dir,
        dio: Dio()..httpClientAdapter = adapter);
  });
  tearDown(() async {
    await AppLogger.instance.flush();
    await dir.delete(recursive: true);
  });

  test(
      'failed day-two download keeps previous playable file AND hash, then retries',
      () async {
    adapter.fail = true;
    var list = await service.syncAudioFromServer();
    expect(list.single.localPath, old.path);
    expect(list.single.hash, 'old');
    expect(list.single.isDownloaded, isTrue);
    expect(service.lastSyncFailures, ['audio']);
    adapter.fail = false;
    list = await service.syncAudioFromServer();
    expect(list.single.hash, 'new');
    expect(list.single.localPath, isNot(old.path));
    expect(service.lastSyncFailures, isEmpty);
    expect(adapter.calls, 2);
  });
  test('HTML download rejected; existing valid file never erased', () async {
    adapter.bytes = List.filled(256, 60);
    final list = await service.syncAudioFromServer();
    expect(list.single.localPath, old.path);
    expect(await service.fileExists(old.path), isTrue);
    expect(dir.listSync().where((f) => f.path.endsWith('.part')), isEmpty);
  });
  test('unchanged validated revision needs no download on next sync', () async {
    await service.syncAudioFromServer();
    await service.syncAudioFromServer();
    expect(adapter.calls, 1);
  });
  test('metadata duration survives disk round trip', () {
    const audio = AudioModel(
        id: '74s',
        title: '',
        type: AudioType.greeting,
        remoteUrl: '',
        durationSeconds: 74);
    expect(AudioModel.fromJson(audio.toJson()).durationSeconds, 74);
  });
}
