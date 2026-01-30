class Category {
  final String id;
  final String name;
  final String icon; // Material Icons 名称
  final int type; // 0-收入(INCOME), 1-支出(EXPENSE)

  Category({
    required this.id,
    required this.name,
    required this.icon,
    required this.type,
  });

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as String,
        name: json['name'] as String,
        icon: json['icon'] as String,
        type: json['type'] as int,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'type': type,
      };
}

