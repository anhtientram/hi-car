import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/device_utils.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../../core/constants.dart';
import '../../native/service_channel.dart';

enum SessionValidation { noToken, valid, invalid, offline }

class AuthRepository {
  AuthRepository._();
  static final AuthRepository instance = AuthRepository._();

  Future<UserModel> signup({
    required String phone,
    required String name,
    required String password,
    required String licensePlate,
  }) async {
    final response = await ApiService.instance.signup(
      phone: phone,
      name: name,
      password: password,
      licensePlate: licensePlate,
    );

    final user =
        UserModel.fromJson(response['driver'] ?? response['user'] ?? response);
    await _saveUser(user);
    return user;
  }

  Future<UserModel> login({
    String? code,
    String? phone,
    String? password,
  }) async {
    // Collect real device info using utility
    final deviceContext = await DeviceUtils.GetDeviceContext();

    final response = await ApiService.instance.login(
      code: code,
      phone: phone,
      password: password,
      deviceContext: deviceContext,
    );

    final user = UserModel.fromJson(response);
    await _saveUser(user);
    return user;
  }

  // ===== Logout =====

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    // Auth & User
    await prefs.remove(AppConstants.keyAuthToken);
    await prefs.remove(AppConstants.keyUserData);

    // Audio Metadata — sẽ được tải lại ở lần đồng bộ sau.
    await prefs.remove(AppConstants.keyAudioList);
    await prefs.remove('cached_audio_list');

    // ⚠️ KHÔNG xoá lựa chọn lời chào/tạm biệt ở đây. Đăng xuất rồi đăng nhập lại cùng tài
    // khoản mà mất cấu hình thì app tự chọn đại một bài khác trong danh sách → khách phản
    // ánh "hôm sau xe phát nhạc lạ". Đổi sang tài khoản KHÁC đã được xử lý riêng ở
    // _clearAudioSelectionIfAccountChanged khi lưu người dùng mới.

    // Others
    await prefs.remove(AppConstants.keyLastSyncTime);
  }

  /// Đăng xuất mềm khi token hết hạn: giữ danh sách nhạc + cấu hình lời chào/tạm biệt.
  Future<void> softLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.keyAuthToken);
    await prefs.remove(AppConstants.keyUserData);
  }

  /// Huỷ phiên: xoá token prefs + device-protected (Box boot không tự phát).
  Future<void> expireSession() async {
    await softLogout();
    try {
      await ServiceChannel.instance
          .clearAuthState()
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  /// Gọi GET /api/auth/me để xác minh token còn hợp lệ trên server.
  Future<SessionValidation> validateSession() async {
    if (!await isLoggedIn()) return SessionValidation.noToken;

    try {
      final me = await ApiService.instance.getMe();
      if (me.isEmpty) return SessionValidation.invalid;

      final isActive = me['is_active'];
      if (isActive == false) return SessionValidation.invalid;

      await _refreshUserFromMe(me);
      return SessionValidation.valid;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403 || code == 404) {
        return SessionValidation.invalid;
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.connectionError) {
        return SessionValidation.offline;
      }
      return SessionValidation.offline;
    } catch (_) {
      return SessionValidation.offline;
    }
  }

  // ===== Check Auth =====

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.keyAuthToken) != null;
  }

  Future<UserModel?> getStoredUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString(AppConstants.keyUserData);
    if (userData == null) return null;
    try {
      return UserModel.fromJsonString(userData);
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteAccount() async {
    // Note: Implementation usually calls an API to delete data then log out.
    await logout();
  }

  // ===== Private =====

  Future<void> _saveUser(UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    await _clearAudioSelectionIfAccountChanged(prefs, user.id);
    if (user.token != null) {
      await prefs.setString(AppConstants.keyAuthToken, user.token!);
    }
    await prefs.setString(AppConstants.keyUserData, user.toJsonString());
  }

  /// Đăng nhập bằng tài khoản KHÁC → bỏ lựa chọn lời chào/tạm biệt của tài khoản trước.
  ///
  /// Đăng nhập lại vẫn giữ nguyên cấu hình (cùng id → không làm gì). Nhưng nếu đổi tài
  /// khoản mà vẫn giữ, id lời chào cũ sẽ không có trong danh sách mới, còn file đã ghim
  /// (`active_greeting.mp3` / `boot_greeting.mp3`) vẫn là nhạc của người trước → xe phát
  /// nhầm giọng của tài khoản cũ.
  Future<void> _clearAudioSelectionIfAccountChanged(
    SharedPreferences prefs,
    String userId,
  ) async {
    if (userId.isEmpty) return;
    final previous = prefs.getString(AppConstants.keyLastAccountId);
    await prefs.setString(AppConstants.keyLastAccountId, userId);
    if (previous == null || previous == userId) return;

    for (final key in [
      AppConstants.keyGreetingAudioId,
      AppConstants.keyGoodbyeAudioId,
      AppConstants.keyGreetingAudioPath,
      AppConstants.keyGoodbyeAudioPath,
      AppConstants.keyAudioList,
      'cached_audio_list',
      AppConstants.keyGreetingClearedByUser,
    ]) {
      await prefs.remove(key);
    }

    try {
      await ServiceChannel.instance
          .clearGreetingConfig()
          .timeout(const Duration(seconds: 2));
      await ServiceChannel.instance
          .clearGoodbyeConfig()
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  Future<void> _refreshUserFromMe(Map<String, dynamic> me) async {
    final stored = await getStoredUser();
    if (stored == null) return;

    final updated = stored.copyWith(
      id: (me['id'] ?? stored.id).toString(),
      name: me['name'] as String? ?? stored.name,
      phone: me['phone'] as String? ?? stored.phone,
      avatarUrl: me['avatar'] as String? ?? stored.avatarUrl,
    );
    await _saveUser(updated);
  }
}
