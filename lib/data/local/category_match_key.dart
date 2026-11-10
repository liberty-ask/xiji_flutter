/// 学习表匹配键归一化。
///
/// 写入（[CategoryRuleRepository.assign]）与读取（[CategoryRuleRepository.findByMatchText]）
/// 共用这一份实现，避免两侧口径漂移。
///
/// 归一化保持保守，只处理"同一商户的不同写法"里最常见且安全的差异：
/// - 折叠全部空白（半角/全角），忽略大小写
/// - 去掉结尾的分店标记：`（1店）`、`(二店)`、`第2号店`、`3号店`
/// - 去掉结尾的常见门店后缀：官方旗舰店 / 旗舰店 / 专营店 / 专卖店 / 直营店 / 分店 / 门店
///
/// 不做的事：不剥离"店""超市"等通用词（会把"水果店"和"水果"错误合并），
/// 不剥离裸数字（"711"、"7-11" 是合法店名的一部分）。
String normalizeCategoryMatchKey(String raw) {
  var key = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s\u3000]+'), '');
  if (key.isEmpty) return key;

  // 结尾括号内的分店/门店标记：（1店）(二店)[3号店]
  key = key.replaceAll(RegExp(r'[（(【\[]\s*[^）)】\]]{0,8}(?:分店|门店|店)\s*[）)】\]]$'), '');
  // 结尾的「第2号店」「3号店」「2分店」
  key = key.replaceAll(RegExp(r'第?\d{1,3}号店$'), '');
  key = key.replaceAll(RegExp(r'第?\d{1,3}分店$'), '');
  // 结尾门店后缀（长后缀优先，避免「官方旗舰店」只被剥成「官方」）
  const suffixes = [
    '官方旗舰店',
    '旗舰店',
    '专营店',
    '专卖店',
    '直营店',
    '分店',
    '门店',
  ];
  for (final suffix in suffixes) {
    if (key.length > suffix.length + 1 && key.endsWith(suffix)) {
      key = key.substring(0, key.length - suffix.length);
      break;
    }
  }
  // 归一化后为空（原文全是符号/空白）时退回原始紧凑形式，不做进一步猜测
  return key;
}
