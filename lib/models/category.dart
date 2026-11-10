class Category {
  final String id;
  final String name;
  final String icon; // Material Icons 名称
  // 多语言词条 key：内置分类非空，用户自建分类为 null（显示原文）
  final String? nameKey;

  /// 展示顺序（内置 0–24，自建从 25 起）；仅用于选择器稳定排序
  final int sortOrder;

  Category({
    required this.id,
    required this.name,
    required this.icon,
    this.nameKey,
    this.sortOrder = 0,
  });

  /// 兼容旧字段：旧数据里的 type 直接忽略（分类已中性化）
  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as String,
        name: json['name'] as String,
        icon: json['icon'] as String,
        nameKey: json['nameKey'] as String?,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'nameKey': nameKey,
        'sortOrder': sortOrder,
      };
}
