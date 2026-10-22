import '../../models/category_keyword_rule.dart';
import 'builtin_categories.dart';
import 'category_repository.dart';
import 'category_rule_repository.dart';
import 'current_family_store.dart';

/// 本地分类引擎：账单导入与语音记账共用的离线分类判定。
///
/// 判定顺序（对每条线索，交易对方在前、商品名在后）：
/// 1. 学习表精确命中——用户指认过的文本直接命中其指认分类（命中计数 +1）
/// 2. 内置规则包含命中——随版本发布的关键词库，先命中先得（JSON 顺序）
/// 全部未命中返回 null，由调用方走「未分类」兜底，不猜测填充具体分类。
///
/// expectedType：分类类型过滤（0-收入 1-支出），防止支出线索命中收入分类
/// （如退款行命中商户的支出学习条目）。type=2（不计收支）记录沿用支出侧
/// 分类，与既有服务端语义一致。
class CategoryEngine {
  final CategoryRuleRepository _rules;
  final CategoryRepository _categories;

  /// 小写关键词 → 内置分类 ID（按规则顺序展开，先到先得）
  final Map<String, String> _builtinKeywordToId = {};

  CategoryEngine(
    this._rules,
    this._categories,
    List<CategoryKeywordRule> builtinRules,
  ) {
    // 加载期校验：规则分类名必须是内置分类，坏数据直接抛错（fail fast）
    for (final rule in builtinRules) {
      final builtin = BuiltinCategories.byName(rule.category, rule.type);
      if (builtin == null) {
        throw StateError('内置规则分类不存在: ${rule.category}(type=${rule.type})');
      }
      for (final keyword in rule.keywords) {
        _builtinKeywordToId.putIfAbsent(
            keyword.toLowerCase(), () => builtin.id);
      }
    }
  }

  /// 全量分类 ID → 类型缓存（分类被软删后不在缓存中，对应学习条目不再命中）。
  /// 家庭维度：内置（全局共享）+ 当前家庭自定义
  Future<Map<String, int>> loadCategoryTypeCache() async {
    final all =
        await _categories.listAll(await CurrentFamilyStore.get());
    return {for (final c in all) c.id: c.type};
  }

  /// 分类判定：返回命中的分类 ID，未命中返回 null
  Future<String?> classify(
    List<String?> clues, {
    int? expectedType,
    Map<String, int>? categoryTypeCache,
  }) async {
    final cache = categoryTypeCache ?? await loadCategoryTypeCache();

    for (final raw in clues) {
      final clue = raw?.trim() ?? '';
      if (clue.isEmpty) continue;

      // 1. 学习表精确命中
      final entry = await _rules.findByMatchText(clue);
      if (entry != null && _typeOk(cache[entry.categoryId], expectedType)) {
        await _rules.recordHit(entry.id);
        return entry.categoryId;
      }

      // 2. 内置规则包含命中（不区分大小写）
      final lower = clue.toLowerCase();
      for (final kw in _builtinKeywordToId.keys) {
        if (!lower.contains(kw)) continue;
        final categoryId = _builtinKeywordToId[kw]!;
        final type = BuiltinCategories.byId(categoryId)!.type;
        if (_typeOk(type, expectedType)) return categoryId;
      }
    }
    return null;
  }

  bool _typeOk(int? actualType, int? expectedType) {
    if (actualType == null) return false; // 分类已删除/未知
    if (expectedType == null) return true;
    return actualType == expectedType;
  }
}
