/// 系统内置分类常量表：随 App 版本发布的固定 UUIDv7 常量。
///
/// 约束（spec: local-data / 分类 ID 生成规则）：
/// - 内置分类 ID 为固定常量，两台设备初始化后完全一致；
/// - 名称与图标已与 IconConstants 图标库对齐，图标渲染统一走
///   IconConstants.getIconFromString，禁止各页面自建映射。
class BuiltinCategory {
  final String id;
  final String name;
  final String icon;
  final int type; // 0-收入 1-支出

  const BuiltinCategory({
    required this.id,
    required this.name,
    required this.icon,
    required this.type,
  });
}

class BuiltinCategories {
  BuiltinCategories._();

  /// 生成时刻：2026-10，常量一经发布永不改动（改名/换图标走新增+墓碑）
  static const List<BuiltinCategory> all = [
    // ---- 支出 ----
    BuiltinCategory(
        id: '01a15d13-bded-710c-a3bd-aba94a5aeb36',
        name: '餐饮',
        icon: 'restaurant',
        type: 1),
    BuiltinCategory(
        id: '01a15d13-bdef-75ae-8342-df8b6acf41fa',
        name: '购物',
        icon: 'shopping_cart',
        type: 1),
    BuiltinCategory(
        id: '01a15d13-bdef-7611-b1fc-61e853292646',
        name: '交通',
        icon: 'directions_bus',
        type: 1),
    BuiltinCategory(
        id: '01a15d13-bdef-76cd-8fad-588d6c75eed0',
        name: '日用',
        icon: 'local_grocery_store',
        type: 1),
    BuiltinCategory(
        id: '01a15d13-bdef-7e40-bc4b-0dd4cca76f2b',
        name: '居家',
        icon: 'home',
        type: 1),
    BuiltinCategory(
        id: '01a15d13-bdef-7b6c-8877-89536b93ea4f',
        name: '水电煤',
        icon: 'electric_bolt',
        type: 1),
    BuiltinCategory(
        id: '01a15d13-bdef-7a58-b453-255e47763085',
        name: '通讯',
        icon: 'phone',
        type: 1),
    BuiltinCategory(
        id: '01a15d13-bdf0-73cb-b48f-2c8926f276e3',
        name: '娱乐',
        icon: 'movie',
        type: 1),
    BuiltinCategory(
        id: '01a15d13-bdf0-7287-9691-3c9d73130408',
        name: '医疗',
        icon: 'medical_services',
        type: 1),
    BuiltinCategory(
        id: '01a15d13-bdf0-723d-a96d-564ec22b8adf',
        name: '教育',
        icon: 'school',
        type: 1),
    BuiltinCategory(
        id: '01a15d13-bdf0-7b31-bb46-6bf4de344428',
        name: '旅行',
        icon: 'flight',
        type: 1),
    BuiltinCategory(
        id: '01a15d13-bdf0-750f-aa61-55e4f94ffe2a',
        name: '宠物',
        icon: 'pets',
        type: 1),
    // 未分类（账单导入/语音未命中兜底），排在支出段最后
    BuiltinCategory(
        id: '01a15d13-bdf0-7501-9f3a-5c6d90abc12e',
        name: '未分类',
        icon: 'help_outline',
        type: 1),
    // ---- 收入 ----
    BuiltinCategory(
        id: '01a15d13-bdf0-7a5f-993a-8442815623e1',
        name: '工资',
        icon: 'payments',
        type: 0),
    BuiltinCategory(
        id: '01a15d13-bdf0-7644-b686-f047ad95e187',
        name: '奖金',
        icon: 'monetization_on',
        type: 0),
    BuiltinCategory(
        id: '01a15d13-bdf0-7842-87c1-81c76e61eb09',
        name: '理财',
        icon: 'trending_up',
        type: 0),
    BuiltinCategory(
        id: '01a15d13-bdf0-7091-9d3c-cca93860ab8b',
        name: '兼职',
        icon: 'work',
        type: 0),
    BuiltinCategory(
        id: '01a15d13-bdf0-757b-821e-3b16cda192df',
        name: '红包',
        icon: 'gift',
        type: 0),
    BuiltinCategory(
        id: '01a15d13-bdf0-7264-9899-50ad2df4a8c2',
        name: '其他收入',
        icon: 'more_horiz',
        type: 0),
    // 未分类（兜底），排在收入段最后
    BuiltinCategory(
        id: '01a15d13-bdf0-7502-8b7c-4d5e6f70890a',
        name: '未分类',
        icon: 'help_outline',
        type: 0),
  ];

  /// 按 ID 查找（内置分类判定用）
  static BuiltinCategory? byId(String id) {
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// 按名称+类型查找（内置关键词规则库的分类名解析用）。
  /// 同名不同类型允许并存（如「未分类」支出/收入），必须带类型区分。
  static BuiltinCategory? byName(String name, int type) {
    for (final c in all) {
      if (c.name == name && c.type == type) return c;
    }
    return null;
  }

  /// 未分类兜底分类 ID（type=2 不计收支沿用支出侧未分类，
  /// 与服务端「不计收支挂支出分类」的既有语义一致）
  static String get uncategorizedExpenseId => '01a15d13-bdf0-7501-9f3a-5c6d90abc12e';
  static String get uncategorizedIncomeId => '01a15d13-bdf0-7502-8b7c-4d5e6f70890a';
}
