import '../../models/category_keyword_rule.dart';
import 'builtin_categories.dart';
import 'category_repository.dart';
import 'category_rule_repository.dart';
import 'current_family_store.dart';

/// 本地分类引擎：账单导入与语音记账共用的离线分类判定。
///
/// 判定顺序（先学习表、后关键词，两者对所有平台一视同仁）：
/// 1. [matchLearned]——用户指认过的文本直接命中其指认分类（命中计数 +1）
/// 2. [classifyKeywords]——内置规则包含命中（JSON 顺序，先命中先得）
/// 全部未命中返回 null，由调用方走「未分类」兜底，不猜测填充具体分类。
///
/// 分类是纯标签：判定结果不再按收支方向过滤（同一分类可同时挂收入与支出），
/// 方向由 transactions.type 单独决定；type=2 不计收支的行由调用方跳过推断。
class CategoryEngine {
  final CategoryRuleRepository _rules;
  final CategoryRepository _categories;

  /// 编译后的内置规则（保持 JSON 顺序，先命中先得）
  final List<_CompiledRule> _builtinRules = [];

  CategoryEngine(
    this._rules,
    this._categories,
    List<CategoryKeywordRule> builtinRules,
  ) {
    // 加载期校验：规则分类名必须是内置分类，坏数据直接抛错（fail fast）
    for (final rule in builtinRules) {
      final builtin = BuiltinCategories.byName(rule.category);
      if (builtin == null) {
        throw StateError('内置规则分类不存在: ${rule.category}');
      }
      _builtinRules.add(_CompiledRule(
        categoryId: builtin.id,
        keywords: [for (final k in rule.keywords) k.toLowerCase()],
        excludeKeywords: [
          for (final k in rule.excludeKeywords) k.toLowerCase()
        ],
      ));
    }
  }

  /// 可用分类 ID 集合（分类被软删后不在集合中，对应学习条目不再命中）。
  /// 家庭维度：内置（全局共享）+ 当前家庭自定义
  Future<Set<String>> loadActiveCategoryIds() async {
    final all = await _categories.listAll(await CurrentFamilyStore.get());
    return {for (final c in all) c.id};
  }

  /// 分类判定：学习表优先，其次内置关键词
  Future<String?> classify(
    List<String?> clues, {
    Set<String>? activeCategoryIds,
  }) async {
    final active = activeCategoryIds ?? await loadActiveCategoryIds();
    final learned = await matchLearned(clues, activeCategoryIds: active);
    if (learned != null) return learned;
    return classifyKeywords(clues, activeCategoryIds: active);
  }

  /// 学习表命中（所有平台通用，含微信）。
  ///
  /// 按线索顺序逐条做归一化精确匹配（交易对方在前、商品名在后），
  /// 命中且分类仍有效时写回命中计数。未命中返回 null。
  Future<String?> matchLearned(
    List<String?> clues, {
    Set<String>? activeCategoryIds,
  }) async {
    final active = activeCategoryIds ?? await loadActiveCategoryIds();
    for (final raw in clues) {
      final clue = raw?.trim() ?? '';
      if (clue.isEmpty) continue;

      final entry = await _rules.findByMatchText(clue);
      if (entry != null && active.contains(entry.categoryId)) {
        await _rules.recordHit(entry.id);
        return entry.categoryId;
      }
    }
    return null;
  }

  /// 内置关键词规则命中（不区分大小写，按规则顺序先命中先得）。
  ///
  /// 规则内命中任一关键词即算命中；但线索文本含该规则的任一排除词时，
  /// 整条规则跳过（排除词用于压掉「医院店」「天然气灶」这类字面反例）。
  Future<String?> classifyKeywords(
    List<String?> clues, {
    Set<String>? activeCategoryIds,
  }) async {
    final active = activeCategoryIds ?? await loadActiveCategoryIds();
    for (final raw in clues) {
      final clue = raw?.trim() ?? '';
      if (clue.isEmpty) continue;

      final lower = clue.toLowerCase();
      for (final rule in _builtinRules) {
        if (!rule.matches(lower)) continue;
        if (active.contains(rule.categoryId)) return rule.categoryId;
      }
    }
    return null;
  }
}

/// 编译后的内置规则：分类 ID + 小写关键词 + 小写排除词
class _CompiledRule {
  final String categoryId;
  final List<String> keywords;
  final List<String> excludeKeywords;

  const _CompiledRule({
    required this.categoryId,
    required this.keywords,
    required this.excludeKeywords,
  });

  bool matches(String lowerText) {
    for (final exclude in excludeKeywords) {
      if (lowerText.contains(exclude)) return false;
    }
    for (final keyword in keywords) {
      if (lowerText.contains(keyword)) return true;
    }
    return false;
  }
}
