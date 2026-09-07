/// App-wide constants for Giọng Thương Gia
class AppConstants {
  AppConstants._();

  // ===== App Info =====
  static const String appName = 'Giọng Thương Gia';
  static const String bundleId = 'com.hicar.ora.limited';

  // ===== Method Channels =====
  static const String serviceChannel = 'com.hicar.ora.limited/service';
  static const String bluetoothChannel = 'com.hicar.ora.limited/bluetooth';

  // ===== Connection Modes =====
  static const String iosCarplayMode = 'ios_carplay';

  // ===== SharedPreferences Keys =====
  static const String keyAuthToken = 'auth_token';
  static const String keyUserData = 'user_data';
  static const String keyAudioList = 'audio_list';
  static const String keyTargetDeviceAddress = 'target_device_address';
  static const String keyTargetDeviceName = 'target_device_name';
  static const String keyDelaySeconds = 'delay_seconds';
  static const String keyGreetingAudioId = 'greeting_audio_id';
  static const String keyGoodbyeAudioId = 'goodbye_audio_id';
  static const String keyAutoPlayEnabled = 'auto_play_enabled';
  static const String keyLastSyncTime = 'last_sync_time';

  // ===== Audio Dirs =====
  static const String audioDirName = 'hicar_audio';
  static const String defaultAudioAsset = 'assets/audio/audio_default.MP3';
  // Giữ nguyên id cũ 'demo_default' để lựa chọn đã lưu trên máy người dùng không bị mất.
  static const String defaultGreetingId = 'demo_default';
  static const String defaultGoodbyeId = 'default_goodbye';
  static const String defaultGoodbyeAsset = 'assets/audio/good_bye.MP3';

  // ===== Mock API =====
  static const String mockApiBaseUrl = 'https://api.hicar.ora.limited/v1';

  // ===== Bluetooth Delay Options =====
  static const List<int> delayOptions = [1, 3, 5, 10];
  static const int defaultDelaySeconds = 5;

  // ===== Generate Credits =====
  static const int defaultGenerateCredits = 3;
}
