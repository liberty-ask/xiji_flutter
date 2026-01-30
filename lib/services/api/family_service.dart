import 'api_client.dart';
import '../../models/family_member.dart';
import '../../models/application.dart';
import '../../models/family.dart';

class FamilyService {
  // 单例实例
  static FamilyService? _instance;
  
  final ApiClient _api = ApiClient();
  
  // 私有构造函数
  FamilyService._internal();
  
  // 获取单例实例
  factory FamilyService() {
    _instance ??= FamilyService._internal();
    return _instance!;
  }

  // 获取家庭列表
  Future<List<Family>> getFamiliesList() async {
    final result = await _api.get('/v1/families/list');
    final List<dynamic> list = result as List<dynamic>;
    return list.map((json) => Family.fromJson(json as Map<String, dynamic>)).toList();
  }

  // 切换家庭
  Future<void> switchFamily(String familyId) async {
    await _api.post('/v1/families/switch', data: {
      'familyId': familyId,
    });
  }

  // 获取家庭成员列表
  Future<List<FamilyMember>> getMembers() async {
    final result = await _api.get('/v1/families/members');
    final List<dynamic> list = result as List<dynamic>;
    return list.map((json) => FamilyMember.fromJson(json as Map<String, dynamic>)).toList();
  }

  // 获取待审核申请列表
  Future<List<Application>> getPendingApplications() async {
    final result = await _api.get('/v1/families/pending-applications');
    final List<dynamic> list = result as List<dynamic>;
    return list.map((json) => Application.fromJson(json as Map<String, dynamic>)).toList();
  }

  // 处理申请（批准或拒绝）
  Future<void> processApplication(String id, String action) async {
    await _api.post('/v1/families/process-application', data: {
      'id': id,
      'action': action, // 'approve' 或 'reject'
    });
  }

  // 获取用户信息
  Future<Map<String, dynamic>> getUserProfile() async {
    return await _api.get('/v1/user/profile');
  }

  // 修改密码
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _api.post('/v1/user/change-password', data: {
      'oldPassword': oldPassword,
      'newPassword': newPassword,
    });
  }

  // 退出家庭
  Future<void> exitFamily() async {
    await _api.post('/v1/families/exit');
  }

  // 更新用户资料
  Future<void> updateProfile({
    String? nickname,
    String? avatar,
    String? email,
  }) async {
    final data = <String, dynamic>{};
    if (nickname != null) data['nickname'] = nickname;
    if (avatar != null) data['avatar'] = avatar;
    if (email != null) data['email'] = email;
    
    await _api.post('/v1/user/profile', data: data);
  }

  // 上传文件（支持XFile和File）
  Future<String> uploadFile(dynamic file) async {
    return await _api.uploadFile('/v1/upload/file', file);
  }

  // 申请加入家庭
  Future<void> applyToFamily({
    required String familyId,
    required String note,
  }) async {
    await _api.post('/v1/families/apply', data: {
      'familyId': familyId,
      'note': note,
    });
  }
}

