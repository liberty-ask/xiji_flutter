/// 系统内置分类常量表：随 App 版本发布的固定 UUIDv7 常量。
///
/// 约束（分类体系重构方案 2026-11-09 第二版）：
/// - 分类是纯标签，不再有收支类型；同一分类可同时挂支出与收入交易；
///   方向唯一来源是 transactions.type（0 收入 / 1 支出 / 2 不计收支）。
/// - 内置分类 ID 为固定常量，两台设备初始化后完全一致；
/// - name 是业务规范名（规则解析、备份导入按名称匹配、日志排查），
///   nameKey 只负责显示，显示层统一走 CategoryL10n；
/// - hint 仅用于选择器冷启动排序，不落库、不同步、不参与校验。
/// - 图标与 IconConstants 图标库对齐，渲染统一走
///   IconConstants.getIconFromString，禁止各页面自建映射。
enum CategoryHint {
  /// 支出倾向
  expense,

  /// 收入倾向
  income,

  /// 收支双向
  both,

  /// 无倾向（兜底分类）
  neutral,
}

class BuiltinCategory {
  final String id;
  final String name;
  final String icon;

  /// 多语言词条 key（ARB）；内置分类必填，自建分类为 NULL
  final String nameKey;

  /// 选择器排序提示倾向（不落库）
  final CategoryHint hint;

  /// 全局展示顺序 0–24
  final int sortOrder;

  const BuiltinCategory({
    required this.id,
    required this.name,
    required this.icon,
    required this.nameKey,
    required this.hint,
    required this.sortOrder,
  });
}

class BuiltinCategories {
  BuiltinCategories._();

