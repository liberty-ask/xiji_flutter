import 'package:drift/drift.dart';

import 'builtin_categories.dart';
import 'transaction_fts.dart';
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
  // 金额整数分（Money.yuanToCents）：存储与聚合域用分，加减精确无浮点尾巴；
  // 元 double 只存在于门面出参与页面展示（见 utils/money.dart 语义边界）
  IntColumn get amountCents => integer()();
  DateTimeColumn get date => dateTime()(); // 业务日期，ID 时间戳不作为时间依据
  TextColumn get userId => text()();
  TextColumn get familyId => text().withDefault(const Constant(''))(); // 家庭归属（D11）
  TextColumn get description => text().nullable()();
  TextColumn get counterparty => text().nullable()();
  TextColumn get tradeNo => text().nullable()(); // 平台账单单号，导入去重
  TextColumn get merchantOrderNo => text().nullable()(); // 商户单号
  TextColumn get payMethod => text().nullable()(); // 支付方式
  TextColumn get platform => text().nullable()(); // 所属平台（支付宝/微信/京东），账单导入与迁移写入
  // 退款冲抵（净额法）：退款记录指向原支出；原支出累计已冲抵退款（分）。
  // refundedCents 冗余在支出行上，跨月退款也能把扣减落在支出所属月份，
  // 且云同步到达顺序错乱时金额仍自洽（退款行自身 type=2 不进统计）
  TextColumn get refundOfId => text().nullable()();
  IntColumn get refundedCents => integer().withDefault(const Constant(0))();

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
  TextColumn get name => text()(); // 业务规范名（规则/导入/日志），显示走 nameKey
  TextColumn get icon => text()(); // Material Icons 名称，渲染统一走 IconConstants
  // 多语言词条 key：内置分类必填，用户自建分类为 NULL（显示原文）
  TextColumn get nameKey => text().nullable()();
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
  // 预算归属成员（D8 个人预算制）：各成员每月各自一条预算，
  // 不同值是正常态而非冲突，LWW 仅仲裁同一成员多设备
  TextColumn get userId => text()();
  IntColumn get year => integer()();
  IntColumn get month => integer()();
  IntColumn get amountCents => integer()();

  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  BoolColumn get syncPending => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        'UNIQUE(family_id, user_id, year, month)'
      ];
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
  /// v6 预算个人化迁移的存量行补种 ID 提供者（登录账号的 userId）。
  /// 惰性调用（onUpgrade 执行时）；测试注入固定值，生产由 Db 提供
  /// LocalUser。一次性语义，迁移完成即不再使用。
  final Future<String> Function()? _migrationSeedUserIdProvider;

  AppDatabase(super.e,
      {Future<String> Function()? migrationSeedUserIdProvider})
      : _migrationSeedUserIdProvider = migrationSeedUserIdProvider;

  @override
  int get schemaVersion => 10;

  /// 系统内置分类种子：固定 UUID 常量，insertOrIgnore 幂等。
  /// 分类中性化后为单一 sortOrder（0–24），name 与 nameKey 随常量表发布。
  Future<void> seedBuiltinCategories() async {
    await batch((b) {
      for (final c in BuiltinCategories.all) {
        b.insert(
          categories,
          CategoriesCompanion.insert(
            id: Value(c.id),
            name: c.name,
            icon: c.icon,
            nameKey: Value(c.nameKey),
            isBuiltin: const Value(true),
            sortOrder: Value(c.sortOrder),
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
      // v2/v9 的内置分类补种在 v10 统一重建时一并完成：旧版本表结构
      // （categories 带 type、无 name_key）无法用新版 Companion 写入，
      // 因此这里不再做中间版本补种，避免迁移链在旧库上写错列。
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
      // v5：金额整数分化（金额精度约定）——amount REAL 元 → amount_cents
      // INTEGER 分，消除浮点累加误差。SQLite 无法改列类型，两表整体重建，
      // 存量元数据 ×100 四舍五入转分
      if (from < 5) {
        await customStatement(
          'CREATE TABLE transactions_new('
          'id TEXT NOT NULL, '
          'type INTEGER NOT NULL, '
          'category_id TEXT NOT NULL, '
          'amount_cents INTEGER NOT NULL, '
          'date INTEGER NOT NULL, '
          'user_id TEXT NOT NULL, '
          "family_id TEXT NOT NULL DEFAULT '', "
          'description TEXT NULL, '
          'counterparty TEXT NULL, '
          'trade_no TEXT NULL, '
          'merchant_order_no TEXT NULL, '
          'pay_method TEXT NULL, '
          'platform TEXT NULL, '
          'version INTEGER NOT NULL DEFAULT 1, '
          'updated_at INTEGER NOT NULL, '
          'deleted INTEGER NOT NULL DEFAULT 0, '
          'sync_pending INTEGER NOT NULL DEFAULT 1, '
          'PRIMARY KEY (id))',
        );
        await customStatement(
          'INSERT INTO transactions_new '
          'SELECT id, type, category_id, '
          'CAST(ROUND(amount * 100) AS INTEGER), '
          'date, user_id, family_id, description, counterparty, trade_no, '
          'merchant_order_no, pay_method, platform, version, updated_at, '
          'deleted, sync_pending FROM transactions',
        );
        await customStatement('DROP TABLE transactions');
        await customStatement(
            'ALTER TABLE transactions_new RENAME TO transactions');

        await customStatement(
          'CREATE TABLE budgets_new('
          'id TEXT NOT NULL, '
          "family_id TEXT NOT NULL DEFAULT '', "
          'year INTEGER NOT NULL, '
          'month INTEGER NOT NULL, '
          'amount_cents INTEGER NOT NULL, '
          'version INTEGER NOT NULL DEFAULT 1, '
          'updated_at INTEGER NOT NULL, '
          'deleted INTEGER NOT NULL DEFAULT 0, '
          'sync_pending INTEGER NOT NULL DEFAULT 1, '
          'PRIMARY KEY (id), '
          'UNIQUE (family_id, year, month))',
        );
        await customStatement(
          'INSERT INTO budgets_new '
          'SELECT id, family_id, year, month, '
          'CAST(ROUND(amount * 100) AS INTEGER), '
          'version, updated_at, deleted, sync_pending FROM budgets',
        );
        await customStatement('DROP TABLE budgets');
        await customStatement('ALTER TABLE budgets_new RENAME TO budgets');
      }
      // v6：预算个人化（D8）——budgets 加 user_id 列（归属成员），
      // 唯一约束 UNIQUE(family_id, year, month) → UNIQUE(family_id,
      // user_id, year, month)；存量行补种本地登录用户 ID（唯一真实
      // 用户场景下旧预算即本人设置）
      if (from < 6) {
        await customStatement(
          'CREATE TABLE budgets_new('
          'id TEXT NOT NULL, '
          "family_id TEXT NOT NULL DEFAULT '', "
          'user_id TEXT NOT NULL, '
          'year INTEGER NOT NULL, '
          'month INTEGER NOT NULL, '
          'amount_cents INTEGER NOT NULL, '
          'version INTEGER NOT NULL DEFAULT 1, '
          'updated_at INTEGER NOT NULL, '
          'deleted INTEGER NOT NULL DEFAULT 0, '
          'sync_pending INTEGER NOT NULL DEFAULT 1, '
          'PRIMARY KEY (id), '
          'UNIQUE (family_id, user_id, year, month))',
        );
        final seedUserId = _migrationSeedUserIdProvider != null
            ? await _migrationSeedUserIdProvider!()
            : '';
        await customStatement(
          'INSERT INTO budgets_new '
          "SELECT id, family_id, ?, year, month, amount_cents, "
          'version, updated_at, deleted, sync_pending FROM budgets',
          [seedUserId],
        );
        await customStatement('DROP TABLE budgets');
        await customStatement('ALTER TABLE budgets_new RENAME TO budgets');
      }
      // v7：退款冲抵（净额法）——交易加退款关联与原支出累计退款额（分）。
      // 存量行默认无关联、已退 0，统计口径与旧版完全一致
      if (from < 7) {
        await customStatement(
          'ALTER TABLE transactions ADD COLUMN refund_of_id TEXT NULL',
        );
        await customStatement(
          'ALTER TABLE transactions ADD COLUMN refunded_cents INTEGER NOT NULL DEFAULT 0',
        );
      }
      // v8：搜索索引自愈——v8 之前同步入库（首轮全量恢复/日常增量）直写
      // transactions 而不维护 transactions_fts，重装/换机后搜索整库为空。
      // 这里做一次性全量重建，回填所有历史缺口；之后由 TransactionFts
      // 在每条写库路径上增量维护。墓碑与空文本行不进索引。
      if (from < 8) {
        await TransactionFts.rebuild(this);
      }
      // v9：新增「保险」支出内置分类。直接按内置集合定义补种：
      // seedBuiltinCategories 走 insertOrIgnore，已存在的内置行不重复插入，
      // 因此对已有库只补缺的那一行，天然幂等
      // （分类中性化后补种统一并入 v10，见上）
      // v10：分类中性化——categories 删除 type、新增 name_key 可空列。
      // SQLite 无法可靠 DROP COLUMN，整体重建；旧 type 丢弃。
      // 两个「未分类」合并到支出侧 ID，「理财」交易改挂「其他」，
      // 内置行清空后按 25 个中性常量重新落库（含改名/改图标/重排序）。
      if (from < 10) {
        await customStatement(
          'CREATE TABLE categories_new('
          'id TEXT NOT NULL, '
          'name TEXT NOT NULL, '
          'icon TEXT NOT NULL, '
          'name_key TEXT NULL, '
          'is_builtin INTEGER NOT NULL DEFAULT 0, '
          'sort_order INTEGER NOT NULL DEFAULT 0, '
          "family_id TEXT NOT NULL DEFAULT '', "
          'version INTEGER NOT NULL DEFAULT 1, '
          'updated_at INTEGER NOT NULL, '
          'deleted INTEGER NOT NULL DEFAULT 0, '
          'sync_pending INTEGER NOT NULL DEFAULT 1, '
          'PRIMARY KEY (id))',
        );
        await customStatement(
          'INSERT INTO categories_new '
          'SELECT id, name, icon, NULL, is_builtin, sort_order, family_id, '
          'version, updated_at, deleted, sync_pending FROM categories',
        );
        // 收入未分类 → 保留的支出未分类 ID
        await customStatement(
          'UPDATE transactions SET category_id = ? WHERE category_id = ?',
          [
            BuiltinCategories.uncategorizedId,
            BuiltinCategories.removedIncomeUncategorizedId,
          ],
        );
        // 理财 → 其他（真实收益归其他，本金流转应走 type=2）
        await customStatement(
          'UPDATE transactions SET category_id = ? WHERE category_id = ?',
          [
            BuiltinCategories.byName('其他')!.id,
            BuiltinCategories.removedInvestmentId,
          ],
        );
        await customStatement('DROP TABLE categories');
        await customStatement('ALTER TABLE categories_new RENAME TO categories');
        // 内置行按新常量整体重写：改名（居住/水电燃气/其他）、nameKey、
        // 单一 sortOrder 与删除理财/收入未分类都在这一步收敛
        await customStatement('DELETE FROM categories WHERE is_builtin = 1');
        await seedBuiltinCategories();
      }
    },
  );
}
