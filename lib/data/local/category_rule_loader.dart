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
  static int _generation = -1;

  /// 应用级分类引擎单例：内置规则 + Db 单例仓储。
  /// 账单导入与语音记账（第 4 组）共用同一引擎与学习表。
  /// 随库世代自动重绑：Db.close() 后（登出/账号切换）重开新库时
  /// 重建引擎，防止持有已关闭旧库的引用。
  static Future<CategoryEngine> loadDefaultEngine() async {
    final g = Db.generation;
    if (_defaultEngine == null || _generation != g) {
      _defaultEngine = CategoryEngine(
        Db.categoryRules,
        Db.categories,
        await load(),
      );
      _generation = g;
    }
    return _defaultEngine!;
  }
}
