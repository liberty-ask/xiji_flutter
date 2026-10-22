import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:xiji_flutter/parser/bill_csv_parser.dart';

void main() {
  final parser = BillCsvParser();

  /// 支付宝账单 fixture：GBK 编码，第 4 行首格含「支付宝账户」（服务端 canParse 口径）
  Uint8List alipayCsv() {
    const content = '''
支付宝交易（2026-09-01 00:00:00 至 2026-09-30 00:00:00）[全部]
支付宝账号:[test@example.com]
起始日期:2026-09-01 00:00:00    终止日期:2026-09-30 00:00:00
支付宝账户:[test@example.com]
-----------------------------交易记录明细列表------------------------------
交易订单号,商家订单号,交易时间,付款时间,最近修改时间,交易来源地,类型,交易对方,商品说明,收/付款方式,金额,收/支,交易状态,交易分类,备注
2026090122001234567890,ORD001,2026-09-01 10:00:00,2026-09-01 10:00:00,2026-09-01 10:00:00,手机,即时到账,瑞幸咖啡,拿铁咖啡,余额宝,25.00,支出,交易成功,餐饮,/
2026090222001234567891,ORD002,2026-09-02 12:30:00,2026-09-02 12:30:00,2026-09-02 12:30:00,手机,即时到账,某某公司,9月工资,银行卡,8000.00,收入,交易成功,工资,/
2026090322001234567892,ORD003,2026-09-03 08:00:00,2026-09-03 08:00:00,2026-09-03 08:00:00,手机,担保交易,某平台,余额宝-自动转入,余额宝,500.00,不计收支,交易成功,转账,/
2026090422001234567893,ORD004,2026-09-04 09:00:00,2026-09-04 09:00:00,2026-09-04 09:00:00,手机,即时到账,万达影院,"电影票,两张",余额宝,60.00,支出,交易成功,娱乐,/
2026090522001234567894,,2026-09-05 09:00:00,,,手机,即时到账,某商户,异常行缺金额,余额宝,,支出,交易成功,餐饮,/
2026090622001234567895,ORD006,2026-09-06 09:00:00,2026-09-06 09:00:00,2026-09-06 09:00:00,手机,即时到账,其他类型商户,未知收支类型行,余额宝,12.00,其他,交易成功,餐饮,/
''';
    return Uint8List.fromList(gbk.encode(content));
  }

  group('任务 3.3：账单 CSV 本地解析器（支付宝字段映射）', () {
    test('支付宝：GBK 编码识别 + 平台来源字段 + 正常行字段映射', () {
      final result = parser.parse(alipayCsv());

      expect(result, isNotNull);
      expect(result!.platform, '支付宝');
      expect(result.platformCode, 'alipay');
      expect(result.rows, hasLength(5), reason: '金额缺失行为异常行');
      expect(result.errors, hasLength(1));
      expect(result.errors.first.row, 11, reason: '异常行行号对应文件实际行');
      expect(result.errors.first.reason, '数据不完整');

      final first = result.rows.first;
      expect(first.platformCode, 'alipay');
      expect(first.tradeNo, '2026090122001234567890');
      expect(first.merchantOrderNo, 'ORD001');
      expect(first.date, DateTime(2026, 9, 1, 10, 0, 0));
      expect(first.amount, 25.00);
      expect(first.type, 1);
      expect(first.counterparty, '瑞幸咖啡');
      expect(first.description, '拿铁咖啡');
      expect(first.payMethod, '余额宝');
      expect(first.status, '交易成功');
    });

    test('支付宝：收入/不计收支/未知收支/引号内逗号', () {
      final result = parser.parse(alipayCsv())!;

      expect(result.rows[1].type, 0, reason: '收入 → 0');
      expect(result.rows[2].type, 2, reason: '不计收支 → 2');
      expect(result.rows[3].description, '电影票,两张',
          reason: '引号内的逗号不切分单元格');
      expect(result.rows[3].type, 1);
      expect(result.rows[4].type, 1,
          reason: '收/支未标识且金额为正 → 默认支出（对齐服务端）');

      // 元数据合计：不计收支不计入收支合计
      expect(result.totalIncome, 8000.0);
      expect(result.totalExpense, 97.0);
      expect(result.startDate, DateTime(2026, 9, 1, 10, 0, 0));
      expect(result.endDate, DateTime(2026, 9, 6, 9, 0, 0));
    });

    test('不支持的平台/非账单文件返回 null', () {
      final junk = Uint8List.fromList(utf8.encode('随便什么,内容\n1,2'));
      expect(parser.parse(junk), isNull);
    });

    test('空文件返回 null', () {
      expect(parser.parse(Uint8List(0)), isNull);
    });
  });

  /// 京东账单 fixture：GBK 编码，表头在第 22 行（前 21 行为账户信息），
  /// 第 2 行首格含「京东账号」（服务端 canParse 口径）
  Uint8List jdCsv() {
    final preamble = List.generate(
        21, (i) => i == 1 ? '京东账号:[test@example.com]' : '账户信息行 $i');
    const header =
        '交易时间,商户名称,交易说明,金额,收/付款方式,交易状态,收/支,交易分类,交易订单号,商家订单号,备注';
    const dataRows = '''
2026-09-01 10:00:00,瑞幸咖啡,拿铁咖啡,25.00,京东支付,交易成功,支出,餐饮,JD123456,M001,/
2026-09-02 09:00:00,某某公司,9月工资,8000.00,银行卡,交易成功,收入,工资,JD123457,M002,/
2026-09-03 08:00:00,京东平台,小金库自动转入,500.00,小金库,交易成功,不计收支,转账,JD123458,M003,/
2026-09-04 12:00:00,某商户,订单已全额退款,19.88(已全额退款),白条,退款成功,不计收支,餐饮,JD123459,M004,/
2026-09-05 13:00:00,某超市,,,,京东支付,交易成功,支出,日用品,JD123460,M005,/
2026-09-06 14:00:00,某商户,,30.00,京东支付,交易成功,支出,其他,JD123461,M006,备注当描述
''';
    final content = [...preamble, header, ...dataRows.split('\n')].join('\n');
    return Uint8List.fromList(gbk.encode(content));
  }

  group('任务 3.3 补：京东账单解析（对齐服务端 JdBillParser）', () {
    test('京东：GBK 编码识别 + 第 22 行表头探测 + 平台来源字段 + 正常行字段映射', () {
      final result = parser.parse(jdCsv());

      expect(result, isNotNull);
      expect(result!.platform, '京东');
      expect(result.platformCode, 'jd');
      expect(result.rows, hasLength(5), reason: '金额缺失行为异常行');
      expect(result.errors, hasLength(1));
      expect(result.errors.first.row, 27, reason: '异常行行号对应文件实际行');
      expect(result.errors.first.reason, '数据不完整');

      final first = result.rows.first;
      expect(first.platformCode, 'jd');
      expect(first.tradeNo, 'JD123456');
      expect(first.merchantOrderNo, 'M001');
      expect(first.date, DateTime(2026, 9, 1, 10, 0, 0));
      expect(first.amount, 25.00);
      expect(first.type, 1);
      expect(first.counterparty, '瑞幸咖啡');
      expect(first.description, '拿铁咖啡');
      expect(first.payMethod, '京东支付');
      expect(first.status, '交易成功');
    });

    test('京东：收入/不计收支/已全额退款转支出/金额括号清理/备注回退描述', () {
      final result = parser.parse(jdCsv())!;

      expect(result.rows[1].type, 0, reason: '收入 → 0');
      expect(result.rows[2].type, 2, reason: '不计收支 → 2');
      expect(result.rows[3].type, 1, reason: '不计收支且金额含「已全额退款」→ 1');
      expect(result.rows[3].amount, 19.88, reason: '金额括号内退款标记被清理');
      expect(result.rows[4].description, '备注当描述',
          reason: '交易说明为空回退备注列');

      expect(result.totalIncome, 8000.0);
      expect(result.totalExpense, 74.88);
    });
  });
}
