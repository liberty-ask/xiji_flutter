import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'bill_csv_parser.dart';

/// 账单 XLSX 本地解析器：微信支付账单（官方邮箱导出仅 XLSX 格式，不产 CSV）。
///
/// xlsx 首部为「微信支付账单明细」等说明文字行，表头行需扫描定位：
/// 首 30 行内单元格精确命中微信关键字段 ≥5 个即认定（对齐服务端 HeaderDetector）。
/// 字段映射与收/支语义逐条对齐服务端 WechatBillParser：
/// - 收/支：收入/收款/转入→0，支出/付款/转出→1，「/」（不计收支）等其余值默认支出
/// - 商品列为空或「/」时回退「交易类型/交易对方」
/// - 交易单号缺失时以「时间_金额_对方」生成兜底单号
/// 去重（tradeNo 单键）与退款修正（仅收/支未标注行凭「退款」佐证转收入）由导入服务统一处理。
class BillXlsxParser {
  /// 微信表头关键字段（对齐服务端 HeaderDetector.PLATFORM_KEYWORDS）
  static const _wechatKeywords = {
    '交易单号', '交易时间', '金额(元)', '收/支', '交易类型',
    '交易对方', '商品', '支付方式', '当前状态', '商户单号',
  };

  /// 解析微信账单 xlsx 字节：非微信格式或文件损坏返回 null
  BillParseResult? parse(Uint8List bytes) {
    // 1. 解码工作簿（xlsx 为 zip 容器，非 xlsx 或损坏文件解码抛异常）
    Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } catch (_) {
      return null;
    }
    if (excel.tables.isEmpty) return null;
    final rows = excel.tables.values.first.rows;

    // 2. 平台识别：首行首格含「微信支付账单」（对齐服务端 canParse）
    if (rows.isEmpty || rows.first.isEmpty) return null;
    final firstCell = _cellText(rows.first.first);
    if (firstCell == null || !firstCell.contains('微信支付账单')) return null;

    // 3. 表头探测：说明行之后扫描定位表头行
    final headerIndex = _detectHeaderRow(rows);
    if (headerIndex == -1) {
      return const BillParseResult(
        platform: '微信',
        platformCode: 'wechat',
        rows: [],
        errors: [BillParseError(0, '无法识别微信账单表头')],
      );
    }
    final headers =
        rows[headerIndex].map((c) => _cellText(c)?.trim() ?? '').toList();

    // 4. 逐行解析（表头行之后；整行空白跳过，行号对应表格实际行）
    final parsedRows = <ParsedBillRow>[];
    final errors = <BillParseError>[];
    for (var i = headerIndex + 1; i < rows.length; i++) {
      final cells = rows[i];
      if (cells.every((c) => (_cellText(c) ?? '').trim().isEmpty)) continue;
      try {
        final row = _mapRow(headers, cells);
        if (row != null) {
          parsedRows.add(row);
        } else {
          errors.add(BillParseError(i + 1, '数据不完整'));
        }
      } catch (e) {
        errors.add(BillParseError(i + 1, '解析失败：$e'));
      }
    }

    return BillCsvParser.buildResult('wechat', parsedRows, errors);
  }

  /// 表头探测：单元格精确命中微信关键字段 ≥5 个即认定（对齐服务端阈值）
  int _detectHeaderRow(List<List<Data?>> rows) {
    final maxSearch = rows.length < 30 ? rows.length : 30;
    for (var i = 0; i < maxSearch; i++) {
      var matched = 0;
      for (final cell in rows[i]) {
        final value = _cellText(cell)?.trim() ?? '';
        if (value.isNotEmpty && _wechatKeywords.contains(value)) matched++;
      }
      if (matched >= 5) return i;
    }
    return -1;
  }

  /// 单行字段映射：日期与金额均不可缺，否则视为异常行返回 null
  ParsedBillRow? _mapRow(List<String> headers, List<Data?> cells) {
    String? cell(List<String> names) {
      for (final name in names) {
        final index = headers.indexOf(name);
        if (index < 0 || index >= cells.length) continue;
        final value = _cellText(cells[index])?.trim();
        if (value != null && value.isNotEmpty) return value;
      }
      return null;
    }

    final time = cell(['交易时间', '支付时间']);
    final amountRaw = cell(['金额(元)', '金额']);
    final date = BillCsvParser.parseDate(time);
    final amount = BillCsvParser.parseAmount(amountRaw);
    if (date == null || amount == null) return null;

    // 微信：收入/收款/转入→0，支出/付款/转出→1，「/」不计收支默认支出（对齐服务端，
    // 微信不产生 type=2；退款守卫后导入服务不覆盖明确标注的收支类型）
    final incomeExpense = cell(['收/支']);
    int type;
    if (incomeExpense == '收入' ||
        incomeExpense == '收款' ||
        incomeExpense == '转入') {
      type = 0;
    } else if (incomeExpense == '支出' ||
        incomeExpense == '付款' ||
        incomeExpense == '转出') {
      type = 1;
    } else {
      type = 1;
    }

    // 交易单号缺失时以 时间+金额+对方 生成兜底单号（对齐服务端）
    var tradeNo = cell(['交易单号']);
    tradeNo ??=
        'wechat_${time ?? ''}_${amountRaw ?? ''}_${cell(['交易对方']) ?? ''}';

    // 商品列为空或「/」时，回退 交易类型/交易对方（对齐服务端）
    var description = cell(['商品']);
    if (description == null || description == '/') {
      description = '${cell(['交易类型']) ?? ''}/${cell(['交易对方']) ?? ''}';
    }

    return ParsedBillRow(
      platformCode: 'wechat',
      tradeNo: tradeNo,
      merchantOrderNo: cell(['商户单号']),
      date: date,
      amount: amount,
      type: type,
      counterparty: cell(['交易对方']),
      description: description,
      payMethod: cell(['支付方式']),
      status: cell(['当前状态']),
    );
  }

  /// 单元格统一转文本：文本取拼接串；日期/时间类型按账单格式输出，避免时区偏移；
  /// 数值/布尔直接 toString（金额与单号列以文本为主）
  String? _cellText(Data? cell) {
    final value = cell?.value;
    if (value == null) return null;
    String two(int n) => n.toString().padLeft(2, '0');
    return switch (value) {
      TextCellValue(:final value) => value.toString(),
      DateCellValue(:final year, :final month, :final day) =>
        '$year-${two(month)}-${two(day)}',
      TimeCellValue(:final hour, :final minute, :final second) =>
        '${two(hour)}:${two(minute)}:${two(second)}',
      DateTimeCellValue(
        :final year,
        :final month,
        :final day,
        :final hour,
        :final minute,
        :final second,
      ) =>
        '$year-${two(month)}-${two(day)} '
            '${two(hour)}:${two(minute)}:${two(second)}',
      _ => value.toString(),
    };
  }
}
