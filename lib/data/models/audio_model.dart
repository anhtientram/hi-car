import 'dart:convert';

enum AudioType { greeting, goodbye, custom }

extension AudioTypeExtension on AudioType {
  String get value {
    switch (this) {
      case AudioType.greeting:
        return 'greeting';
      case AudioType.goodbye:
        return 'goodbye';
      case AudioType.custom:
        return 'custom';
    }
  }

  String get label {
    switch (this) {
      case AudioType.greeting:
        return 'Lời chào';
      case AudioType.goodbye:
        return 'Lời tạm biệt';
      case AudioType.custom:
        return 'Tùy chỉnh';
    }
  }

  static AudioType fromString(String value) {
    switch (value) {
      case 'greeting':
        return AudioType.greeting;
      case 'goodbye':
        return AudioType.goodbye;
      default:
        return AudioType.custom;
    }
  }
}

class AudioModel {
  final String id;
  final String title;
  final AudioType type;
  final String remoteUrl;
  final String? localPath;
  final bool isDownloaded;
  final DateTime? downloadedAt;
  final bool isActiveGreeting;
  final bool isActiveGoodbye;
  final int durationSeconds;
  final String? description;
  final String? hash; // Added for verification
  final String? assetPath; // New field for bundled assets

  const AudioModel({
    required this.id,
    required this.title,
    required this.type,
    required this.remoteUrl,
    this.localPath,
    this.isDownloaded = false,
    this.downloadedAt,
    this.isActiveGreeting = false,
    this.isActiveGoodbye = false,
    this.durationSeconds = 0,
    this.description,
    this.hash,
    this.assetPath,
  });

  bool get hasLocalFile =>
      (isDownloaded && localPath != null && localPath!.isNotEmpty) ||
      (assetPath != null && assetPath!.isNotEmpty);

  factory AudioModel.fromJson(Map<String, dynamic> json) {
    return AudioModel(
      id: json['id']?.toString() ?? '',
      title: json['title'] as String? ?? '',
      type: AudioTypeExtension.fromString(json['type'] as String? ?? 'custom'),
      remoteUrl: json['remote_url'] ?? json['url'] ?? '',
      localPath: json['local_path'] as String?,
      isDownloaded: json['is_downloaded'] as bool? ?? false,
      hash: json['hash'] as String?,
      downloadedAt: json['downloaded_at'] != null
          ? DateTime.tryParse(json['downloaded_at'] as String)
          : null,
      isActiveGreeting: json['is_active_greeting'] as bool? ?? false,
      isActiveGoodbye: json['is_active_goodbye'] as bool? ?? false,
      durationSeconds: num.tryParse(
                  (json['duration'] ?? json['duration_seconds'] ?? 0)
                      .toString())
              ?.toInt() ??
          0,
      description: json['description'] as String?,
      assetPath: json['asset_path'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'type': type.value,
      'remote_url': remoteUrl,
      'local_path': localPath,
      'is_downloaded': isDownloaded,
      'downloaded_at': downloadedAt?.toIso8601String(),
      'is_active_greeting': isActiveGreeting,
      'is_active_goodbye': isActiveGoodbye,
      'duration_seconds': durationSeconds,
      'description': description,
      'hash': hash,
      'asset_path': assetPath,
    };
  }

  AudioModel copyWith({
    String? id,
    String? title,
    AudioType? type,
    String? remoteUrl,
    String? localPath,
    bool? isDownloaded,
    DateTime? downloadedAt,
    bool? isActiveGreeting,
    bool? isActiveGoodbye,
    int? durationSeconds,
    String? description,
    String? hash,
    String? assetPath,
  }) {
    return AudioModel(
      id: id ?? this.id,
      title: title ?? this.title,
      type: type ?? this.type,
      remoteUrl: remoteUrl ?? this.remoteUrl,
      localPath: localPath ?? this.localPath,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      isActiveGreeting: isActiveGreeting ?? this.isActiveGreeting,
      isActiveGoodbye: isActiveGoodbye ?? this.isActiveGoodbye,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      description: description ?? this.description,
      hash: hash ?? this.hash,
      assetPath: assetPath ?? this.assetPath,
    );
  }

  static List<AudioModel> fromJsonList(String jsonString) {
    final list = jsonDecode(jsonString) as List;
    return list
        .map((e) => AudioModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String toJsonList(List<AudioModel> items) {
    return jsonEncode(items.map((e) => e.toJson()).toList());
  }
}
