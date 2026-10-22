/// 金额元↔分转换（整数分方案，根治浮点累加误差）。
///
/// 语义边界（见 design 金额精度约定）：
/// - 「分」（int）是存储与聚合域的货币单位：本地库 amount_cents 列、
///   SUM 聚合、门面内部累加全部用整数分，加减永远精确
/// - 「元」（double）只出现在对外边界：页面展示、表单输入、门面出参、
///   解析器产出。元 double 是两位小数的近似，仅允许单值存在，
///   禁止在元域做多次累加（那是 15 位小数尾巴的来源）
///
/// 转换的数学安全性：两位小数的元值 ×100 后误差 <1e-9，
/// 距 0.5 的舍入边界有 8 个数量级余量，round 结果确定性正确。
class Money {
  Money._();

  /// 元 → 分：46.2 -> 4620。输入应为两位小数以内的元值。
  static int yuanToCents(double yuan) => (yuan * 100).round();

  /// 分 → 元：4620 -> 46.2。产出仅用于展示/单值传递，禁止再累加。
  static double centsToYuan(int cents) => cents / 100;

  /// 分 → 元字符串（两位小数）：4620 -> "46.20"。
  /// 元 double 近似误差 << 0.005 舍入边界，toStringAsFixed(2) 恒精确。
  static String centsToYuanText(int cents) =>
      (cents / 100).toStringAsFixed(2);

  /// 元字符串 → 分（表单/账单文本解析）：空/非法返回 null。
  static int? yuanTextToCents(String? text) {
    if (text == null) return null;
    final v = double.tryParse(text.trim());
    if (v == null || v.isNaN || v.isInfinite) return null;
    if (v < 0) return null;
    return (v * 100).round();
  }
}
