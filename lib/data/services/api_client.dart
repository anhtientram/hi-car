import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/logger.dart';
import '../../core/app_router.dart';
import '../repositories/auth_repository.dart';

/// Performance-optimized API Client with memory caching and Bearer Auth.
class ApiClient {
  /// Base URL mặc định (fallback) khi chưa lấy được cấu hình từ xa.
  /// api_url đã bao gồm hậu tố `/api` nên các endpoint KHÔNG lặp lại tiền tố này.
  static const String fallbackBaseUrl =
      'https://admintts.chaoxechuanthuonggia.com/api';

  /// Base URL đang dùng (có thể được RemoteConfigService cập nhật lúc mở app).
  static String baseUrl = fallbackBaseUrl;

  /// Cập nhật baseUrl động (gọi từ RemoteConfigService). An toàn khi gọi trước
  /// hoặc sau khi [instance] được khởi tạo.
  static void applyBaseUrl(String url) {
    baseUrl = url;
    if (_maybeInstance != null) {
      _maybeInstance!._dio.options.baseUrl = url;
    }
  }

  static ApiClient? _maybeInstance;

  late final Dio _dio;
  final Map<String, dynamic> _memoryCache = {};

  // Singleton
  ApiClient._() {
    _maybeInstance = this;
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ));

    // Fix for some older Android devices with outdated certificates
    (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
      return client;
    };

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('auth_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        if (kDebugMode) {
          print('🚀 API Request: [${options.method}] ${options.path}');
          if (options.data != null) print('📦 Request Data: ${options.data}');
          if (options.queryParameters.isNotEmpty)
            print('🔍 Query Params: ${options.queryParameters}');
        }
        return handler.next(options);
      },
      onResponse: (response, handler) {
        if (kDebugMode) {
          print(
              '✅ API Response: [${response.statusCode}] ${response.requestOptions.path}');
          print('📄 Response Data: ${response.data}');
        }
        return handler.next(response);
      },
      onError: (DioException e, handler) async {
        if (kDebugMode) {
          print(
              '❌ API Error: [${e.response?.statusCode}] ${e.requestOptions.path}');
          if (e.response?.data != null)
            print('❗ Error Data: ${e.response?.data}');
          print('💡 Message: ${e.message}');
        }

        // Capture in local logs
        AppLogger.instance.log(
          'Lỗi mạng: [${e.response?.statusCode}] ${e.requestOptions.path}',
          type: 'network_error',
          details: {
            'statusCode': e.response?.statusCode,
            'path': e.requestOptions.path,
            'data': e.response?.data,
            'message': e.message,
          },
        );

        // Token hết hạn / bị thu hồi: đăng xuất mềm — giữ nhạc local, chỉ xoá session.
        final skipRedirect =
            e.requestOptions.extra['skipAuthRedirect'] == true;
        if (e.response?.statusCode == 401 && !skipRedirect) {
          await AuthRepository.instance.expireSession();

          AppRouter.router.go('/login');

          if (kDebugMode) {
            print('🚨 SESSION EXPIRED: Redirecting to login (local audio kept)...');
          }
        }
        return handler.next(e);
      },
    ));
  }

  static final ApiClient instance = ApiClient._();

  // ===== Cached Methods (Memory Cache) =====

  Future<Response> get(String path,
      {Map<String, dynamic>? queryParameters,
      bool useCache = false,
      bool skipAuthRedirect = false}) async {
    final cacheKey = '$path${queryParameters?.toString() ?? ''}';

    if (useCache && _memoryCache.containsKey(cacheKey)) {
      if (kDebugMode) print('⏺ Using Memory Cache for: $cacheKey');
      return _memoryCache[cacheKey];
    }

    try {
      final response = await _dio.get(
        path,
        queryParameters: queryParameters,
        options: Options(extra: {'skipAuthRedirect': skipAuthRedirect}),
      );
      if (useCache) _memoryCache[cacheKey] = response;
      return response;
    } catch (e) {
      rethrow;
    }
  }

  Future<Response> post(String path, {dynamic data}) async {
    try {
      final response = await _dio.post(path, data: data);
      // Clear relevant cache on POST (data might have changed)
      _memoryCache.clear();
      return response;
    } catch (e) {
      rethrow;
    }
  }

  void clearCache() => _memoryCache.clear();

  static String formatError(dynamic e) {
    if (e is DioException) {
      // 1. Try to extract message from response body
      if (e.response?.data != null) {
        final data = e.response?.data;
        if (data is Map) {
          if (data.containsKey('message') && data['message'] != null) {
            return data['message'].toString();
          }
          if (data.containsKey('error') && data['error'] != null) {
            return data['error'].toString();
          }
          // Nesting support: { "data": { "message": "..." } }
          if (data.containsKey('data') && data['data'] is Map) {
            final nestedData = data['data'] as Map;
            if (nestedData.containsKey('message') &&
                nestedData['message'] != null) {
              return nestedData['message'].toString();
            }
          }
        } else if (data is String && data.isNotEmpty && data.length < 200) {
          return data;
        }
      }

      // 2. Fallback to DioException types
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Kết nối máy chủ quá hạn. Vui lòng thử lại.';
        case DioExceptionType.connectionError:
          return 'Không có kết nối internet.';
        case DioExceptionType.badResponse:
          final code = e.response?.statusCode;
          if (code == 401)
            return 'Phiên đăng nhập hết hạn. Vui lòng đăng nhập lại.';
          if (code == 403) return 'Bạn không có quyền thực hiện hành động này.';
          if (code == 404) return 'Không tìm thấy máy chủ.';
          if (code == 500) return 'Lỗi máy chủ hệ thống (500).';
          return 'Lỗi phản hồi từ máy chủ ($code).';
        default:
          return 'Lỗi hệ thống (${e.response?.statusCode ?? "Network"}).';
      }
    }
    final errorStr = e.toString().replaceFirst('Exception: ', '');
    return errorStr.length > 200 ? 'Lỗi hệ thống không xác định' : errorStr;
  }
}
