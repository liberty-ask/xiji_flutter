import 'dart:convert';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';

/// 平台 code -> 展示名（与服务端表 platform 列口径一致，导入与迁移写入）
const kBillPlatformNames = {'alipay': '支付宝', 'wechat': '微信', 'jd': '京东'};

/// 账单单行解析结果（平台中立，字段对齐本地交易表）
class ParsedBillRow {
  final String platformCode; // alipay / wechat / jd（平台来源字段）
  final String? tradeNo; // 平台交易单号，导入去重键
  final String? merchantOrderNo; // 商户单号
  final DateTime date; // 业务日期（含时分秒，列表按此排序）
  final double amount; // 金额（正数）
  final int? type; // 0-收入 1-支出 2-不计收支；null-账单未标识且无法推断
  final String? counterparty; // 交易对方（分类引擎首要线索）
  final String? description; // 商品说明
  final String? payMethod; // 收/付款方式
  final String? status; // 交易状态（退款判定线索）

  const ParsedBillRow({
    required this.platformCode,
    this.tradeNo,
    this.merchantOrderNo,
    required this.date,
    required this.amount,
    this.type,
    this.counterparty,
    this.description,
    this.payMethod,
    this.status,
  });
}

/// 解析失败的行（行号从 1 起，对应 CSV 文件实际行）
class BillParseError {
  final int row;
  final String reason;

  const BillParseError(this.row, this.reason);
}

/// 账单解析结果
class BillParseResult {
  final String platform; // 支付宝 / 微信 / 京东
  final String platformCode; // alipay / wechat / jd
  final List<ParsedBillRow> rows; // 解析成功的行
  final List<BillParseError> errors; // 解析失败的行
  final DateTime? startDate;
  final DateTime? endDate;
  final double totalIncome; // type=0 合计
  final double totalExpense; // type=1 合计

  const BillParseResult({
    required this.platform,
    required this.platformCode,
    required this.rows,
    required this.errors,
    this.startDate,
    this.endDate,
    this.totalIncome = 0,
    this.totalExpense = 0,
  });

  int get totalCount => rows.length + errors.length;
}

/// 账单 CSV 本地解析器：支付宝/京东格式识别与字段映射。
///
/// 编码：支付宝 CSV 为 GBK，京东 CSV 为 GBK 或 UTF-8——
/// 先按严格 UTF-8 解码，失败则回退 GBK（服务端 HeaderDetector 同序尝试，口径一致）。
/// 字段映射与收/支语义逐条对齐服务端 AlipayBillParser / JdBillParser，
/// 平台自身的分类列不参与本地分类（分类列由本地引擎预填，spec 约定）。
/// 微信账单官方仅导出 XLSX（不产 CSV），走 BillXlsxParser 解析。
class BillCsvParser {
  /// 平台识别关键字段（对齐服务端 HeaderDetector.PLATFORM_KEYWORDS）
  static const _alipayKeywords = {
    '交易订单号', '交易时间', '金额', '收/支', '交易对方',
    '商品说明', '收/付款方式', '交易分类', '交易状态', '商家订单号',
  };
  static const _jdKeywords = {
    '交易时间', '商户名称', '交易说明', '金额', '收/付款方式',
    '交易状态', '收/支', '交易分类', '交易订单号', '商家订单号', '备注',
  };

  static const _platformNames = kBillPlatformNames;

