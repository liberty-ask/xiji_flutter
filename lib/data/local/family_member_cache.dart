import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/family_member.dart';
import 'local_user.dart';

/// 家庭成员列表本地缓存（离线优先）。
///
/// 键：`family_members@<userId>@<familyId>`——成员归属家庭，同一用户在不同
/// 家庭的 role/syncEnabled 可能不同，必须按家庭隔离；同时带账号后缀，
/// 多账号切换不串数据。
/// 值：`List<FamilyMember>` 的 JSON（含 id/name/role/avatar/label/
/// syncEnabled/publicKey），断网时足以还原成员列表与 X/N 统计口径。
class FamilyMemberCache {
  FamilyMemberCache._();

  static const _keyPrefix = 'family_members@';

  static Future<String> _key(String familyId) async {
    final user = await LocalUser.load();
    return '$_keyPrefix${user?.id ?? ''}@$familyId';
  }

  /// 覆盖式写入某家庭的成员列表（拉取成功时调用）
  static Future<void> save(String familyId, List<FamilyMember> members) async {
    // 家庭未就绪（空 ID）不落盘，避免写成所有家庭共用的脏键
    if (familyId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      await _key(familyId),
      jsonEncode(members.map((m) => m.toJson()).toList()),
    );
  }

  /// 读取某家庭的成员缓存（无缓存/损坏返回 null）
  static Future<List<FamilyMember>?> load(String familyId) async {
    if (familyId.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(await _key(familyId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => FamilyMember.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// 网络优先、失败回退缓存：成功落盘；失败且无缓存时原样抛错。
  static Future<List<FamilyMember>> fetchWithFallback({
    required String familyId,
    required Future<List<FamilyMember>> Function() fetch,
  }) async {
    try {
      final members = await fetch();
      await save(familyId, members);
      return members;
    } catch (_) {
      final cached = await load(familyId);
      if (cached != null) return cached;
      rethrow;
    }
  }

  /// 登出清空全部账号/家庭维度缓存。
  /// 此时 LocalUser 可能已被清除，按键前缀删除而非依赖当前 userId。
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where((k) => k.startsWith(_keyPrefix))
        .toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}
