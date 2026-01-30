class User {
  final String id;
  final String nickname;
  final String phone;
  final String? email;
  final String? avatar;
  final int? role;
  final String? familyId;

  User({
    required this.id,
    required this.nickname,
    required this.phone,
    this.email,
    this.avatar,
    this.role,
    this.familyId,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        nickname: json['nickname'] as String,
        phone: json['phone'] as String,
        email: json['email'] as String?,
        avatar: json['avatar'] as String?,
        role: json['role'] as int,
        familyId: json['familyId'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'nickname': nickname,
        'phone': phone,
        'email': email,
        'avatar': avatar,
        'role': role,
        'familyId': familyId,
      };
}

class UserRole {
  static const int admin = 1;
  static const int member = 0;

  static bool isAdmin(int? role) => role == admin;
  static bool isMember(int? role) => role == member;
}
