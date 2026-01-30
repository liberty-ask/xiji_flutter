import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user.dart';
import '../services/api/api_client.dart';
import '../services/api/auth_service.dart';
import '../services/api/family_service.dart';
import '../utils/constants.dart';

class AuthProvider with ChangeNotifier {
  User? _user;
  bool _isLoading = false;
  bool _isInitialized = false;

  User? get user => _user;
  bool get isAuthenticated => _user != null;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;

  final AuthService _authService = AuthService();
  final ApiClient _apiClient = ApiClient();
  final FamilyService _familyService = FamilyService();

  // 初始化：从存储中恢复用户状态
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // 检查是否有 Token（使用与ApiClient相同的存储配置）
      // 使用与ApiClient相同的FlutterSecureStorage配置，确保Android平台行为一致
      const storage = FlutterSecureStorage(
        aOptions: AndroidOptions(
          encryptedSharedPreferences: true,
        ),
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
      );
      final token = await storage.read(key: AppConstants.tokenKey);
      
      if (token != null && token.isNotEmpty) {
        // 有 Token，尝试恢复用户信息
        try {
          await refreshUser();
        } catch (e) {
          // refreshUser 失败，但不清空 Token
          // 可能是网络问题或临时错误，保留 Token 允许用户继续使用
          // 只有当明确知道是401错误（Token无效）时才清空
          final errorStr = e.toString().toLowerCase();
          // 检查是否是401未授权错误
          if (errorStr.contains('未授权') || 
              errorStr.contains('未授权，请重新登录') ||
              errorStr.contains('unauthorized') ||
              errorStr.contains('401')) {
            // Token 确实无效，清空 Token 和用户信息
            await _apiClient.removeToken();
            _user = null;
          } else {
            // 其他错误（如网络问题、超时等），保留 Token
            // 不清空用户信息，允许后续 API 调用尝试恢复
            // 这允许用户在网络恢复后继续使用应用，而不是被迫重新登录
            // 注意：此时 _user 可能为 null，但在后续 API 调用成功时会自动恢复
          }
        }
      }
    } catch (e) {
      // 读取 Token 失败，可能是存储访问问题
      // 不影响初始化流程，只是无法恢复登录状态
      _user = null;
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  // 登录
  Future<void> login(String account, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _authService.login(
        account: account,
        password: password,
      );

      await _apiClient.setToken(result['token'] as String);
      
      await refreshUser();
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 验证码登录
  Future<void> loginWithCode(String phone, String code) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _authService.login(
        phone: phone,
        code: code,
      );

      await _apiClient.setToken(result['token'] as String);
      
      await refreshUser();
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 刷新用户信息
  Future<void> refreshUser() async {
    try {
      final userData = await _familyService.getUserProfile();
      _user = User(
        id: userData['id'] ?? userData['familyId'] ?? '',
        nickname: userData['nickname'] ?? '',
        phone: userData['phone'] ?? '',
        email: userData['email'],
        avatar: userData['avatar'],
        role: userData['role'] != null ? (userData['role'] is String ? int.tryParse(userData['role'] as String) : userData['role'] as int) : null,
        familyId: userData['familyId'],
      );
    } catch (e) {
      _user = null;
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  // 使用注册返回的数据设置用户信息（注册接口直接返回用户数据）
  // registerResult 已经是 ApiClient._handleResponse 提取的 data 字段内容
  Future<void> setUserFromRegisterResponse(Map<String, dynamic> registerResult) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      final token = registerResult['token'] as String?;
      final userData = registerResult['user'] as Map<String, dynamic>?;
      
      if (token != null) {
        await _apiClient.setToken(token);
      }
      
      if (userData != null) {
        _user = User(
        id: userData['id'] as String? ?? '',
        nickname: userData['nickname'] as String? ?? '',
        phone: userData['phone'] as String? ?? '',
        email: userData['email'] as String?,
        avatar: userData['avatar'] as String?,
        role: userData['role'] != null ? (userData['role'] is String ? int.tryParse(userData['role'] as String) : userData['role'] as int) : null,
        familyId: userData['familyId'] as String?,
      );
      }
    } catch (e) {
      _user = null;
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 登出
  Future<void> logout() async {
    await _apiClient.removeToken();
    _user = null;
    notifyListeners();
  }
}