  /// 解析账单字节：自动识别平台与编码，无法识别返回 null
  BillParseResult? parse(Uint8List bytes) {
    // 1. 解码：严格 UTF-8 优先，失败回退 GBK
    List<String> lines;
    try {
      var text = utf8.decode(bytes); // 非 malformed 字节直接抛错
      if (text.startsWith('\uFEFF')) text = text.substring(1); // 去 BOM
      lines = text.split(RegExp(r'\r\n|\r|\n'));
    } catch (_) {
      final text = gbk.decode(bytes);
      lines = text.split(RegExp(r'\r\n|\r|\n'));
    }

    // 2. 平台识别（对齐服务端 canParse）
    final platformCode = _detectPlatform(lines);
    if (platformCode == null) return null;

    // 3. 表头探测：前 30 行内命中 ≥5 个关键字段的行
    final headerIndex = _detectHeaderRow(lines, platformCode);
    if (headerIndex == -1) {
      return BillParseResult(
        platform: _platformNames[platformCode]!,
        platformCode: platformCode,
        rows: const [],
        errors: const [BillParseError(0, '无法识别账单表头')],
      );
    }

    final headers = _splitCsvLine(lines[headerIndex]).map((h) => h.trim()).toList();

    // 4. 逐行解析
    final rows = <ParsedBillRow>[];
    final errors = <BillParseError>[];
    for (var i = headerIndex + 1; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) continue;
      try {
        final cells = _splitCsvLine(lines[i]);
        final row = _mapRow(headers, cells, platformCode, lineNo: i + 1);
        if (row != null) {
          rows.add(row);
        } else {
          errors.add(BillParseError(i + 1, '数据不完整'));
        }
      } catch (e) {
        errors.add(BillParseError(i + 1, '解析失败：$e'));
      }
    }

