import '../../parser/bill_csv_parser.dart';
import 'builtin_categories.dart';

/// 账单平台分类 → 内置中性分类映射（方案 4.5 三张表）。
///
/// 口径：平台分类列只是**一层证据**，不是结论。按可信度分两档：
/// - 明确类目（交通、医疗、保险、教育、旅行、数码、母婴、宠物、酒店、服饰等）
///   直接采用，减少关键词层误判；
/// - 含糊类目（餐饮美食、日用百货、商业服务、公共服务、生活服务、美容美发、其他）
///   以及「收钱码收款」「经营码交易」这类收单 MCC 噪声，一律返回 null ——
///   不直接采用，交给上层的关键词规则继续判，判不出由调用方落未分类。
///
/// 微信同样参与这套映射，但不再按平台做任何门控；是否使用商品关键词由上层统一决定。
/// type=2 不计收支的行不映射具体分类（也不参与分类统计）。
class BillCategoryMapper {
  BillCategoryMapper._();

  static String get _dining => _id('餐饮');
  static String get _daily => _id('日用');
  static String get _shopping => _id('购物');
  static String get _onlineShopping => _id('网购');
  static String get _transport => _id('交通');
  static String get _housing => _id('居住');
  static String get _utilities => _id('水电燃气');
  static String get _telecom => _id('通讯');
  static String get _entertainment => _id('娱乐');
  static String get _medical => _id('医疗');
  static String get _insurance => _id('保险');
  static String get _education => _id('教育');
  static String get _travel => _id('旅行');
  static String get _services => _id('生活服务');
  static String get _childcare => _id('育儿');
  static String get _pets => _id('宠物');
  static String get _social => _id('人情往来');
  static String get _redPacket => _id('红包');
  static String get _other => _id('其他');

  static String _id(String name) => BuiltinCategories.byName(name)!.id;

  /// 行级预填：返回分类 ID，null 表示交给关键词层/未分类兜底
  static String? mapRow(ParsedBillRow row) {
    // 不计收支不映射具体分类（也不进分类统计）
    if (row.type == 2) return null;

    return switch (row.platformCode) {
      'alipay' => _mapAlipay(row),
      'jd' => _mapJd(row),
      'wechat' => _mapWechat(row),
      _ => null,
    };
  }

  /// 支付宝：按「交易分类」映射（方案表 10），含糊类目降级
  static String? _mapAlipay(ParsedBillRow row) {
    final category = row.platformCategory?.trim();
    if (category == null || category.isEmpty) return null;

    // 个人/小微商户收款码：类目由收单 MCC 决定，与真实消费性质无关
    if (_isQrPayment(row)) return null;

    switch (category) {
      // —— 明确类目：直接采用 ——
      case '交通出行':
      case '爱车养车':
        return _transport;
      case '医疗健康':
        return _medical;
      case '保险':
        return _insurance;
      case '教育培训':
        return _education;
      case '酒店旅游':
        return _travel;
      case '数码电器':
        return _isPlatformOrder(row) ? _onlineShopping : _shopping;
      case '母婴亲子':
        return _childcare;
      case '宠物':
        return _pets;
      case '家居家装':
        return _housing;
      case '服饰装扮':
        return _shopping;
      case '文化休闲':
        return _entertainment;
      case '转账红包':
        return _socialOrRedPacket(row.type);
      case '红包':
        return _redPacket;
      case '充值缴费':
        return _isUtility(row) ? _utilities : (_isTelecom(row) ? _telecom : null);
      case '信用借还':
        return row.type == 1 ? _other : null; // 手续费归其他，借还本身不映射
      case '收入':
        return _other;

      // —— 含糊类目：不直接采用，交给关键词层 ——
      case '餐饮美食':
      case '日用百货':
      case '商业服务':
      case '公共服务':
      case '生活服务':
      case '美容美发':
      case '其他':
      case '投资理财':
      case '退款':
      case '亲友代付':
      case '亲属卡':
        return null;
      default:
        return null;
    }
  }