  /// 生成时刻：2026-10，常量一经发布永不改动（改名/换图标走新增+墓碑）
  static const List<BuiltinCategory> all = [
    BuiltinCategory(
        id: '01a15d13-bded-710c-a3bd-aba94a5aeb36',
        name: '餐饮',
        icon: 'restaurant',
        nameKey: 'categoryDining',
        hint: CategoryHint.expense,
        sortOrder: 0),
    BuiltinCategory(
        id: '01a15d13-bdef-76cd-8fad-588d6c75eed0',
        name: '日用',
        icon: 'local_grocery_store',
        nameKey: 'categoryDaily',
        hint: CategoryHint.expense,
        sortOrder: 1),
    BuiltinCategory(
        id: '01a15d13-bdef-75ae-8342-df8b6acf41fa',
        name: '购物',
        icon: 'shopping_cart',
        nameKey: 'categoryShopping',
        hint: CategoryHint.expense,
        sortOrder: 2),
    // 新增：京东「其他网购」29 + 「网购」4 直接支撑
    BuiltinCategory(
        id: '01a0c450-6c00-7ac6-94cb-84afd363380d',
        name: '网购',
        icon: 'shopping_bag',
        nameKey: 'categoryOnlineShopping',
        hint: CategoryHint.expense,
        sortOrder: 3),
    BuiltinCategory(
        id: '01a15d13-bdef-7611-b1fc-61e853292646',
        name: '交通',
        icon: 'directions_bus',
        nameKey: 'categoryTransport',
        hint: CategoryHint.expense,
        sortOrder: 4),
    // 原「居家」改名
    BuiltinCategory(
        id: '01a15d13-bdef-7e40-bc4b-0dd4cca76f2b',
        name: '居住',
        icon: 'home',
        nameKey: 'categoryHousing',
        hint: CategoryHint.expense,
        sortOrder: 5),
    // 原「水电煤」改名
    BuiltinCategory(
        id: '01a15d13-bdef-7b6c-8877-89536b93ea4f',
        name: '水电燃气',
        icon: 'electric_bolt',
        nameKey: 'categoryUtilities',
        hint: CategoryHint.expense,
        sortOrder: 6),
    BuiltinCategory(
        id: '01a15d13-bdef-7a58-b453-255e47763085',
        name: '通讯',
        icon: 'phone',
        nameKey: 'categoryTelecom',
        hint: CategoryHint.expense,
        sortOrder: 7),
    BuiltinCategory(
        id: '01a15d13-bdf0-73cb-b48f-2c8926f276e3',
        name: '娱乐',
        icon: 'movie',
        nameKey: 'categoryEntertainment',
        hint: CategoryHint.expense,
        sortOrder: 8),
    BuiltinCategory(
        id: '01a15d13-bdf0-7287-9691-3c9d73130408',
        name: '医疗',
        icon: 'medical_services',
        nameKey: 'categoryMedical',
        hint: CategoryHint.expense,
        sortOrder: 9),
    BuiltinCategory(
        id: '01a15d13-bdf1-7c4e-9b21-1f3a0d5e8c47',
        name: '保险',
        icon: 'health_and_safety',
        nameKey: 'categoryInsurance',
        hint: CategoryHint.expense,
        sortOrder: 10),
    BuiltinCategory(
        id: '01a15d13-bdf0-723d-a96d-564ec22b8adf',
        name: '教育',
        icon: 'school',
        nameKey: 'categoryEducation',
        hint: CategoryHint.expense,
        sortOrder: 11),
    BuiltinCategory(
        id: '01a15d13-bdf0-7b31-bb46-6bf4de344428',
        name: '旅行',
        icon: 'flight',
        nameKey: 'categoryTravel',
        hint: CategoryHint.expense,
        sortOrder: 12),
    // 新增：支付宝「商业服务」15 + 生活服务/快递
    BuiltinCategory(
        id: '01a0c450-6c00-78b6-b5d2-d70723e19609',
        name: '生活服务',
        icon: 'cleaning_services',
        nameKey: 'categoryServices',
        hint: CategoryHint.expense,
        sortOrder: 13),
    // 新增：支付宝母婴 5 + 京东母婴 10
    BuiltinCategory(
        id: '01a0c450-6c00-79bb-827f-e6ae10eaccf0',
        name: '育儿',
        icon: 'child_care',
        nameKey: 'categoryChildcare',
        hint: CategoryHint.expense,
        sortOrder: 14),
    BuiltinCategory(
        id: '01a15d13-bdf0-750f-aa61-55e4f94ffe2a',
        name: '宠物',
        icon: 'pets',
        nameKey: 'categoryPets',
        hint: CategoryHint.expense,
        sortOrder: 15),
    // 新增：支付宝转账红包 21 + 微信红包/转账 23
    BuiltinCategory(
        id: '01a0c450-6c00-7e73-8686-ea0d383d3f69',
        name: '人情往来',
        icon: 'gift',
        nameKey: 'categorySocial',
        hint: CategoryHint.expense,
        sortOrder: 16),
    BuiltinCategory(
        id: '01a15d13-bdf0-7a5f-993a-8442815623e1',
        name: '工资',
        icon: 'payments',
        nameKey: 'categorySalary',
        hint: CategoryHint.income,
        sortOrder: 17),
    BuiltinCategory(
        id: '01a15d13-bdf0-7644-b686-f047ad95e187',
        name: '奖金',
        icon: 'monetization_on',
        nameKey: 'categoryBonus',
        hint: CategoryHint.income,
        sortOrder: 18),
    BuiltinCategory(
        id: '01a15d13-bdf0-7091-9d3c-cca93860ab8b',
        name: '兼职',
        icon: 'work',
        nameKey: 'categoryPartTime',
        hint: CategoryHint.income,
        sortOrder: 19),
    BuiltinCategory(
        id: '01a15d13-bdf0-757b-821e-3b16cda192df',
        name: '红包',
        icon: 'gift',
        nameKey: 'categoryRedPacket',
        hint: CategoryHint.both,
        sortOrder: 20),
    // 新增：C 级无样本，通用人情收入口径
    BuiltinCategory(
        id: '01a0c450-6c00-7df1-994c-e9f62ca0db0c',
        name: '礼金',
        icon: 'stars',
        nameKey: 'categoryGiftMoney',
        hint: CategoryHint.income,
        sortOrder: 21),
    // 新增：C 级无样本，区别于退款净额法
    BuiltinCategory(
        id: '01a0c450-6c00-797d-ae8a-0581d31691a3',
        name: '报销',
        icon: 'receipt',
        nameKey: 'categoryReimbursement',
        hint: CategoryHint.income,
        sortOrder: 22),
    // 原「其他收入」改名，支出侧杂项共用
    BuiltinCategory(
        id: '01a15d13-bdf0-7264-9899-50ad2df4a8c2',
        name: '其他',
        icon: 'more_horiz',
        nameKey: 'categoryOther',
        hint: CategoryHint.both,
        sortOrder: 23),
    // 原支出侧「未分类」保留为唯一兜底 ID（收入侧同名 ID 已合并删除）
    BuiltinCategory(
        id: '01a15d13-bdf0-7501-9f3a-5c6d90abc12e',
        name: '未分类',
        icon: 'help_outline',
        nameKey: 'categoryUncategorized',
        hint: CategoryHint.neutral,
        sortOrder: 24),
  ];

  /// 已删除的历史内置分类 ID（v10 迁移改挂「其他」，不再作为分类存在）。
  /// 保留常量仅供迁移识别，禁止在新代码中引用为分类。
  static const String removedInvestmentId = '01a15d13-bdf0-7842-87c1-81c76e61eb09';
  static const String removedIncomeUncategorizedId =
      '01a15d13-bdf0-7502-8b7c-4d5e6f70890a';

  /// 按 ID 查找（内置分类判定、显示层取 nameKey 用）
  static BuiltinCategory? byId(String id) {
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// 按规范名查找（内置关键词规则库、备份导入的名称兜底匹配用）。
  /// 分类中性后名称全局唯一，不再需要类型参数。
  static BuiltinCategory? byName(String name) {
    for (final c in all) {
      if (c.name == name) return c;
    }
    return null;
  }

  /// 未分类兜底分类 ID（导入/语音未命中的系统兜底，不等于「其他」）
  static String get uncategorizedId => '01a15d13-bdf0-7501-9f3a-5c6d90abc12e';
}
