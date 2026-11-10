import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiji_flutter/data/local/app_database.dart';
import 'package:xiji_flutter/data/local/bill_import_service.dart';
import 'package:xiji_flutter/data/local/builtin_categories.dart';
import 'package:xiji_flutter/data/local/category_engine.dart';
import 'package:xiji_flutter/data/local/category_repository.dart';
import 'package:xiji_flutter/data/local/category_rule_repository.dart';
import 'package:xiji_flutter/data/local/transaction_repository.dart';
import 'package:xiji_flutter/models/category_keyword_rule.dart';
import 'package:xiji_flutter/parser/bill_csv_parser.dart';

/// 统一四层链路：学习表 → 平台分类 → 关键词 → 未分类，对所有平台一视同仁。
/// 使用随版本发布的真实规则库（assets/category_rules.json），覆盖顺序与降级口径。
void main() {
  late AppDatabase db;
  late CategoryRuleRepository rules;
  late BillImportService service;

  final assetRules = CategoryKeywordRule.parseList(
    File('assets/category_rules.json').readAsStringSync(),
  );

  String id(String name) => BuiltinCategories.byName(name)!.id;
  final uncategorizedId = BuiltinCategories.uncategorizedId;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    final transactions = TransactionRepository(db);
    final categories = CategoryRepository(db);
    rules = CategoryRuleRepository(db);
    service = BillImportService.withRepos(
      transactions,
      rules,
      CategoryEngine(rules, categories, assetRules),
    );
  });

  tearDown(() async {
    await db.close();
  });

  ParsedBillRow row({
    required String platformCode,
    String? platformCategory,
    String? transactionType,
    String? counterparty,
    String? description,
    int? type = 1,
    String? tradeNo,
  }) {
    return ParsedBillRow(
      platformCode: platformCode,
      tradeNo: tradeNo,
      date: DateTime(2026, 11, 1, 12),
      amount: 30,
      type: type,
      counterparty: counterparty,
      description: description,
      platformCategory: platformCategory,
      transactionType: transactionType,
    );
  }

  Future<String?> prefill(ParsedBillRow r) async {
    final items = await service.prepare([r]);
    return items.single.categoryId;
  }

  test('学习表命中覆盖平台分类（支付宝）', () async {
    await rules.assign(
        matchText: '某商户', categoryId: id('娱乐'), source: 0);

    final category = await prefill(row(
      platformCode: 'alipay',
      platformCategory: '交通出行',
      counterparty: '某商户',
      description: '打车',
    ));
    expect(category, id('娱乐'), reason: '学习表是第一层，压过明确平台类目');
  });

  test('微信走学习表', () async {
    await rules.assign(
        matchText: '某商户', categoryId: id('娱乐'), source: 0);

    final category = await prefill(row(
      platformCode: 'wechat',
      transactionType: '商户消费',
      counterparty: '某商户',
      description: '消费',
    ));
    expect(category, id('娱乐'), reason: '微信不再被门控排除在学习表之外');
  });

  test('微信走关键词层', () async {
    final category = await prefill(row(
      platformCode: 'wechat',
      transactionType: '商户消费',
      counterparty: '瑞幸咖啡',
      description: '拿铁',
    ));
    expect(category, id('餐饮'));
  });

  test('收钱码行不再落餐饮：平台类目降级后交关键词层', () async {
    final unknown = await prefill(row(
      platformCode: 'alipay',
      platformCategory: '餐饮美食',
      counterparty: '张阿姨',
      description: '收钱码收款',
    ));
    expect(unknown, uncategorizedId, reason: '收单 MCC 不可信且关键词无命中');

    final grocery = await prefill(row(
      platformCode: 'alipay',
      platformCategory: '餐饮美食',
      counterparty: '张阿姨',
      description: '收钱码收款 蔬菜',
    ));
    expect(grocery, id('日用'), reason: '商品名含蔬菜应归日用，而不是餐饮');
  });

  test('京东空格分隔多标签按第一段命中网购', () async {
    final category = await prefill(row(
      platformCode: 'jd',
      platformCategory: '其他网购 食品酒饮',
      counterparty: '某某商家',
      description: '订单',
    ));
    expect(category, id('网购'));
  });

  test('关键词分层不互抢：日用规则排在餐饮之前', () async {
    // 「叮咚买菜」命中日用，「咖啡」命中餐饮；规则顺序决定先到先得
    final category = await prefill(row(
      platformCode: 'alipay',
      platformCategory: '餐饮美食',
      counterparty: '叮咚买菜',
      description: '顺带买了一杯咖啡',
    ));
    expect(category, id('日用'));
  });

  test('type=2 不计收支的行不参与任何分类推断', () async {
    final category = await prefill(row(
      platformCode: 'alipay',
      platformCategory: '交通出行',
      counterparty: '某商户',
      description: '退款',
      type: 2,
    ));
    expect(category, uncategorizedId);
  });

  test('清空学习表后同一商户回到平台/关键词层', () async {
    await rules.assign(
        matchText: '某商户', categoryId: id('娱乐'), source: 0);
    expect(
      await prefill(row(
        platformCode: 'alipay',
        platformCategory: '交通出行',
        counterparty: '某商户',
      )),
      id('娱乐'),
    );

    expect(await service.clearLearningTable(), 1);
    expect(
      await prefill(row(
        platformCode: 'alipay',
        platformCategory: '交通出行',
        counterparty: '某商户',
      )),
      id('交通'),
      reason: '清空后回落到平台分类层',
    );
  });

  group('扩词：每个新增关键词都有用例（合成商户名）', () {
    test('餐饮：现制现售与小吃的每个新词', () async {
      const words = [
        '餐饮', '面食', '火烧', '炉包', '锅盔', '包子',
        '煎饼', '凉皮', '馄饨', '熟食', '豆糕', '仙豆糕',
      ];
      for (final word in words) {
        expect(
          await prefill(row(
            platformCode: 'alipay',
            counterparty: '合成$word商户',
            description: '消费',
          )),
          id('餐饮'),
          reason: '新增词「$word」应归餐饮',
        );
      }
    });

    test('日用：生鲜果蔬与米面粮油的每个新词', () async {
      const words = [
        '果品', '果铺', '果业', '果蔬', '粮油', '水产', '海鲜', '鲜果', '肉食',
      ];
      for (final word in words) {
        expect(
          await prefill(row(
            platformCode: 'alipay',
            counterparty: '合成$word商户',
            description: '收钱码收款',
          )),
          id('日用'),
          reason: '新增词「$word」属生鲜/食材，应归日用',
        );
      }
    });

    test('交通：琴岛通', () async {
      expect(
        await prefill(row(
          platformCode: 'wechat',
          transactionType: '商户消费',
          counterparty: '合成科技有限公司',
          description: '琴岛通 充值',
        )),
        id('交通'),
      );
    });

    test('水电燃气：天然气；燃气灶不误命中', () async {
      expect(
        await prefill(row(
          platformCode: 'wechat',
          transactionType: '商户消费',
          counterparty: '合成天然气',
          description: '自助生活缴费',
        )),
        id('水电燃气'),
      );
      expect(
        await prefill(row(
          platformCode: 'wechat',
          transactionType: '商户消费',
          counterparty: '合成电器',
          description: '卡萨帝燃气灶天然气灶',
        )),
        uncategorizedId,
        reason: '家电（燃气灶/天然气灶）不是燃气缴费',
      );
    });

    test('医疗：附院', () async {
      expect(
        await prefill(row(
          platformCode: 'wechat',
          transactionType: '商户消费',
          counterparty: '合成附院',
          description: '挂号费',
        )),
        id('医疗'),
      );
    });

    test('豆糕不把包装糕点当现制餐饮', () async {
      expect(
        await prefill(row(
          platformCode: 'wechat',
          transactionType: '商户消费',
          counterparty: '合成生活',
          description: '有机绿豆糕原材料',
        )),
        uncategorizedId,
        reason: '绿豆糕是包装食品，不应命中现制餐饮规则',
      );
      expect(
        await prefill(row(
          platformCode: 'alipay',
          counterparty: '合成餐饮具商户',
          description: '餐具',
        )),
        uncategorizedId,
        reason: '「餐饮具」被排除词压掉，不能因「餐饮」落餐饮',
      );
    });
  });

  group('误命中修正：便利店与金融产品', () {
    test('便利店名含医院不判医疗', () async {
      for (final name in [
        '7-ELEVEn(合成医院店)',
        '7ELEVEn(合成妇幼医院店)',
        '合成便利店(中心医院店)',
        '合成罗森(医院店)',
        '合成便利蜂(医院店)',
      ]) {
        final category = await prefill(row(
          platformCode: 'alipay',
          platformCategory: '餐饮美食',
          counterparty: name,
          description: '收钱码收款',
        ));
        expect(category, id('日用'), reason: '$name 是便利店，不是医疗机构');
      }
      expect(
        await prefill(row(
          platformCode: 'alipay',
          platformCategory: '医疗健康',
          counterparty: '合成市立医院',
          description: '挂号费',
        )),
        id('医疗'),
        reason: '正常医院仍应判医疗',
      );
    });

    test('金融产品不被平台名规则抓成网购', () async {
      final cases = <String, ParsedBillRow>{
        '京东小金库收益': row(
          platformCode: 'jd',
          platformCategory: '小金库',
          counterparty: '京东小金库',
          description: '京东小金库收益',
          type: 0,
        ),
        '京东金融': row(
          platformCode: 'jd',
          platformCategory: '其他',
          counterparty: '京东金融',
          description: '价保退款',
          type: 0,
        ),
        '京东白条': row(
          platformCode: 'jd',
          platformCategory: '白条',
          counterparty: '京东白条',
          description: '白条自动还款',
          type: 0,
        ),
        '余额宝': row(
          platformCode: 'alipay',
          platformCategory: '投资理财',
          counterparty: '余额宝',
          description: '余额宝-自动转入',
        ),
        '花呗信用购': row(
          platformCode: 'alipay',
          platformCategory: '信用借还',
          counterparty: '花呗|信用购',
          description: '自动还款',
          type: 2,
        ),
      };
      for (final entry in cases.entries) {
        expect(await prefill(entry.value), uncategorizedId,
            reason: '${entry.key} 属金融产品，保持未分类');
      }

      expect(
        await prefill(row(
          platformCode: 'jd',
          platformCategory: '其他网购',
          counterparty: '京东平台商户',
          description: '订单',
        )),
        id('网购'),
        reason: '正常京东购物仍判网购',
      );
    });
  });

  test('生鲜不落餐饮、餐饮不落日用', () async {
    expect(
      await prefill(row(
        platformCode: 'alipay',
        counterparty: '合成生鲜超市',
        description: '收钱码收款',
      )),
      id('日用'),
    );
    expect(
      await prefill(row(
        platformCode: 'alipay',
        counterparty: '合成果蔬店',
        description: '收钱码收款',
      )),
      id('日用'),
    );
    expect(
      await prefill(row(
        platformCode: 'alipay',
        counterparty: '合成饭店',
        description: '消费',
      )),
      id('餐饮'),
    );
    expect(
      await prefill(row(
        platformCode: 'alipay',
        counterparty: '合成小吃店',
        description: '消费',
      )),
      id('餐饮'),
    );
  });
}
