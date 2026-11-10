import 'package:flutter_test/flutter_test.dart';
import 'package:xiji_flutter/data/local/bill_category_mapper.dart';
import 'package:xiji_flutter/data/local/builtin_categories.dart';
import 'package:xiji_flutter/parser/bill_csv_parser.dart';

/// 平台分类层可信度分级：明确类目直接采用，含糊类目降级交给关键词层。
void main() {
  String id(String name) => BuiltinCategories.byName(name)!.id;

  ParsedBillRow row({
    required String platformCode,
    String? platformCategory,
    String? transactionType,
    String? counterparty = '某商户',
    String? description = '商品',
    int? type = 1,
  }) {
    return ParsedBillRow(
      platformCode: platformCode,
      date: DateTime(2026, 11, 1),
      amount: 20,
      type: type,
      counterparty: counterparty,
      description: description,
      platformCategory: platformCategory,
      transactionType: transactionType,
    );
  }

  group('支付宝：明确类目直接采用', () {
    test('交通出行 / 医疗健康 / 酒店旅游 / 教育培训', () {
      expect(
        BillCategoryMapper.mapRow(row(
            platformCode: 'alipay', platformCategory: '交通出行', type: 1)),
        id('交通'),
      );
      expect(
        BillCategoryMapper.mapRow(row(
            platformCode: 'alipay', platformCategory: '医疗健康', type: 1)),
        id('医疗'),
      );
      expect(
        BillCategoryMapper.mapRow(row(
            platformCode: 'alipay', platformCategory: '酒店旅游', type: 1)),
        id('旅行'),
      );
      expect(
        BillCategoryMapper.mapRow(row(
            platformCode: 'alipay', platformCategory: '教育培训', type: 1)),
        id('教育'),
      );
    });
  });

  group('支付宝：含糊类目降级返回 null（交给关键词层）', () {
    test('餐饮美食 / 日用百货 / 生活服务 / 其他', () {
      for (final category in ['餐饮美食', '日用百货', '生活服务', '其他']) {
        expect(
          BillCategoryMapper.mapRow(
              row(platformCode: 'alipay', platformCategory: category, type: 1)),
          isNull,
          reason: '$category 属含糊类目，不应直接锁死',
        );
      }
    });
  });

  group('支付宝：收单 MCC 噪声降级', () {
    test('收钱码收款即使标餐饮美食也不采用', () {
      expect(
        BillCategoryMapper.mapRow(row(
          platformCode: 'alipay',
          platformCategory: '餐饮美食',
          description: '收钱码收款',
          counterparty: '菜市场张阿姨',
          type: 1,
        )),
        isNull,
        reason: '收单 MCC 与真实消费性质无关',
      );
    });

    test('经营码交易即使标日用百货也不采用', () {
      expect(
        BillCategoryMapper.mapRow(row(
          platformCode: 'alipay',
          platformCategory: '日用百货',
          description: '经营码交易',
          type: 1,
        )),
        isNull,
      );
    });
  });

  group('京东：交易分类多标签拆分', () {
    test('空格分隔的「其他网购 食品酒饮」拆开后命中网购', () {
      expect(
        BillCategoryMapper.mapRow(row(
          platformCode: 'jd',
          platformCategory: '其他网购 食品酒饮',
          counterparty: '某某商家',
          description: '订单',
          type: 1,
        )),
        id('网购'),
        reason: '空格也是分隔符，不能整串匹配失败后掉到关键词层',
      );
    });

    test('食品酒饮 + 即食描述判餐饮', () {
      expect(
        BillCategoryMapper.mapRow(row(
          platformCode: 'jd',
          platformCategory: '食品酒饮',
          description: '外卖订单',
          type: 1,
        )),
        id('餐饮'),
      );
    });

    test('食品酒饮 + 餐饮具判日用（排除词生效）', () {
      expect(
        BillCategoryMapper.mapRow(row(
          platformCode: 'jd',
          platformCategory: '食品酒饮',
          description: '餐饮具一套',
          type: 1,
        )),
        id('日用'),
        reason: '「餐饮具」不是即食，不应命中餐饮',
      );
    });

    test('咖啡豆 / 即食燕麦不判即食', () {
      expect(
        BillCategoryMapper.mapRow(row(
          platformCode: 'jd',
          platformCategory: '食品酒饮',
          counterparty: '某咖啡旗舰店',
          description: '咖啡豆 500g',
          type: 1,
        )),
        id('日用'),
        reason: '咖啡豆是食材，不是现场消费',
      );
      expect(
        BillCategoryMapper.mapRow(row(
          platformCode: 'jd',
          platformCategory: '食品酒饮',
          description: '即食燕麦片',
          type: 1,
        )),
        id('日用'),
      );
    });

    test('「其他」标签降级交给关键词层', () {
      expect(
        BillCategoryMapper.mapRow(row(
            platformCode: 'jd', platformCategory: '其他', type: 1)),
        isNull,
      );
    });
  });

  group('微信：交易类型映射，商户消费交给后续层', () {
    test('转账 → 人情往来；微信红包按方向', () {
      expect(
        BillCategoryMapper.mapRow(row(
            platformCode: 'wechat', transactionType: '转账', type: 1)),
        id('人情往来'),
      );
      expect(
        BillCategoryMapper.mapRow(row(
            platformCode: 'wechat', transactionType: '微信红包', type: 0)),
        id('红包'),
      );
    });

    test('商户消费不映射（交学习表 / 关键词层）', () {
      expect(
        BillCategoryMapper.mapRow(row(
            platformCode: 'wechat', transactionType: '商户消费', type: 1)),
        isNull,
      );
    });
  });

  test('type=2 不计收支的行一律不映射', () {
    expect(
      BillCategoryMapper.mapRow(row(
          platformCode: 'alipay', platformCategory: '交通出行', type: 2)),
      isNull,
    );
    expect(
      BillCategoryMapper.mapRow(row(
          platformCode: 'jd', platformCategory: '其他网购', type: 2)),
      isNull,
    );
    expect(
      BillCategoryMapper.mapRow(row(
          platformCode: 'wechat', transactionType: '转账', type: 2)),
      isNull,
    );
  });
}
