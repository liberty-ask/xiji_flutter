class FamilyMemberRole {
  static const int admin = 1;
  static const int member = 0;

  static bool isAdmin(int? role) => role == admin;
  static bool isMember(int? role) => role == member;
}

class FamilyMember {
  final String id;
  final String name;
  final int role;
  final String? avatar; // 改为可空类型
  final String? label;

  FamilyMember({
    required this.id,
    required this.name,
    required this.role,
    this.avatar, // 改为可选参数
    this.label,
  });

  factory FamilyMember.fromJson(Map<String, dynamic> json) => FamilyMember(
        id: json['id'] as String,
        name: json['name'] as String,
        role: json['role'] as int,
        avatar: json['avatar'] as String?, // 处理 null 情况
        label: json['label'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'role': role,
        'avatar': avatar,
        'label': label,
      };
}
