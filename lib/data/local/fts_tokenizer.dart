/// FTS5 中文拆字分词器。
///
/// FTS5 默认分词器（unicode61）对中文无效：连续汉字整句被当作单个 token，
/// 子串搜索无法命中。方案：中文及全角符号逐字成 token，英文数字保留整词，
/// 半角标点与空格仅作分隔。写入与查询使用同一规则，查询时拆字后以双引号
/// 短语匹配保证相邻命中。
class FtsTokenizer {
  FtsTokenizer._();

  /// 中文逐字、英文数字整词，生成 FTS 可分词的 token 文本
  static String tokenize(String text) {
    final buffer = StringBuffer();
    var ascii = StringBuffer();
    void flush() {
      if (ascii.isNotEmpty) {
        buffer.write(' $ascii');
        ascii = StringBuffer();
      }
    }

    for (final rune in text.runes) {
      if (rune > 127) {
        flush();
        buffer.write(' ${String.fromCharCode(rune)}');
      } else if (_isWordChar(rune)) {
        ascii.write(String.fromCharCode(rune));
      } else {
        flush(); // 半角标点、空格等：仅作分隔
      }
    }
    flush();
    return buffer.toString().trim();
  }

  /// 构造 FTS5 短语查询串：拆字后以双引号包裹，保证相邻匹配
  static String phrase(String keyword) => '"${tokenize(keyword)}"';

  static bool _isWordChar(int rune) =>
      (rune >= 0x30 && rune <= 0x39) || // 0-9
      (rune >= 0x41 && rune <= 0x5A) || // A-Z
      (rune >= 0x61 && rune <= 0x7A); // a-z
}
