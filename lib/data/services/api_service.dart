import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import '../../core/api_endpoints.dart';

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  final _client = ApiClient.instance;

  // ===== AUTH =====

  /// Đăng nhập bằng mã kích hoạt hoặc số điện thoại.
  /// API: POST /api/auth/login
  Future<Map<String, dynamic>> login({
    String? code,
    String? phone,
    String? password,
    Map<String, String>? deviceContext,
  }) async {
    final payload = {
      if (code != null) 'code': code,
      if (phone != null) 'phone': phone,
      if (password != null) 'password': password,
      ...?deviceContext,
    };

    // Note: Some Laravel servers might redirect without trailing slash or due to www/non-www.
    // We use the exact path as defined in api.md.
    final path =
        phone != null ? ApiEndpoints.loginPhone : ApiEndpoints.loginCode;
    final response = await _client.post(path, data: payload);

    final data = response.data['data'];
    final token = data['token'];

    // Save token for persistent auth
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);

    return data;
  }

  /// Lấy thông tin tài khoản hiện tại (xác thực token còn hiệu lực).
  /// API: GET /api/auth/me
  Future<Map<String, dynamic>> getMe() async {
    final response = await _client.get(
      ApiEndpoints.authMe,
      skipAuthRedirect: true,
    );
    final data = response.data['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  /// Đăng xuất tài khoản.
  /// API: POST /api/auth/logout
  Future<void> logout() async {
    try {
      await _client.post(ApiEndpoints.logout);
    } catch (_) {
      // Don't block logout if API call fails
    }
  }

  /// Đăng ký tài khoản mới.
  Future<Map<String, dynamic>> signup({
    required String phone,
    required String name,
    required String password,
    required String licensePlate,
  }) async {
    final response = await _client.post(ApiEndpoints.register, data: {
      'phone': phone,
      'name': name,
      'password': password,
      'license_plate': licensePlate,
    });
    return response.data['data'] ?? {};
  }

  // ===== VEHICLES =====

  /// Lấy danh sách xe khả dụng.
  /// API: GET /api/vehicles
  Future<List<dynamic>> getVehicles() async {
    final response = await _client.get(ApiEndpoints.vehicles, useCache: true);
    return response.data['data'] ?? [];
  }

  /// Chọn xe vận hành.
  /// API: POST /api/vehicles/select
  Future<void> selectVehicle(int vehicleId) async {
    await _client
        .post(ApiEndpoints.selectVehicle, data: {'vehicle_id': vehicleId});
  }

  // ===== AUDIO LIST =====

  /// Lấy danh sách nhạc đồng bộ.
  /// API: GET /api/audio/list
  Future<List<dynamic>> getAudioList() async {
    final response = await _client.get(ApiEndpoints.audioList);
    return response.data['data'] ?? [];
  }

  // ===== STUDIO (VOICE GEN) =====

  /// Lấy danh sách Template, Giọng đọc & Nhạc nền.
  /// API: GET /api/v1/voice/templates
  Future<Map<String, dynamic>> getStudioTemplates() async {
    final response =
        await _client.get(ApiEndpoints.studioTemplates, useCache: true);
    return response.data['data'] ?? {};
  }

  /// Tạo bản nghe thử nháp.
  /// API: POST /api/v1/voice/preview
  Future<Map<String, dynamic>> previewVoice(Map<String, dynamic> params) async {
    final response =
        await _client.post(ApiEndpoints.studioPreview, data: params);
    return response.data['data'] ?? {};
  }

  /// Đặt mua lời chào.
  /// API: POST /api/v1/orders
  Future<Map<String, dynamic>> createOrder(Map<String, dynamic> params) async {
    final response =
        await _client.post(ApiEndpoints.studioOrders, data: params);
    return response.data['data'] ?? {};
  }

  /// Tạo lại đơn hàng (miễn phí trong 24h).
  /// API: POST /api/v1/orders/{id}/recreate
  Future<Map<String, dynamic>> recreateOrder(
      String orderId, Map<String, dynamic> params) async {
    final response =
        await _client.post(ApiEndpoints.studioRecreate(orderId), data: params);
    return response.data['data'] ?? {};
  }

  /// (Legacy support) Tạo audio từ text.
  Future<Map<String, dynamic>> generateAudio({
    required String ownerName,
    required String licensePlate,
    required String carBrand,
    required String type,
  }) async {
    final response = await _client.post('/audio/generate', data: {
      'owner_name': ownerName,
      'license_plate': licensePlate,
      'car_brand': carBrand,
      'type': type,
    });
    return response.data['data'] ?? {};
  }

  // ===== LOGGING =====

  /// Gửi log lỗi lên server.
  /// API: POST /api/logs/error
  Future<void> logError(Map<String, dynamic> errorData) async {
    await _client.post(ApiEndpoints.errorLog, data: errorData);
  }
}