  /// 京东：按「交易分类」多标签映射（方案表 11）。
  /// 标签可能用逗号、顿号、斜杠或空格分隔，需全部拆开逐项判定。
  static String? _mapJd(ParsedBillRow row) {
    final raw = row.platformCategory?.trim();
    if (raw == null || raw.isEmpty) return null;

    final labels = raw
        .split(RegExp(r'[\s,，、/|]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);

    for (final label in labels) {
      final mapped = switch (label) {
        '其他网购' || '网购' => _onlineShopping,
        '小金库' || '白条' => null,
        '母婴用品' => _childcare,
        '医疗保健' => _medical,
        '食品酒饮' => _isReadyToEat(row) ? _dining : _daily,
        '美妆个护' || '数码电器' || '珠宝首饰' => _onlineShopping,
        '图书文娱' => _isTextbook(row) ? _education : _entertainment,
        '家居家装' => _housing,
        '日用百货' || '清洁纸品' => _daily,
        '生活服务' || '收发快递' => _services,
        '其他' => null, // 含糊类目：交给关键词层
        _ => null,
      };
      if (mapped != null) return mapped;
    }
    return null;
  }

  /// 微信：按「交易类型」映射（方案表 12）。
  /// 交易类型只区分资金形态，不含消费类别；映射不到的交由学习表/关键词层。
  static String? _mapWechat(ParsedBillRow row) {
    final type = row.transactionType?.trim();
    if (type == null || type.isEmpty) return null;

    switch (type) {
      case '商户消费':
      case '扫二维码付款':
      case '退款':
      case '零钱通转出':
      case '转入零钱通':
      case '信用卡还款':
      case '提现':
      case '充值':
        return null;
      case '转账':
        return _social; // 本人账户互转已由 type=2 拦截，此处为转给他人
      case '微信红包':
        return row.type == 0 ? _redPacket : _social;
      case '其他（收入）':
      case '其他(收入)':
        return _other;
      default:
        return null;
    }
  }

  static String? _socialOrRedPacket(int? type) {
    if (type == 0) return _redPacket; // 收到红包
    if (type == 1) return _social; // 送礼/支出
    return null;
  }

  /// 收钱码收款 / 经营码交易：收款方 MCC 不代表真实消费类别
  static bool _isQrPayment(ParsedBillRow row) {
    final description = row.description ?? '';
    return description.contains('收钱码收款') || description.contains('经营码交易');
  }

  static bool _isUtility(ParsedBillRow row) {
    final text = '${row.counterparty ?? ''}${row.description ?? ''}';
    return _containsAny(text, const [
      '电费', '水费', '燃气', '供电', '自来水', '供热', '电网', '暖气'
    ]);
  }

  static bool _isTelecom(ParsedBillRow row) {
    final text = '${row.counterparty ?? ''}${row.description ?? ''}';
    return _containsAny(text, const [
      '话费', '流量', '宽带', '移动', '联通', '电信', '铁通'
    ]);
  }

  static bool _isPlatformOrder(ParsedBillRow row) {
    final text = '${row.counterparty ?? ''}${row.description ?? ''}';
    return _containsAny(text, const [
      '淘宝', '天猫', '京东', '拼多多', '苏宁', '唯品会', '得物', '商城', '旗舰店'
    ]);
  }

  /// 即食判定：只认"加工后现场消费"，并排除食材/餐具类误命中。
  /// 「餐饮」「即食」这类裸词会命中「餐饮具」「即食燕麦」，不再作为判据。
  static bool _isReadyToEat(ParsedBillRow row) {
    final text = '${row.counterparty ?? ''}${row.description ?? ''}';
    if (_containsAny(text, const [
      '餐饮具', '餐具', '厨具', '咖啡豆', '咖啡粉', '咖啡杯', '咖啡机',
      '奶茶粉', '即食燕麦', '即食面', '方便面',
    ])) {
      return false;
    }
    return _containsAny(text, const [
      '外卖', '快餐', '汉堡', '披萨', '咖啡', '奶茶', '饭店', '火锅', '烧烤', '小吃', '炸鸡', '堂食'
    ]);
  }

  static bool _isTextbook(ParsedBillRow row) {
    final text = '${row.counterparty ?? ''}${row.description ?? ''}';
    return _containsAny(text, const ['教材', '教辅', '考试', '培训', '教育', '图书']);
  }

  static bool _containsAny(String text, List<String> keywords) {
    for (final keyword in keywords) {
      if (text.contains(keyword)) return true;
    }
    return false;
  }
}