    return buildResult(platformCode, rows, errors);
  }

  /// 平台识别：支付宝第 4 行首格含「支付宝账户」；
  /// 京东第 2 行首格含「京东账号」
  String? _detectPlatform(List<String> lines) {
    String firstCellOf(String line) {
      final cells = _splitCsvLine(line);
      return cells.isEmpty ? '' : cells.first.trim();
    }

    if (lines.length > 3 && firstCellOf(lines[3]).contains('支付宝账户')) {
      return 'alipay';
    }
    if (lines.length > 1 && firstCellOf(lines[1]).contains('京东账号')) {
      return 'jd';
    }
    return null;
  }

  /// 表头探测：单元格精确命中平台关键字段 ≥5 个即认定（对齐服务端阈值）
  int _detectHeaderRow(List<String> lines, String platformCode) {
    final keywords = switch (platformCode) {
      'alipay' => _alipayKeywords,
      _ => _jdKeywords,
    };
    final maxSearch = lines.length < 30 ? lines.length : 30;
    for (var i = 0; i < maxSearch; i++) {
      if (lines[i].trim().isEmpty) continue;
      final cells = _splitCsvLine(lines[i]).map((c) => c.trim());
      final matched = cells.where(keywords.contains).length;
      if (matched >= 5) return i;
    }
    return -1;
  }

  /// 单行字段映射：日期与金额均不可缺，否则视为异常行返回 null。
  /// 返回的 type 可能为 null（收/支未标识且无法推断），由导入阶段判失败
  ParsedBillRow? _mapRow(
    List<String> headers,
    List<String> cells,
    String platformCode, {
    required int lineNo,
  }) {
    String? cell(List<String> names) {
      for (final name in names) {
        final index = headers.indexOf(name);
        if (index < 0 || index >= cells.length) continue;
        final value = cells[index].trim();
        if (value.isNotEmpty) return value;
      }
      return null;
    }

    final date = parseDate(cell(switch (platformCode) {
      'alipay' => ['交易时间', '交易创建时间', '付款时间'],
      _ => ['交易时间'],
    }));
    final amountRaw = cell(switch (platformCode) {
      'alipay' => ['金额', '金额（元）'],
      _ => ['金额'],
    });
    // 京东金额可能带括号退款标记（如 19.88(已退款2)），取括号前数值
    final amount = parseAmount(
        platformCode == 'jd' && amountRaw != null
            ? amountRaw.replaceAll(RegExp(r'\([^)]*\)'), '').trim()
            : amountRaw);
    if (date == null || amount == null) return null;

    final incomeExpense = cell(['收/支']);
    int? type;
    if (platformCode == 'alipay') {
      // 支付宝：收入/收款→0，支出/付款→1，不计收支→2，其余金额为正默认支出
      if (incomeExpense == '收入' || incomeExpense == '收款') {
        type = 0;
      } else if (incomeExpense == '支出' || incomeExpense == '付款') {
        type = 1;
      } else if (incomeExpense == '不计收支') {
        type = 2;
      } else if (amount > 0) {
        type = 1;
      }
    } else if (platformCode == 'jd') {
      // 京东：收入/收款/收→0，支出/付款/支→1；
      // 不计收支→金额含「已全额退款」记支出（原消费退款冲抵），否则 2；
      // 收/支未标识不猜测，由导入阶段判失败
      if (incomeExpense == '收入' ||
          incomeExpense == '收款' ||
          incomeExpense == '收') {
        type = 0;
      } else if (incomeExpense == '支出' ||
          incomeExpense == '付款' ||
          incomeExpense == '支') {
        type = 1;
      } else if (incomeExpense == '不计收支') {
        type = amountRaw != null && amountRaw.contains('已全额退款') ? 1 : 2;
      }
    }

    if (platformCode == 'alipay') {
      return ParsedBillRow(
        platformCode: platformCode,
        tradeNo: cell(['交易订单号', '交易号', '交易单号']),
        merchantOrderNo: cell(['商家订单号']),
        date: date,
        amount: amount,
        type: type,
        counterparty: cell(['交易对方']),
        description: cell(['商品说明', '商品名称', '备注']),
        payMethod: cell(['收/付款方式']),
        status: cell(['交易状态']),
      );
    }

    if (platformCode == 'jd') {
      // 京东：商户名称为交易对方；交易说明为空回退备注
      return ParsedBillRow(
        platformCode: platformCode,
        tradeNo: cell(['交易订单号']),
        merchantOrderNo: cell(['商家订单号']),
        date: date,
        amount: amount,
        type: type,
        counterparty: cell(['商户名称']),
        description: cell(['交易说明', '备注']),
        payMethod: cell(['收/付款方式']),
        status: cell(['交易状态']),
      );
    }

    return null; // 不可达：平台识别仅产出 alipay/jd
  }

  /// 日期解析：yyyy-MM-dd[ HH:mm[:ss]] 及 yyyy/M/d、yyyy年M月d日（CSV/XLSX 共用）
  static DateTime? parseDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    var s = raw.trim();
    s = s.replaceAll('年', '-').replaceAll('月', '-').replaceAll('/', '-');
    // 截掉「日」及其后的日期后缀噪声（如「2024-01-01日」）
    s = s.replaceFirst(RegExp(r'日(\s|$)'), ' ');
    s = s.trim();
    return DateTime.tryParse(s);
  }

  /// 金额解析：去货币符号与千分位后转数值（对齐服务端 ExcelUtil.parseAmount，CSV/XLSX 共用）
  static double? parseAmount(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final cleaned = raw
        .trim()
        .replaceAll(',', '')
        .replaceAll('，', '')
        .replaceAll('￥', '')
        .replaceAll('¥', '')
        .replaceAll('\$', '')
        .trim();
    return double.tryParse(cleaned);
  }

  /// 解析结果汇总：起止日期与收支合计（CSV/XLSX 共用）
  static BillParseResult buildResult(
      String platformCode, List<ParsedBillRow> rows, List<BillParseError> errors) {
    DateTime? start;
    DateTime? end;
    var income = 0.0;
    var expense = 0.0;
    for (final r in rows) {
      if (start == null || r.date.isBefore(start)) start = r.date;
      if (end == null || r.date.isAfter(end)) end = r.date;
      if (r.type == 0) income += r.amount;
      if (r.type == 1) expense += r.amount;
    }
    return BillParseResult(
      platform: _platformNames[platformCode]!,
      platformCode: platformCode,
      rows: rows,
      errors: errors,
      startDate: start,
      endDate: end,
      totalIncome: income,
      totalExpense: expense,
    );
  }

  /// CSV 行切分：标准引号转义（"" → "），引号内逗号不切分
  List<String> _splitCsvLine(String line) {
    final cells = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            buf.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          buf.write(c);
        }
      } else {
        if (c == '"') {
          inQuotes = true;
        } else if (c == ',') {
          cells.add(buf.toString());
          buf.clear();
        } else {
          buf.write(c);
        }
      }
    }
    cells.add(buf.toString());
    return cells;
  }
}
