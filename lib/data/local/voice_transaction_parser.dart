import 'category_engine.dart';
import 'category_repository.dart';

/// 纯文本提取结果（与数据库无关，可独立单测）。
/// [amount] 为文本中首个金额（按出现顺序，值需大于 0）；
/// [amountConflict] 表示文本中出现多个互不相同的金额（口语重复或识别混杂）；
/// [type] 0-收入 1-支出，null=未出现类型词（不猜测，与直接入库的置信度要求挂钩）；
/// [date] 提取到的日期，null=未提及（由调用方默认今天，对齐既有服务端语义）。
class VoiceTextFacts {
  final double? amount;
  final bool amountConflict;
  final int? type;
  final DateTime? date;

  const VoiceTextFacts({
    this.amount,
    this.amountConflict = false,
    this.type,
    this.date,
  });

  /// 从语音识别文本提取金额/类型/日期，全部逻辑离线纯本地
  static VoiceTextFacts parse(String text, {required DateTime now}) {
    final amount = _extractAmount(text);
    return VoiceTextFacts(
      amount: amount?.$1,
      amountConflict: amount?.$2 ?? false,
      type: _extractType(text),
      date: _extractDate(text, now),
    );
  }

  /// 金额提取：只认带货币线索的写法，裸数字（可能是日期/编号）不猜测。
  /// - 阿拉伯数字：30元 / 30.5元 / 30块 / 30块钱 / 30块5(毛) / ¥30
  /// - 中文数字：三十元 / 十五块 / 一百二十块 / 两千五百元 / 十五块五
  /// 返回 (首个金额, 是否存在多个不同金额)
  static (double, bool)? _extractAmount(String text) {
    final found = <(int, double)>[]; // (位置, 金额)

    // 阿拉伯数字 + 货币单位；「30块5」口语补 5 毛
    final arabic = RegExp(
        r'([0-9]+(?:\.[0-9]+)?)(块钱|元|块)([0-9](?:毛|角)?)?');
    for (final m in arabic.allMatches(text)) {
      final v = double.parse(m.group(1)!) +
          (m.group(3) != null ? int.parse(m.group(3)![0]) / 10 : 0);
      found.add((m.start, v));
    }

    // ¥/￥ 前缀符号
    final symbol = RegExp(r'[¥￥]([0-9]+(?:\.[0-9]+)?)');
    for (final m in symbol.allMatches(text)) {
      found.add((m.start, double.parse(m.group(1)!)));
    }

    // 中文数字 + 货币单位；「十五块五」补 5 毛
    final chinese = RegExp(
        r'([零一二两三四五六七八九十百千万]+)(块钱|元|块)([零一二三四五六七八九](?:毛|角)?)?');
    for (final m in chinese.allMatches(text)) {
      final v = _chineseNumeralToValue(m.group(1)!) +
          (m.group(3) != null ? _digitMap[m.group(3)![0]]! / 10 : 0);
      found.add((m.start, v));
    }

    // 无效金额（0 或负数）剔除
    final valid = found.where((f) => f.$2 > 0).toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));
    if (valid.isEmpty) return null;

    final distinct = valid.map((f) => f.$2).toSet();
    return (valid.first.$2, distinct.length > 1);
  }

  /// 中文数字字符 → 数值（indexOf 会被「两」占位导致偏移，必须用显式映射）
  static const _digitMap = {
    '零': 0, '一': 1, '二': 2, '两': 2, '三': 3, '四': 4,
    '五': 5, '六': 6, '七': 7, '八': 8, '九': 9,
  };

  /// 中文数字转数值：支持到千万级。
  /// 标准式：三十=30 十五=15 一百二十=120 两千五百=2500 三百零五=305 一万五千=15000
  /// 口语无单位缩写（一百二/三千五）无货币线索，不作为金额提取（见上）
  static double _chineseNumeralToValue(String s) {
    double section = 0; // 万段内累积
    double digit = 0; // 待乘位的数字（0=未置位）

    for (final ch in s.runes.map(String.fromCharCode)) {
      final d = _digitMap[ch];
      if (d != null) {
        if (ch != '零') digit = d.toDouble(); // 零只占位（三百零五）
        continue;
      }
      if (ch == '万') {
        // 万段收口：一万 → (0+1)*10000；十万 → 10*10000；十五万 → (10+5)*10000
        section = (section + digit) * 10000;
      } else {
        final unit = ch == '十' ? 10.0 : (ch == '百' ? 100.0 : 1000.0);
        section += (digit == 0 ? 1 : digit) * unit;
      }
      digit = 0;
    }

    return section + digit;
  }

  /// 类型提取：收入/支出关键词全文扫描，最早出现的词决定类型；均未出现返回 null
  static int? _extractType(String text) {
    const incomeWords = [
      '收到', '收入', '工资', '薪水', '薪资', '奖金', '红包', '转入', '到账', '退款', '赚',
    ];
    const expenseWords = [
      '花了', '花费', '消费', '支出', '买了', '买', '付了', '付款', '充值', '交了',
    ];

    int bestPos = -1;
    int? type;
    void scan(List<String> words, int t) {
      for (final w in words) {
        final i = text.indexOf(w);
        if (i >= 0 && (bestPos < 0 || i < bestPos)) {
          bestPos = i;
          type = t;
        }
      }
    }

    scan(incomeWords, 0);
    scan(expenseWords, 1);
    return type;
  }

  /// 日期提取：今天/昨天/前天/大前天 与 N号/N日。
  /// N号晚于今天视为上月（记账记录皆为过去时），最早出现的词生效
  static DateTime? _extractDate(String text, DateTime now) {
    const relatives = {'大前天': 3, '前天': 2, '昨天': 1, '今天': 0};
    int bestPos = -1;
    int offset = 0;
    for (final e in relatives.entries) {
      final i = text.indexOf(e.key);
      if (i >= 0 && (bestPos < 0 || i < bestPos)) {
        bestPos = i;
        offset = e.value;
      }
    }
    if (bestPos >= 0) {
      return DateTime(now.year, now.month, now.day - offset);
    }

    final m = RegExp(r'([0-9]{1,2})[号日]').firstMatch(text);
    if (m != null) {
      final day = int.parse(m.group(1)!);
      if (day < 1 || day > 31) return null;
      var d = DateTime(now.year, now.month, day);
      if (d.isAfter(now)) {
        d = DateTime(now.year, now.month - 1, day);
      }
      return d;
    }
    return null;
  }
}

