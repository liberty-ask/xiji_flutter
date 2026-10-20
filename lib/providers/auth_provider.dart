import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/user.dart';
import '../services/api/api_client.dart';
import '../services/api/auth_service.dart';
import '../services/api/family_service.dart';

/// 认证状态管理
///
/// 乐观认证：本地存有token即视为已登录（_hasToken），用户资料(_user)降级为缓存，
/// 拉取失败不清凭证；唯一强制登出路径是refresh token被服务端确认无效。
class AuthProvider with ChangeNotifier {
  User? _user;
  bool _hasToken = false;
  bool _isLoading = false;
  bool _isInitialized = false;

  final AuthService _authService = AuthService();
  final FamilyService _familyService = FamilyService();
  final ApiClient _apiClient = ApiClient();

  AuthProvider() {
    // 注册全局会话过期回调：refresh确认无效时强制登出（跳转由路由守卫自动完成）
    ApiClient.onSessionExpired = _onSessionExpired;
  }

  User? get user => _user;

  /// 登录态：本地凭证存在性判定（乐观认证，离线可进主界面）
  bool get isAuthenticated => _hasToken;

  bool get isLoading => _isLoading;

  bool get isInitialized => _isInitialized;

  /// 强制登出：清双token与登录态（会话过期唯一路径，幂等）
  Future<void> _onSessionExpired() async {
    await _apiClient.removeToken();
    _hasToken = false;
    _user = null;
    notifyListeners();
  }

  /// 初始化：读取本地凭证，有token即置登录态，资料异步拉取
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      final token = await _apiClient.getToken();
      if (token != null && token.isNotEmpty) {
        _hasToken = true;
        // 资料拉取失败不影响登录态（凭证生命周期由刷新链路管理）
        unawaited(refreshUser().catchError((_) {}));
      }
    } catch (_) {
      _hasToken = false;
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// 刷新用户资料（资料作为缓存，失败保留上次内容）
  Future<void> refreshUser() async {
    try {
      final userData = await _familyService.getUserProfile();
      _user = User.fromJson(userData);
    } catch (e) {
      debugPrint('获取用户信息失败: $e');
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  /// 密码登录
  Future<void> login(String account, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _authService.login(
        account: account,
        password: password,
      );

      await _apiClient.setTokens(
        result['accessToken'] as String,
        result['refreshToken'] as String,
      );
      _hasToken = true;
      await refreshUser();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 验证码登录
  Future<void> loginWithCode(String phone, String code) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _authService.login(
        phone: phone,
        code: code,
      );

      await _apiClient.setTokens(
        result['accessToken'] as String,
        result['refreshToken'] as String,
      );
      _hasToken = true;
      await refreshUser();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 从注册响应中提取用户信息和token（注册成功自动登录）
  Future<void> setUserFromRegisterResponse(
      Map<String, dynamic> registerResult) async {
    _isLoading = true;
    notifyListeners();

    try {
      final accessToken = registerResult['accessToken'] as String?;
      final refreshToken = registerResult['refreshToken'] as String?;
      if (accessToken != null && refreshToken != null) {
        await _apiClient.setTokens(accessToken, refreshToken);
        _hasToken = true;
      }

      if (registerResult['user'] != null) {
        _user = User.fromJson(registerResult['user']);
      } else {
        _user = null;
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 登出：服务端全端撤销（尽力而为，失败不阻断本地登出）
  Future<void> logout() async {
    try {
      await _authService.logout();
    } catch (_) {
      // 服务端撤销失败（含网络问题）时仍完成本地登出
    }
    await _onSessionExpired();
  }
}
