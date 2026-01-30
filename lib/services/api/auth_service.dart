import 'api_client.dart';

class AuthService {
  // 单例实例
  static AuthService? _instance;
  
  final ApiClient _api = ApiClient();
  
  // 私有构造函数
  AuthService._internal();
  
  // 获取单例实例
  factory AuthService() {
    _instance ??= AuthService._internal();
    return _instance!;
  }

  // 发送登录验证码
  Future<void> sendLoginCode(String phone) async {
    await _api.post('/v1/auth/send-code', data: {'phone': phone});
  }

  // 登录
  Future<Map<String, dynamic>> login({
    String? account,
    String? password,
    String? phone,
    String? code,
  }) async {
    final data = <String, dynamic>{};
    if (account != null && password != null) {
      data['account'] = account;
      data['password'] = password;
    } else if (phone != null && code != null) {
      data['phone'] = phone;
      data['code'] = code;
    }

    return await _api.post('/v1/auth/login', data: data);
  }

  // 发送注册验证码
  Future<void> sendRegisterCode(String phone) async {
    await _api.post('/v1/auth/register/send-code', data: {'phone': phone});
  }

  // 注册
  Future<Map<String, dynamic>> register({
    required String phone,
    required String code,
    required String password,
    required String nickname,
  }) async {
    return await _api.post('/v1/auth/register', data: {
      'phone': phone,
      'code': code,
      'password': password,
      'nickname': nickname,
    });
  }

  // 发送忘记密码验证码
  Future<void> sendForgotPasswordCode(String phone) async {
    await _api.post('/v1/auth/forgot-password/send-code', data: {'phone': phone});
  }

  // 重置密码
  Future<void> resetPassword({
    required String phone,
    required String code,
    required String newPassword,
  }) async {
    await _api.post('/v1/auth/forgot-password/reset', data: {
      'phone': phone,
      'code': code,
      'newPassword': newPassword,
    });
  }
}
