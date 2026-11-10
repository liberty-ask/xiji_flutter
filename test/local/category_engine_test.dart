import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  // 内置规则（测试内固定样例，与 asset 结构一致；中性分类后不含 type）
  final testRules = CategoryKeywordRule.parseList('''
  {
    "rules": [
      { "keywords": ["瑞幸", "星巴克"], "category": "餐饮" },
      { "keywords": ["Steam"], "category": "娱乐" },
      { "keywords": ["工资"], "category": "工资" }
    ]
  }
  ''');

  setUp(() {
    // 引擎可用分类集合经 CurrentFamilyStore 解析当前家庭（mock prefs 下为 ''）
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    categories = CategoryRepository(db);
    rules = CategoryRuleRepository(db);
    engine = CategoryEngine(rules, categories, testRules);
  });

  tearDown(() async {
    await db.close();
  });

  // 常量引用：内置分类固定 ID
  final diningId = BuiltinCategories.byName('餐饮')!.id;
  final entertainmentId = BuiltinCategories.byName('娱乐')!.id;
  final salaryId = BuiltinCategories.byName('工资')!.id;

  group('任务 3.1：内置关键词规则库匹配逻辑', () {
    test('命中：交易对方包含关键词 → 对应内置分类 ID', () async {
      final hit = await engine.classify(['瑞幸咖啡（杭州）有限公司']);
      expect(hit, diningId);
    });

    test('未命中：无线索文本返回 null（不猜测填充）', () async {
      final hit = await engine.classify(['完全陌生的商户']);
      expect(hit, isNull);
    });

    test('多线索顺序：交易对方未命中时回退商品名线索', () async {
      final hit = await engine.classify(['陌生商户', '买了一杯星巴克拿铁']);
      expect(hit, diningId);
    });

    test('不区分大小写：Steam/stEAm 均命中娱乐', () async {
      expect(await engine.classify(['Steam 平台充值']), entertainmentId);
      expect(await engine.classify(['stEAm 平台充值']), entertainmentId);
    });

    test('不按收支过滤：收入向关键词同样命中，方向由交易自身决定', () async {
      // 分类中性化：规则只认线索文本，收支方向不参与判定
      expect(await engine.classify(['某月工资条相关文本']), salaryId);
    });

    test('坏规则 fail fast：分类名不是内置分类时构造即抛错', () {
      final badRules = CategoryKeywordRule.parseList('''
      { "rules": [ { "keywords": ["x"], "category": "不存在的分类" } ] }
      ''');
      expect(
        () => CategoryEngine(rules, categories, badRules),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('任务 3.2：学习表与引擎联动（指认后自动命中）', () {
    test('指认回写后相同线索自动命中，且优先于内置规则', () async {
      // 内置规则本会把「瑞幸咖啡」判为餐饮，用户指认改判为娱乐
      await rules.assign(
          matchText: '瑞幸咖啡', categoryId: entertainmentId, source: 0);

      final hit = await engine.classify(['瑞幸咖啡']);
      expect(hit, entertainmentId, reason: '学习表命中优先于内置规则');

      final entry = await rules.findByMatchText('瑞幸咖啡');
      expect(entry!.hitCount, 1, reason: '命中计数 +1');
    });

    test('学习表命中不区分方向：同一指认同时服务收入与支出线索', () async {
      // 指认一个中性分类，收支两侧都应命中同一条学习记录
      await rules.assign(
          matchText: '某商户', categoryId: entertainmentId, source: 0);

      expect(await engine.classify(['某商户']), entertainmentId);
      expect(await engine.classify(['某商户']), entertainmentId,
          reason: '再次判定仍命中同一分类（方向不参与）');

      final entry = await rules.findByMatchText('某商户');
      expect(entry!.hitCount, 2);
    });

    test('指认到已删除分类的条目不再命中', () async {
      // 指认到一个自定义分类，然后软删该分类
      final custom = await categories.insert(
        '',
        CategoriesCompanion.insert(
          name: '自定义甲',
          icon: 'category',
        ),
      );
      await rules.assign(matchText: '陌生商户', categoryId: custom.id, source: 0);
      await categories.softDelete(custom.id);

      final hit = await engine.classify(['陌生商户']);
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
