import 'package:flutter/services.dart' show rootBundle;

import '../../models/category_keyword_rule.dart';
import 'category_engine.dart';
import 'db_provider.dart';

/// 内置关键词规则库加载器：assets/category_rules.json → 规则列表
class CategoryRuleLoader {
  static const assetPath = 'assets/category_rules.json';

  static Future<List<CategoryKeywordRule>> load() async {
    final json = await rootBundle.loadString(assetPath);
    return CategoryKeywordRule.parseList(json);
  }

  static CategoryEngine? _defaultEngine;

  /// 应用级分类引擎单例：内置规则 + Db 单例仓储。
  /// 账单导入与语音记账（第 4 组）共用同一引擎与学习表
  static Future<CategoryEngine> loadDefaultEngine() async {
    _defaultEngine ??= CategoryEngine(
      Db.categoryRules,
      Db.categories,
      await load(),
    );
    return _defaultEngine!;
  }
}
