import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiji_flutter/data/local/app_database.dart';
import 'package:xiji_flutter/data/local/builtin_categories.dart';
import 'package:xiji_flutter/data/local/category_engine.dart';
import 'package:xiji_flutter/data/local/category_repository.dart';
import 'package:xiji_flutter/data/local/category_rule_repository.dart';
import 'package:xiji_flutter/models/category_keyword_rule.dart';

void main() {
  late AppDatabase db;
  late CategoryRepository categories;
  late CategoryRuleRepository rules;
  late CategoryEngine engine;

  // 内置规则（测试内固定样例，与 asset 结构一致）
  final testRules = CategoryKeywordRule.parseList('''
  {
    "rules": [
      { "keywords": ["瑞幸", "星巴克"], "category": "餐饮", "type": 1 },
      { "keywords": ["Steam"], "category": "娱乐", "type": 1 },
      { "keywords": ["工资"], "category": "工资", "type": 0 }
    ]
  }
  ''');

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    categories = CategoryRepository(db);
    rules = CategoryRuleRepository(db);
    engine = CategoryEngine(rules, categories, testRules);
  });

  tearDown(() async {
    await db.close();
  });

  // 常量引用：内置分类固定 ID
  final diningId = BuiltinCategories.byName('餐饮', 1)!.id;
  final entertainmentId = BuiltinCategories.byName('娱乐', 1)!.id;
  final salaryId = BuiltinCategories.byName('工资', 0)!.id;

  group('任务 3.1：内置关键词规则库匹配逻辑', () {
    test('命中：交易对方包含关键词 → 对应内置分类 ID', () async {
      final hit = await engine.classify(['瑞幸咖啡（杭州）有限公司'],
          expectedType: 1);
      expect(hit, diningId);
    });

    test('未命中：无线索文本返回 null（不猜测填充）', () async {
      final hit = await engine.classify(['完全陌生的商户'], expectedType: 1);
      expect(hit, isNull);
    });

    test('多线索顺序：交易对方未命中时回退商品名线索', () async {
      final hit = await engine.classify(['陌生商户', '买了一杯星巴克拿铁'],
          expectedType: 1);
      expect(hit, diningId);
    });

    test('不区分大小写：Steam/stEAm 均命中娱乐', () async {
      expect(
          await engine.classify(['Steam 平台充值'], expectedType: 1),
          entertainmentId);
      expect(
          await engine.classify(['stEAm 平台充值'], expectedType: 1),
          entertainmentId);
    });

    test('类型过滤：支出线索不得命中收入分类规则', () async {
      // 「工资」为收入规则，支出记录不得命中
      final hit = await engine.classify(['某月工资条相关文本'], expectedType: 1);
      expect(hit, isNull);
    });
  });

  group('任务 3.2：学习表与引擎联动（指认后自动命中）', () {
    test('指认回写后相同线索自动命中，且优先于内置规则', () async {
      // 内置规则本会把「瑞幸咖啡」判为餐饮，用户指认改判为娱乐
      await rules.assign(matchText: '瑞幸咖啡', categoryId: entertainmentId, source: 0);

      final hit = await engine.classify(['瑞幸咖啡'], expectedType: 1);
      expect(hit, entertainmentId, reason: '学习表命中优先于内置规则');

      final entry = await rules.findByMatchText('瑞幸咖啡');
      expect(entry!.hitCount, 1, reason: '命中计数 +1');
    });

    test('学习条目类型不匹配时回退内置规则', () async {
      // 用户曾把某商户指认为收入分类，支出记录回退内置规则判定
      await rules.assign(matchText: '瑞幸咖啡', categoryId: salaryId, source: 0);

      final hit = await engine.classify(['瑞幸咖啡'], expectedType: 1);
      expect(hit, diningId, reason: '收入指认不干扰支出判定');
    });

    test('指认到已删除分类的条目不再命中', () async {
      // 指认到一个自定义分类，然后软删该分类
      final custom = await categories.insert(CategoriesCompanion.insert(
        name: '自定义甲',
        icon: 'category',
        type: 1,
      ));
      await rules.assign(matchText: '陌生商户', categoryId: custom.id, source: 0);
      await categories.softDelete(custom.id);

      final hit = await engine.classify(['陌生商户'], expectedType: 1);
      expect(hit, isNull, reason: '分类墓碑后学习条目失效');
    });
  });

  group('内置规则库 asset 完整性', () {
    test('随版本发布的 JSON 可解析且全部分类可解析、引擎可构造', () async {
      final json = File('assets/category_rules.json').readAsStringSync();
      final parsed = CategoryKeywordRule.parseList(json);
      expect(parsed, isNotEmpty);

      // 构造期即校验所有规则分类可解析，坏数据直接抛错
      final assetEngine = CategoryEngine(rules, categories, parsed);
      expect(assetEngine, isNotNull);
    });
  });
}
