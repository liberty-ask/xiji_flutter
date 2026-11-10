import 'dart:convert';

/// 内置分类关键词规则（随版本发布的静态规则库条目）。
///
/// 匹配语义：包含匹配（不区分大小写）——线索文本包含任一关键词即命中，
/// 但同一规则内只要出现任一 [excludeKeywords] 就整条不命中（用于一线反例，
/// 如「7-ELEVEn(医院店)」不该因「医院」落医疗）。
/// category 必须是内置分类名，加载时经 BuiltinCategories.byName 解析为固定 ID。
/// 分类已中性化，规则不再携带收支类型：方向由 transactions.type 单独决定。
class CategoryKeywordRule {
  final List<String> keywords;
  final List<String> excludeKeywords;
  final String category; // 内置分类名

  const CategoryKeywordRule({
    required this.keywords,
    this.excludeKeywords = const [],
    required this.category,
  });

  factory CategoryKeywordRule.fromJson(Map<String, dynamic> json) {
    return CategoryKeywordRule(
      keywords:
          (json['keywords'] as List<dynamic>).map((e) => e as String).toList(),
      excludeKeywords: ((json['exclude'] as List<dynamic>?) ?? const [])
          .map((e) => e as String)
          .toList(),
      category: json['category'] as String,
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
