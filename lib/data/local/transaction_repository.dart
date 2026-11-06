import 'package:drift/drift.dart';

import 'app_database.dart';
import 'fts_tokenizer.dart';

/// 交易 Repository：本地库唯一数据真身的读写入口。
///
/// 同步纪律（所有变更方法共同遵守）：
/// - 每次变更 version+1、updatedAt=now、syncPending=true（进发件箱）
/// - 删除为软删除墓碑：deleted=true，行保留参与同步，不出现在任何查询结果
/// - FTS 索引与主表同事务双写；FTS 的 tx_id 列存主表 UUID（UNINDEXED），
///   规避 INTEGER rowid 与 TEXT 主键的类型错位
class TransactionRepository {
  final AppDatabase _db;

  TransactionRepository(this._db);

  String _ftsText(Transaction row) {
    final parts = [row.description, row.counterparty]
        .whereType<String>()
        .where((s) => s.isNotEmpty);
    return FtsTokenizer.tokenize(parts.join(' '));
  }

  Future<void> _ftsInsert(Transaction row) async {
    final fts = _ftsText(row);
    if (fts.isEmpty) return;
    await _db.customInsert(
      'INSERT INTO transactions_fts(fts_text, tx_id) VALUES (?, ?)',
      variables: [Variable(fts), Variable(row.id)],
    );
  }

  Future<void> _ftsRemove(String id) => _db.customUpdate(
        'DELETE FROM transactions_fts WHERE tx_id = ?',
        variables: [Variable(id)],
      );

  /// 新增交易：主表 + FTS 同事务写入，返回完整行（含客户端生成的 UUIDv7）
  Future<Transaction> insert(TransactionsCompanion t) {
    return _db.transaction(() async {
      final row = await _db.into(_db.transactions).insertReturning(t);
      await _ftsInsert(row);
      return row;
    });
  }

  /// 批量新增（账单导入用）：单事务整体写入，任一行失败整体回滚，
  /// FTS 与主表逐行双写。去重过滤由上层完成（BillImportService）
  Future<void> insertAll(List<TransactionsCompanion> list) {
    return _db.transaction(() async {
      for (final t in list) {
        final row = await _db.into(_db.transactions).insertReturning(t);
        await _ftsInsert(row);
      }
    });
  }

  /// 账单导入去重键：平台单号 + 商家单号。
  ///
  /// 京东同一订单号的付款行与退款行（价保/部分退款）商家单号不同，是两笔
  /// 不同交易，单键 tradeNo 会把其中一行当重复吞掉。商家单号缺失时退化为
  /// 平台单号（支付宝/微信单号本身即逐笔唯一，行为不变）
  static String importKey(String tradeNo, String? merchantOrderNo) =>
      merchantOrderNo == null || merchantOrderNo.isEmpty
          ? tradeNo
          : '$tradeNo|$merchantOrderNo';

  /// 已存在的导入去重键集合（不含墓碑行：软删记录不占单号，删除后可重导，
  /// 重导生成新 id 独立参与同步仲裁）。家庭维度：仅比对当前家庭的单号
  Future<Set<String>> findExistingImportKeys(
      String familyId, Set<String> tradeNos) {
    if (tradeNos.isEmpty) return Future.value(const {});
    final query = _db.selectOnly(_db.transactions)
      ..addColumns([_db.transactions.tradeNo, _db.transactions.merchantOrderNo])
      ..where(_db.transactions.tradeNo.isIn(tradeNos) &
          _db.transactions.familyId.equals(familyId) &
          _db.transactions.deleted.equals(false));
    return query
        .map((row) => importKey(
              row.read(_db.transactions.tradeNo)!,
              row.read(_db.transactions.merchantOrderNo),
            ))
        .get()
        .then((list) => list.toSet());
  }

