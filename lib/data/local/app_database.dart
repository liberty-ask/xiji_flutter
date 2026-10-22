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
  TextColumn get familyId => text().withDefault(const Constant(''))(); // 家庭归属（D11）
  TextColumn get description => text().nullable()();
  TextColumn get counterparty => text().nullable()();
  TextColumn get tradeNo => text().nullable()(); // 平台账单单号，导入去重
  TextColumn get merchantOrderNo => text().nullable()(); // 商户单号
  TextColumn get payMethod => text().nullable()(); // 支付方式
  TextColumn get platform => text().nullable()(); // 所属平台（支付宝/微信/京东），账单导入与迁移写入

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
  // 自定义分类的家庭归属；内置分类全局共享不参与分区（固定 UUID 约束）
  TextColumn get familyId => text().withDefault(const Constant(''))();

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
  TextColumn get familyId =>
      text().withDefault(const Constant(''))(); // 家庭归属（D11）
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
  List<String> get customConstraints => ['UNIQUE(family_id, year, month)'];
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
  int get schemaVersion => 4;

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
      // v3：家庭维度（D11）——交易/分类加列（默认空串归入当前家庭），
      // 预算重建表改唯一约束 UNIQUE(family_id, year, month)
      if (from < 3) {
        await customStatement(
          "ALTER TABLE transactions ADD COLUMN family_id TEXT NOT NULL DEFAULT ''",
        );
        await customStatement(
          "ALTER TABLE categories ADD COLUMN family_id TEXT NOT NULL DEFAULT ''",
        );
        await customStatement(
          'CREATE TABLE budgets_new('
          'id TEXT NOT NULL, '
          "family_id TEXT NOT NULL DEFAULT '', "
          'year INTEGER NOT NULL, '
          'month INTEGER NOT NULL, '
          'amount REAL NOT NULL, '
          'version INTEGER NOT NULL DEFAULT 1, '
          'updated_at INTEGER NOT NULL, '
          'deleted INTEGER NOT NULL DEFAULT 0, '
          'sync_pending INTEGER NOT NULL DEFAULT 1, '
          'PRIMARY KEY (id), '
          'UNIQUE (family_id, year, month))',
        );
        await customStatement(
          'INSERT INTO budgets_new '
          "SELECT id, '', year, month, amount, version, updated_at, "
          'deleted, sync_pending FROM budgets',
        );
        await customStatement('DROP TABLE budgets');
        await customStatement('ALTER TABLE budgets_new RENAME TO budgets');
      }
      // v4：交易补 platform 列（对齐服务端表结构，账单导入与 5.8 迁移写入）
      if (from < 4) {
        await customStatement(
          'ALTER TABLE transactions ADD COLUMN platform TEXT NULL',
        );
      }
    },
  );
}
