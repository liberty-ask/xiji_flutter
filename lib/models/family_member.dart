class FamilyMemberRole {
  static const int admin = 1;
  static const int member = 0;

  static bool isAdmin(int? role) => role == admin;
}

class FamilyMember {
  final String id;
  final String name;
  final int role;
  final String? avatar; // 改为可空类型
  final String? label;

  /// 同步开关投影：1-开启云备份同步，0-休眠（该成员的账单不会上云，
  /// 其他成员无法看到其数据；机制状态明文，仅展示用途）
  final int syncEnabled;

  FamilyMember({
    required this.id,
    required this.name,
    required this.role,
    this.avatar, // 改为可选参数
    this.label,
    this.syncEnabled = 0,
  });

  bool get isSyncing => syncEnabled == 1;

  factory FamilyMember.fromJson(Map<String, dynamic> json) => FamilyMember(
        id: json['id'] as String,
        name: json['name'] as String,
        role: json['role'] as int,
        avatar: json['avatar'] as String?, // 处理 null 情况
        label: json['label'] as String?,
        syncEnabled: (json['syncEnabled'] as int?) ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'role': role,
        'avatar': avatar,
        'label': label,
        'syncEnabled': syncEnabled,
      };
}