  /// 编辑交易：version+1、updatedAt 刷新、syncPending 置位，FTS 同步重建
  Future<Transaction> update(String id, TransactionsCompanion changes) {
    return _db.transaction(() async {
      final current = await (_db.select(_db.transactions)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (current == null) {
        throw StateError('交易不存在: $id');
      }

      // 已冲抵退款的支出：金额不得低于已退额，否则净额变负。
      // 校验以本地库当前值为准（含同步写入的其他设备退款），仅拦金额下限
      final nextAmount = changes.amountCents.present
          ? changes.amountCents.value
          : current.amountCents;
      if (nextAmount < current.refundedCents) {
        throw Exception(
            '该笔交易已退款${(current.refundedCents / 100).toStringAsFixed(2)}元，'
            '金额不能低于已退款金额');
      }

      final row = await (_db.update(_db.transactions)
            ..where((t) => t.id.equals(id)))
          .writeReturning(TransactionsCompanion(
        type: changes.type,
        categoryId: changes.categoryId,
        amountCents: changes.amountCents,
        date: changes.date,
        description: changes.description,
        counterparty: changes.counterparty,
        tradeNo: changes.tradeNo,
        merchantOrderNo: changes.merchantOrderNo,
        payMethod: changes.payMethod,
        version: Value(current.version + 1),
        updatedAt: Value(DateTime.now()),
        syncPending: const Value(true),
      ));

      final updated = row.single;
      await _ftsRemove(id);
      await _ftsInsert(updated);
      return updated;
    });
  }

  /// 删除交易（软删除墓碑）：行保留参与同步，FTS 摘除，列表查询不可见。
  /// 退款冲抵（净额法）联动：
  /// - 删退款行 → 原支出已退额回冲（支出金额恢复）
  /// - 删原支出 → 级联删其退款行，避免悬空关联导致金额错乱
  Future<void> softDelete(String id) {
    return _db.transaction(() async {
      final current = await (_db.select(_db.transactions)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (current == null) return;

      final refundOfId = current.refundOfId;
      if (refundOfId != null && refundOfId.isNotEmpty) {
        await _restoreExpenseRefunded(refundOfId, current.amountCents);
      } else {
        final refunds = await (_db.select(_db.transactions)
              ..where((t) =>
                  t.refundOfId.equals(id) & t.deleted.equals(false)))
            .get();
        for (final r in refunds) {
          await (_db.update(_db.transactions)..where((t) => t.id.equals(r.id)))
              .write(TransactionsCompanion(
            version: Value(r.version + 1),
            updatedAt: Value(DateTime.now()),
            deleted: const Value(true),
            syncPending: const Value(true),
          ));
          await _ftsRemove(r.id);
        }
      }

      await (_db.update(_db.transactions)
            ..where((t) => t.id.equals(id)))
          .write(TransactionsCompanion(
        version: Value(current.version + 1),
        updatedAt: Value(DateTime.now()),
        deleted: const Value(true),
        syncPending: const Value(true),
      ));
      await _ftsRemove(id);
    });
  }

  /// 退款删除时回冲原支出已退额（分域减法，不低于 0）
  Future<void> _restoreExpenseRefunded(String expenseId, int cents) async {
    final expense = await (_db.select(_db.transactions)
          ..where((t) => t.id.equals(expenseId) & t.deleted.equals(false)))
        .getSingleOrNull();
    if (expense == null) return;
    final remaining = expense.refundedCents - cents;
    final next = remaining < 0 ? 0 : remaining;
    if (next == expense.refundedCents) return;
    await (_db.update(_db.transactions)
          ..where((t) => t.id.equals(expenseId)))
        .write(TransactionsCompanion(
      refundedCents: Value(next),
      version: Value(expense.version + 1),
      updatedAt: Value(DateTime.now()),
      syncPending: const Value(true),
    ));
  }

  /// 退款关联候选原支出：同单号、支出、未删除、仍有可退余额。
  /// 家庭维度：仅当前家庭；按业务日期升序取最早一笔（同单号多支出时兜底）
  Future<List<Transaction>> findLinkableExpenses(
      String familyId, Set<String> tradeNos) async {
    if (tradeNos.isEmpty) return const [];
    return (_db.select(_db.transactions)
          ..where((t) =>
              t.tradeNo.isIn(tradeNos) &
              t.familyId.equals(familyId) &
              t.type.equals(1) &
              t.deleted.equals(false))
          ..orderBy([
            (t) => OrderingTerm(expression: t.date, mode: OrderingMode.asc),
          ]))
        .get();
  }

  /// 批量累加原支出的已退款额（导入关联退款时用，单事务）。
  /// 上限为原支出金额，version+1 进发件箱
  Future<void> addRefundedCents(Map<String, int> deltasByExpenseId) {
    return _db.transaction(() async {
      for (final entry in deltasByExpenseId.entries) {
        if (entry.value <= 0) continue;
        final expense = await (_db.select(_db.transactions)
              ..where((t) => t.id.equals(entry.key) & t.deleted.equals(false)))
            .getSingleOrNull();
        if (expense == null) continue;
        final next = expense.refundedCents + entry.value;
        final capped = next > expense.amountCents ? expense.amountCents : next;
        if (capped == expense.refundedCents) continue;
        await (_db.update(_db.transactions)
              ..where((t) => t.id.equals(entry.key)))
            .write(TransactionsCompanion(
          refundedCents: Value(capped),
          version: Value(expense.version + 1),
          updatedAt: Value(DateTime.now()),
          syncPending: const Value(true),
        ));
      }
    });
  }

  /// 列表查询：排除墓碑，按业务日期倒序（date 字段，非 ID 时间戳）。
  /// 家庭维度：仅当前家庭的交易
  Future<List<Transaction>> listAll(String familyId) {
    final query = _db.select(_db.transactions)
      ..where((t) =>
          t.deleted.equals(false) & t.familyId.equals(familyId))
      ..orderBy([
        (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
        (t) =>
            OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
      ]);
    return query.get();
  }

  /// 单条查询（排除墓碑）
  Future<Transaction?> findById(String id) {
    return (_db.select(_db.transactions)
          ..where((t) => t.id.equals(id) & t.deleted.equals(false)))
        .getSingleOrNull();
  }

  /// 交易明细通用查询：类型/日期范围/单日/用户筛选 + FTS 关键词 + 分页，
  /// 排除墓碑，按业务日期倒序。明细列表、筛选、搜索共用此入口。
  /// 家庭维度：仅 [familyId] 家庭的交易。
  Future<List<Transaction>> query({
    required String familyId,
    int? type,
    DateTime? start, // 含
    DateTime? end, // 含
    DateTime? day, // 单日（含当天全天）
    String? userId,
    String? keyword,
    int? page, // 从 1 起
    int? pageSize,
  }) {
    final where = <String>['t.deleted = 0', 't.family_id = ?'];
    final variables = <Variable>[Variable(familyId)];

    if (type != null) {
      where.add('t.type = ?');
      variables.add(Variable(type));
    }
    DateTime? startBound = start;
    DateTime? endBound = end;
    if (day != null) {
      startBound = day;
      endBound = day.add(const Duration(days: 1))
          .subtract(const Duration(microseconds: 1));
    }
    if (startBound != null) {
      where.add('t.date >= ?');
      variables.add(Variable<DateTime>(startBound));
    }
    if (endBound != null) {
      where.add('t.date <= ?');
      variables.add(Variable<DateTime>(endBound));
    }
    if (userId != null && userId.isNotEmpty) {
      where.add('t.user_id = ?');
      variables.add(Variable(userId));
    }

    // 关键词：FTS 短语匹配（中文拆字），空串忽略
    var ftsJoin = '';
    final effectiveKeyword = keyword?.trim() ?? '';
    if (effectiveKeyword.isNotEmpty) {
      ftsJoin = 'JOIN transactions_fts f ON t.id = f.tx_id';
      where.add('f.transactions_fts MATCH ?');
      variables.add(Variable(FtsTokenizer.phrase(effectiveKeyword)));
    }

    // 分页（pageSize 为空则不分页）
    var limitClause = '';
    if (pageSize != null) {
      final currentPage = (page != null && page > 0) ? page : 1;
      limitClause = 'LIMIT ? OFFSET ?';
      variables
        ..add(Variable(pageSize))
        ..add(Variable((currentPage - 1) * pageSize));
    }

    return _db.customSelect(
      'SELECT t.* FROM transactions t $ftsJoin '
      'WHERE ${where.join(' AND ')} '
      'ORDER BY t.date DESC, t.updated_at DESC $limitClause',
      variables: variables,
      readsFrom: {_db.transactions},
    ).map(_mapRow).get();
  }

  /// 首页近期动态：排除墓碑与不计收支（type=2），最近 N 条。
  /// 家庭维度：仅 [familyId] 家庭的交易
  Future<List<Transaction>> recent(String familyId, int limit) {
    return _db.customSelect(
      'SELECT t.* FROM transactions t '
      'WHERE t.deleted = 0 AND t.type != 2 AND t.family_id = ? '
      'ORDER BY t.date DESC, t.updated_at DESC LIMIT ?',
      variables: [Variable(familyId), Variable(limit)],
      readsFrom: {_db.transactions},
    ).map(_mapRow).get();
  }

  /// FTS5 全文搜索：中文拆字短语匹配，排除墓碑，按日期倒序。
  /// 家庭维度：仅 [familyId] 家庭的交易
  Future<List<Transaction>> search(String familyId, String keyword) {
    return query(familyId: familyId, keyword: keyword);
  }

  // 与生成代码 mapFromRow 等价的手动映射（2.31 的 mapFromRow 为异步）
  Transaction _mapRow(QueryRow row) {
    return Transaction(
      id: row.read<String>('id'),
      type: row.read<int>('type'),
      categoryId: row.read<String>('category_id'),
      amountCents: row.read<int>('amount_cents'),
      date: row.read<DateTime>('date'),
      userId: row.read<String>('user_id'),
      familyId: row.read<String>('family_id'),
      description: row.readNullable<String>('description'),
      counterparty: row.readNullable<String>('counterparty'),
      tradeNo: row.readNullable<String>('trade_no'),
      merchantOrderNo: row.readNullable<String>('merchant_order_no'),
      payMethod: row.readNullable<String>('pay_method'),
      platform: row.readNullable<String>('platform'),
      refundOfId: row.readNullable<String>('refund_of_id'),
      refundedCents: row.read<int>('refunded_cents'),
      version: row.read<int>('version'),
      updatedAt: row.read<DateTime>('updated_at'),
      deleted: row.read<bool>('deleted'),
      syncPending: row.read<bool>('sync_pending'),
    );
  }
}
