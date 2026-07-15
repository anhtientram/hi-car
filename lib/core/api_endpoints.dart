class ApiEndpoints {
  ApiEndpoints._();

  // ⚠️ Base URL (api_url lấy từ remote config) ĐÃ bao gồm hậu tố `/api`.
  //    Vì vậy các endpoint dưới đây KHÔNG được thêm tiền tố `/api` nữa để tránh
  //    bị lặp thành `/api/api/...`.

  // Auth
  static const String loginCode = '/auth/login/';
  static const String loginPhone = '/auth/login/phone/';
  static const String register = '/auth/register/';
  static const String logout = '/auth/logout';
  static const String authMe = '/auth/me';

  // Vehicles
  static const String vehicles = '/vehicles/';
  static const String selectVehicle = '/vehicles/select/';

  // Audio & Sync
  static const String audioList = '/audio/list/';
  static String downloadAudio(String id) => '/audio/download/$id/';

  // Studio (Voice Studio)
  static const String studioTemplates = '/v1/voice/templates/';
  static const String studioPreview = '/v1/voice/preview/';
  static const String studioOrders = '/v1/orders/';
  static String studioRecreate(String orderId) =>
      '/v1/orders/$orderId/recreate/';

  // Logs
  static const String errorLog = '/logs/error/';
}
