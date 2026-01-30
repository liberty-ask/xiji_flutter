class FamilyRole {
  static const int admin = 1;
  static const int member = 0;

  static bool isAdmin(int? role) => role == admin;
  static bool isMember(int? role) => role == member;
}

class Family {
  final String id;
  final String name;
  final bool isCurrent;
  final int role;
  final String? avatar; // 头像（可选字段）

  Family({
    required this.id,
    required this.name,
    required this.isCurrent,
    required this.role,
    this.avatar,
  });

  factory Family.fromJson(Map<String, dynamic> json) => Family(
        id: json['id'] as String,
        name: json['name'] as String,
        isCurrent: json['isCurrent'] as bool? ?? false,
        role: json['role'] as int,
        avatar: json['avatar'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isCurrent': isCurrent,
        'role': role,
        'avatar': avatar,
      };
}