/// 语音解析最终结果：文本提取 + 分类引擎命中 + 置信度自评
class VoiceParseResult {
  final double? amount;
  final bool amountConflict;
  final int? type;
  final DateTime? date;

  /// 分类引擎命中的分类 ID（学习表优先 → 内置规则），未命中为 null（不猜测）
  final String? categoryId;

  /// 命中分类的名称（直接入库与 Snackbar 文案用）
  final String? categoryName;

  const VoiceParseResult({
    this.amount,
    this.amountConflict = false,
    this.type,
    this.date,
    this.categoryId,
    this.categoryName,
  });

  /// 有把握：金额存在、无金额冲突、类型明示、分类命中，四者齐备才直接入库；
  /// 任一缺失落预填表单由用户确认
  bool get isConfident =>
      amount != null &&
      !amountConflict &&
      type != null &&
      categoryId != null;
}

/// 语音记账解析引擎：识别文本 → 提取 + 分类，全程离线。
/// 分类判定与账单导入共用同一 CategoryEngine（学习表 + 内置规则），线索为识别全文
class VoiceTransactionParser {
  final CategoryEngine _engine;
  final CategoryRepository _categories;

  VoiceTransactionParser(this._engine, this._categories);

  Future<VoiceParseResult> parse(String text, {DateTime? now}) async {
    final facts =
        VoiceTextFacts.parse(text, now: now ?? DateTime.now());

    // 类型未明示时不做分类判定（直接入库要求类型词明示，
    // 分类缺失即无把握，预填表单由用户自行选择）
    String? categoryId;
    String? categoryName;
    if (facts.type != null) {
      categoryId = await _engine.classify([text], expectedType: facts.type);
      if (categoryId != null) {
        final cats = await _categories.findByIds({categoryId});
        if (cats.isNotEmpty) {
          categoryName = cats.first.name;
        }
      }
    }

    return VoiceParseResult(
      amount: facts.amount,
      amountConflict: facts.amountConflict,
      type: facts.type,
      date: facts.date,
      categoryId: categoryId,
      categoryName: categoryName,
    );
  }
}
