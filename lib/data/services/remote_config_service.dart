import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

/// Lấy Base URL động từ file cấu hình từ xa (GitHub) khi mở app.
///
/// Domain cũ đã ngừng hoạt động nên baseUrl không còn hard-code. Mỗi lần mở app,
/// ta đọc `api_url` từ file config để có thể đổi domain phía server bất cứ lúc nào
/// mà không cần phát hành lại app.
class RemoteConfigService {
  RemoteConfigService._();
  static final RemoteConfigService instance = RemoteConfigService._();

  static const String _configUrl =
      'https://raw.githubusercontent.com/congdev0109/app-config/main/config.json';
  static const String prefsKey = 'api_base_url';

  final Dio _dio = () {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));
    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback = (_, __, ___) => true;
      return client;
    };
    return dio;
  }();

  /// Nạp baseUrl: ưu tiên giá trị cache (để mạng chậm/mất mạng vẫn vào được app),
  /// sau đó cập nhật lại từ config từ xa nếu lấy được.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Áp dụng cache trước để app luôn có baseUrl hợp lệ ngay lập tức.
    final cached = prefs.getString(prefsKey);
    if (cached != null && cached.isNotEmpty) {
      ApiClient.applyBaseUrl(cached);
    }

    // 2. Lấy cấu hình mới nhất từ xa (best-effort). Lỗi mạng → giữ cache/fallback.
    try {
      final response = await _dio.get(_configUrl);
      final data = response.data;
      final Map<String, dynamic> json = data is Map
          ? Map<String, dynamic>.from(data)
          : Map<String, dynamic>.from(jsonDecode(data.toString()) as Map);

      final apiUrl = (json['api_url'] as String?)?.trim();
      if (apiUrl != null && apiUrl.isNotEmpty) {
        final normalized = _stripTrailingSlash(apiUrl);
        await prefs.setString(prefsKey, normalized);
        ApiClient.applyBaseUrl(normalized);
        if (kDebugMode) print('🌐 RemoteConfig baseUrl → $normalized');
      }
    } catch (e) {
      if (kDebugMode) print('⚠️ RemoteConfig load failed: $e');
    }
  }

  String _stripTrailingSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}
