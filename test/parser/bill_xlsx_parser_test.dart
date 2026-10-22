import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiji_flutter/data/local/app_database.dart';
import 'package:xiji_flutter/data/local/bill_import_service.dart';
import 'package:xiji_flutter/data/local/category_engine.dart';
import 'package:xiji_flutter/data/local/category_repository.dart';
import 'package:xiji_flutter/data/local/category_rule_repository.dart';
import 'package:xiji_flutter/data/local/local_user.dart';
import 'package:xiji_flutter/data/local/transaction_repository.dart';
import 'package:xiji_flutter/models/user.dart';
import 'package:xiji_flutter/parser/bill_xlsx_parser.dart';

void main() {
  final parser = BillXlsxParser();

  /// 微信账单表头（官方邮箱导出列序）
  const header = [
    '交易时间', '交易类型', '交易对方', '商品', '收/支', '金额(元)',
    '支付方式', '当前状态', '交易单号', '商户单号', '备注',
  ];

  /// 默认数据行：正常支出/收入、不计收支「/」、已全额退款、缺单号兜底、异常行
  final defaultRows = [
    ['2026-09-05 08:30:00', '商户消费', '肯德基', '肯德基早餐', '支出', '¥25.50', '零钱', '支付成功', '4200001234', '200001', '/'],
    ['2026-09-06 09:00:00', '转账', '张三', '/', '收入', '¥100.00', '零钱', '已收款', '4200001235', '200002', '/'],
    ['2026-09-07 12:00:00', '零钱通转入', '零钱通', '/', '/', '¥10.00', '零钱', '转账成功', '4200001236', '200003', '/'],
    ['2026-09-08 14:00:00', '商户消费', '星巴克', '拿铁', '/', '¥35.00', '零钱', '已全额退款', '4200001237', '200004', '/'],
    ['2026-09-09 16:00:00', '商户消费', '美团外卖', '/', '支出', '¥1,234.56', '银行卡', '支付成功', '', '200005', '/'],
    ['2026-09-10 10:00:00', '商户消费', '异常行', '缺金额', '支出', '', '零钱', '支付成功', '4200001239', '200006', '/'],
  ];

  /// 生成微信 xlsx fixture：说明文字行 + 表头行 + 数据行（模拟邮箱导出格式）
  Uint8List wechatXlsx({List<List<String>>? dataRows, int preambleLines = 4}) {
    final excel = Excel.createExcel();
    final sheet = excel[excel.tables.keys.first];
    sheet.appendRow([TextCellValue('微信支付账单明细')]);
    for (var i = 1; i < preambleLines; i++) {
      sheet.appendRow([TextCellValue('说明文字行 $i')]);
    }
    sheet.appendRow([for (final h in header) TextCellValue(h)]);
    for (final row in dataRows ?? defaultRows) {
      sheet.appendRow([for (final c in row) TextCellValue(c)]);
    }
    return Uint8List.fromList(excel.encode()!);
  }

  group('微信 XLSX 本地解析（对齐服务端 WechatBillParser）', () {
    test('表头定位（说明行后第 5 行）+ 平台来源字段 + 正常行字段映射', () {
      final result = parser.parse(wechatXlsx());

      expect(result, isNotNull);
      expect(result!.platform, '微信');
      expect(result.platformCode, 'wechat');
      expect(result.rows, hasLength(5));
      expect(result.errors, hasLength(1), reason: '金额缺失行为异常行');
      expect(result.errors.first.row, 11, reason: '异常行行号对应表格实际行');
      expect(result.errors.first.reason, '数据不完整');

      final first = result.rows.first;
      expect(first.platformCode, 'wechat');
      expect(first.tradeNo, '4200001234');
      expect(first.merchantOrderNo, '200001');
      expect(first.date, DateTime(2026, 9, 5, 8, 30, 0));
      expect(first.amount, 25.50, reason: '¥ 货币符号剥离');
      expect(first.type, 1);
      expect(first.counterparty, '肯德基');
      expect(first.description, '肯德基早餐');
      expect(first.payMethod, '零钱');
      expect(first.status, '支付成功');
    });

    test('收入/不计收支「/」默认支出/已全额退款/千分位金额/单号兜底/商品回退', () {
      final result = parser.parse(wechatXlsx())!;

      expect(result.rows[1].type, 0, reason: '收入 → 0');
      expect(result.rows[1].description, '转账/张三',
          reason: '商品「/」回退 交易类型/交易对方（对齐服务端）');
      expect(result.rows[2].type, 1,
          reason: '收/支「/」不计收支 → 默认支出（对齐服务端微信解析口径）');
      expect(result.rows[3].type, 1,
          reason: '已全额退款行解析层按「/」默认支出，导入服务修正为收入');
      expect(result.rows[3].status, '已全额退款');
      expect(result.rows[4].amount, 1234.56, reason: '千分位金额清理');
      expect(result.rows[4].tradeNo,
          'wechat_2026-09-09 16:00:00_¥1,234.56_美团外卖',
          reason: '交易单号缺失时以 时间+金额+对方 生成兜底单号（对齐服务端）');

      expect(result.totalIncome, 100.0);
      expect(result.totalExpense, closeTo(1305.06, 0.01));
    });

    test('说明行数量变化时表头仍可定位（前 30 行扫描）', () {
      final result = parser.parse(wechatXlsx(preambleLines: 10));

      expect(result, isNotNull);
      expect(result!.rows, hasLength(5));
      expect(result.errors.first.row, 17,
          reason: '10 行说明 + 表头在 11 行，异常行为第 6 条数据（第 17 行）');
    });

    test('仅说明行无表头 → 无法识别微信账单表头', () {
      final excel = Excel.createExcel();
      final sheet = excel[excel.tables.keys.first];
      sheet.appendRow([TextCellValue('微信支付账单明细')]);
      sheet.appendRow([TextCellValue('没有表头行')]);
      final result = parser.parse(Uint8List.fromList(excel.encode()!));

      expect(result, isNotNull);
      expect(result!.rows, isEmpty);
      expect(result.errors.single.reason, '无法识别微信账单表头');
    });

    test('非微信 xlsx / 非 zip 字节返回 null', () {
      final excel = Excel.createExcel();
      final sheet = excel[excel.tables.keys.first];
      sheet.appendRow([TextCellValue('随便什么内容')]);
      expect(parser.parse(Uint8List.fromList(excel.encode()!)), isNull,
          reason: '首行首格不含「微信支付账单」');
      expect(parser.parse(Uint8List.fromList([1, 2, 3, 4, 5])), isNull,
          reason: '非 zip 容器解码失败');
    });
  });

  group('微信 XLSX 导入链路（同单号去重与退款修正）', () {
    late AppDatabase db;
    late BillImportService service;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      final rules = CategoryRuleRepository(db);
      final categories = CategoryRepository(db);
      service = BillImportService.withRepos(
        TransactionRepository(db),
        rules,
        CategoryEngine(rules, categories, const []),
      );

      SharedPreferences.setMockInitialValues({});
      await LocalUser.cache(User(
        id: 'user-1',
        nickname: '测试用户',
        phone: '13800000000',
      ));
    });

    tearDown(() async {
      await db.close();
    });

    test('同一批次内相同交易单号只入库一条', () async {
      final parsed = parser.parse(wechatXlsx(dataRows: [
        [...defaultRows[0]],
        [...defaultRows[0]], // 同交易单号重复行
      ]))!;
      expect(parsed.rows, hasLength(2), reason: '解析层不去重，两行均产出');

      final outcome =
          await service.importRows(await service.prepare(parsed.rows));
      expect(outcome.successCount, 1);
      expect(outcome.skipCount, 1);
    });

    test('已全额退款行经导入服务修正为收入', () async {
      final parsed = parser.parse(wechatXlsx())!;
      final preview = await service.prepare(parsed.rows);
      final refund = preview.firstWhere((i) => i.row.status == '已全额退款');
      expect(refund.row.type, 0, reason: '状态含「退款」→ 收入（导入服务修正）');
    });
  });
}
