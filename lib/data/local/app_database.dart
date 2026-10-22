import 'package:drift/drift.dart';

import 'builtin_categories.dart';
import 'uuid_v7.dart';

part 'app_database.g.dart';

/// 本地优先架构的唯一数据真身。
///
/// 同步字段约定（所有业务表一致）：
/// - version：LWW 仲裁序号，本地每次修改 +1，初始 1
/// - updatedAt：仲裁辅助时间，取修改时刻
/// - deleted：软删除墓碑，置位后记录参与同步但不出现在查询结果
/// - syncPending：发件箱标记，本地产生未推送的变更置位，推送成功后清除
///
/// 分类删除由业务层校验交易引用（不设外键约束）；账单导入单号去重依赖
/// tradeNo 唯一索引；学习表按 matchText 唯一收敛同一商户的习惯。
class Transactions extends Table {
  TextColumn get id => text().clientDefault(() => UuidV7.generate())();
  IntColumn get type => integer()(); // 0-收入 1-支出 2-不计收支
  TextColumn get categoryId => text()();
  RealColumn get amount => real()();
  DateTimeColumn get date => dateTime()(); // 业务日期，ID 时间戳不作为时间依据
  TextColumn get userId => text()();
  TextColumn get description => text().nullable()();
  TextColumn get counterparty => text().nullable()();
  TextColumn get tradeNo => text().nullable()(); // 平台账单单号，导入去重
  TextColumn get merchantOrderNo => text().nullable()(); // 商户单号
  TextColumn get payMethod => text().nullable()(); // 支付方式

  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  BoolColumn get syncPending => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

class Categories extends Table {
  TextColumn get id => text().clientDefault(() => UuidV7.generate())();
  TextColumn get name => text()();
  TextColumn get icon => text()(); // Material Icons 名称，渲染统一走 IconConstants
  IntColumn get type => integer()(); // 0-收入 1-支出
  BoolColumn get isBuiltin => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  BoolColumn get syncPending => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

class Budgets extends Table {
  TextColumn get id => text().clientDefault(() => UuidV7.generate())();
  IntColumn get year => integer()();
  IntColumn get month => integer()();
  RealColumn get amount => real()();

  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  BoolColumn get syncPending => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['UNIQUE(year, month)'];
}

/// 本地分类学习表：语音与账单导入双向喂养，同一匹配文本收敛为单条
class CategoryRules extends Table {
  TextColumn get id => text().clientDefault(() => UuidV7.generate())();
  TextColumn get matchText => text()(); // 交易对方等分类线索
  TextColumn get categoryId => text()();
  IntColumn get source => integer()(); // 0-账单导入 1-语音记账
  IntColumn get hitCount => integer().withDefault(const Constant(0))();

  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  BoolColumn get syncPending => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['UNIQUE(match_text)'];
}

@DriftDatabase(tables: [Transactions, Categories, Budgets, CategoryRules])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 2;

  /// 系统内置分类种子：固定 UUID 常量，insertOrIgnore 幂等。
  /// sortOrder 按类型分别计数（支出 0-12、收入 0-6），保证同类型内顺序稳定
  Future<void> seedBuiltinCategories() async {
    final sortIndexByType = <int, int>{};
    await batch((b) {
      for (final c in BuiltinCategories.all) {
        final index = sortIndexByType.update(c.type, (v) => v + 1,
            ifAbsent: () => 0);
        b.insert(
          categories,
          CategoriesCompanion.insert(
            id: Value(c.id),
            name: c.name,
            icon: c.icon,
            type: c.type,
            isBuiltin: const Value(true),
            sortOrder: Value(index),
            // 内置分类随 App 发布，非用户变更，不进发件箱
            syncPending: const Value(false),
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      // 交易全文索引：中文拆字方案（demo 验证），内容为描述 + 交易对方。
      // tx_id 列存主表 UUID（UNINDEXED 不参与索引），避免 INTEGER rowid 关联
      await customStatement(
        'CREATE VIRTUAL TABLE transactions_fts USING fts5(fts_text, tx_id UNINDEXED)',
      );
      await seedBuiltinCategories();
    },
    onUpgrade: (m, from, to) async {
      // v2：新增「未分类」兜底内置分类（账单导入/语音未命中），补种常量表
      if (from < 2) {
        await seedBuiltinCategories();
      }
    },
  );
}
