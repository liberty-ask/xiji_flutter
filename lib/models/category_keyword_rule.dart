import 'dart:convert';

/// 内置分类关键词规则（随版本发布的静态规则库条目）。
///
/// 匹配语义：包含匹配（不区分大小写）——线索文本包含任一关键词即命中，
/// category 必须是内置分类名，加载时经 BuiltinCategories.byName 解析为固定 ID。
class CategoryKeywordRule {
  final List<String> keywords;
  final String category; // 内置分类名
  final int type; // 0-收入 1-支出

  const CategoryKeywordRule({
    required this.keywords,
    required this.category,
    required this.type,
  });

  factory CategoryKeywordRule.fromJson(Map<String, dynamic> json) {
    return CategoryKeywordRule(
      keywords:
          (json['keywords'] as List<dynamic>).map((e) => e as String).toList(),
      category: json['category'] as String,
      type: json['type'] as int,
    );
  }

  /// 解析规则库 JSON 字符串（assets/category_rules.json 的结构）
  static List<CategoryKeywordRule> parseList(String jsonString) {
    final data = jsonDecode(jsonString) as Map<String, dynamic>;
    return (data['rules'] as List<dynamic>)
        .map((e) => CategoryKeywordRule.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
