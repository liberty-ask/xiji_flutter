import 'dart:convert';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';

import '../crypto/crypto_primitives.dart';
import '../data/local/app_database.dart';

/// 发件箱待推送行：三表统一中间结构。
/// [recordType] 同时是表路由 key（transaction/category/budget）。
class SyncPendingRow {
  const SyncPendingRow({
    required this.recordType,
    required this.id,
    required this.version,
    required this.updatedAt,
    required this.deleted,
    required this.familyId,
    required this.payload,
  });

  final String recordType;
  final String id;
  final int version;
  final DateTime updatedAt;
  final bool deleted;
  final String familyId;

  /// 明文载荷（加密前）：recordType + 业务字段，7.4 拉取侧据此原样重建行
  final Map<String, dynamic> payload;
}

/// 客户端发件箱（tasks.md 7.3）：收集本地待推送变更、加密为服务端
/// SyncPushRecord 结构、推送完成后清理标记。
///
/// 同步纪律：本地每次写操作置 syncPending=true（各仓储写路径已落实），
/// 本类只读标记不写标记；清标记仅在收到服务端逐条结果后执行，
/// accepted 与 rejected 均视为使命完成（rejected = 服务端已有更高
/// version，本地旧值无需再推），网络/异常失败则标记保留待重试。
class SyncOutbox {
  SyncOutbox._();

  static const String kTypeTransaction = 'transaction';
  static const String kTypeCategory = 'category';
  static const String kTypeBudget = 'budget';
  static const String kTypeCategoryRule = 'categoryRule';

  /// 业务日期以毫秒时间戳传输（避免 ISO 字符串的时区解析歧义，
  /// 7.4 侧 DateTime.fromMillisecondsSinceEpoch 原样恢复）
  static const String kDateMsField = 'dateMs';

  /// 批量加解密的分块大小（250–500 区间取上限）：一块一次 isolate
  /// 往返，500 条约 20–50ms 的计算量整体落在后台隔离线程。
  static const int kCryptoChunkSize = 500;

  /// 小批量直算门限：日常增量常只有个位数到几十条，isolate 启动
  /// 开销（1–10ms）不划算，直接在该入口内同步计算；仍是批量入口，
  /// 不退回逐条 encryptRecord 调用。
  static const int kCryptoIsolateMinRows = 64;

  /// 收集全部待推送行（含墓碑——墓碑必须上云才能在其它设备收敛删除），
  /// 按 updatedAt 升序保持产生顺序。内置分类只读永不变更、标记恒为
  /// false，不依赖查询特判自然排除。
  ///
  /// [currentFamilyId] 为学习表通道家庭：学习表是用户级表（无
  /// familyId 列），推送通道取当前家庭；为 null（无家庭上下文）时
  /// 跳过学习表收集。多家庭用户换家庭后旧家庭通道的条目不再重推，
  /// 属已知近似（主力单家庭场景完全正确）。
  static Future<List<SyncPendingRow>> collectAll(
    AppDatabase db,
    String? currentFamilyId,
  ) async {
    final rows = <SyncPendingRow>[];

    final txs = await (db.select(db.transactions)
          ..where((t) => t.syncPending.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.updatedAt)]))
        .get();
    for (final t in txs) {
      rows.add(SyncPendingRow(
        recordType: kTypeTransaction,
        id: t.id,
        version: t.version,
        updatedAt: t.updatedAt,
        deleted: t.deleted,
        familyId: t.familyId,
        payload: <String, dynamic>{
          'recordType': kTypeTransaction,
          'type': t.type,
          'categoryId': t.categoryId,
          'amountCents': t.amountCents,
          kDateMsField: t.date.millisecondsSinceEpoch,
          'userId': t.userId,
          'familyId': t.familyId,
          'description': t.description,
          'counterparty': t.counterparty,
          'tradeNo': t.tradeNo,
          'merchantOrderNo': t.merchantOrderNo,
          'payMethod': t.payMethod,
          'platform': t.platform,
          'refundOfId': t.refundOfId,
          'refundedCents': t.refundedCents,
        },
      ));
    }

    final cats = await (db.select(db.categories)
          ..where((c) => c.syncPending.equals(true))
          ..orderBy([(c) => OrderingTerm.asc(c.updatedAt)]))
        .get();
    for (final c in cats) {
      rows.add(SyncPendingRow(
        recordType: kTypeCategory,
        id: c.id,
        version: c.version,
        updatedAt: c.updatedAt,
        deleted: c.deleted,
        familyId: c.familyId,
        payload: <String, dynamic>{
          'recordType': kTypeCategory,
          'name': c.name,
          'icon': c.icon,
          // 分类已中性化：不再上传 type；nameKey 是内置分类的本地显示词条，
          // 随客户端版本发布，不同步（服务端只存密文，无需迁移）
          'isBuiltin': c.isBuiltin,
          'sortOrder': c.sortOrder,
          'familyId': c.familyId,
        },
      ));
    }

    final budgets = await (db.select(db.budgets)
          ..where((b) => b.syncPending.equals(true))
          ..orderBy([(b) => OrderingTerm.asc(b.updatedAt)]))
        .get();
    for (final b in budgets) {
      rows.add(SyncPendingRow(
        recordType: kTypeBudget,
        id: b.id,
        version: b.version,
        updatedAt: b.updatedAt,
        deleted: b.deleted,
        familyId: b.familyId,
        payload: <String, dynamic>{
          'recordType': kTypeBudget,
          'familyId': b.familyId,
          'userId': b.userId,
          'year': b.year,
          'month': b.month,
          'amountCents': b.amountCents,
        },
      ));
    }

    // 学习表（7.6）：用户级数据走当前家庭通道
    if (currentFamilyId != null) {
      final rules = await (db.select(db.categoryRules)
            ..where((r) => r.syncPending.equals(true))
            ..orderBy([(r) => OrderingTerm.asc(r.updatedAt)]))
          .get();
      for (final r in rules) {
        rows.add(SyncPendingRow(
          recordType: kTypeCategoryRule,
          id: r.id,
          version: r.version,
          updatedAt: r.updatedAt,
          deleted: r.deleted,
          familyId: currentFamilyId,
          payload: <String, dynamic>{
            'recordType': kTypeCategoryRule,
            'matchText': r.matchText,
            'categoryId': r.categoryId,
            'source': r.source,
            'hitCount': r.hitCount,
          },
        ));
      }
    }

    return rows;
  }

  /// 待加密行转纯数据头：跨 isolate 只允许 List/String/Map/int 等
  /// 可发送值，[SyncPendingRow]（含 DateTime/Uint8List 引用）不能直接传。
  static Map<String, dynamic> _headOf(SyncPendingRow row) => <String, dynamic>{
        'id': row.id,
        'version': row.version,
        'updatedAt': row.updatedAt.millisecondsSinceEpoch,
        'deleted': row.deleted ? 1 : 0,
        'payload': row.payload,
      };

  /// 批量加密（P1-5：下放 isolate）。按 [kCryptoChunkSize] 分块，每块
  /// 一次 [Isolate.run]，主隔离只等结果不做逐条计算。返回值与 [rows]
  /// 顺序一一对应。空列表不发 isolate。
  static Future<List<Map<String, dynamic>>> encryptBatch(
    Uint8List dataKey,
    List<SyncPendingRow> rows,
  ) async {
    if (rows.length < kCryptoIsolateMinRows) {
      return _encryptChunk(
        dataKey,
        <Map<String, dynamic>>[for (final row in rows) _headOf(row)],
      );
    }
    final out = <Map<String, dynamic>>[];
    for (var start = 0; start < rows.length; start += kCryptoChunkSize) {
      final end = start + kCryptoChunkSize > rows.length
          ? rows.length
          : start + kCryptoChunkSize;
      final heads = <Map<String, dynamic>>[
        for (var i = start; i < end; i++) _headOf(rows[i]),
      ];
      out.addAll(await Isolate.run(() => _encryptChunk(dataKey, heads)));
    }
    return out;
  }

  /// 批量解密（P1-5：下放 isolate）。单条认证失败（他人密钥 / 密文
  /// 换位）以 null 占位，不中断整块；返回值与 [records] 顺序一致。
  static Future<List<Map<String, dynamic>?>> decryptBatch(
    Uint8List dataKey,
    List<Map<String, dynamic>> records,
  ) async {
    if (records.length < kCryptoIsolateMinRows) {
      return _decryptChunk(dataKey, records);
    }
    final out = <Map<String, dynamic>?>[];
    for (var start = 0; start < records.length; start += kCryptoChunkSize) {
      final end = start + kCryptoChunkSize > records.length
          ? records.length
          : start + kCryptoChunkSize;
      final chunk = records.sublist(start, end);
      out.addAll(await Isolate.run(() => _decryptChunk(dataKey, chunk)));
    }
    return out;
  }

  /// isolate 入口：逐条加密一块（AES-GCM 本身是同步 CPU 计算，
  /// 隔离线程内无并发诉求，顺序执行开销最小）。
  static Future<List<Map<String, dynamic>>> _encryptChunk(
    Uint8List dataKey,
    List<Map<String, dynamic>> heads,
  ) async {
    final out = <Map<String, dynamic>>[];
    for (final head in heads) {
      out.add(await _encryptHead(dataKey, head));
    }
    return out;
  }

  /// isolate 入口：逐条解密一块，认证失败记 null 继续
  static Future<List<Map<String, dynamic>?>> _decryptChunk(
    Uint8List dataKey,
    List<Map<String, dynamic>> records,
  ) async {
    final out = <Map<String, dynamic>?>[];
    for (final record in records) {
      try {
        out.add(await _decryptHead(dataKey, record));
      } on SecretBoxAuthenticationError {
        out.add(null);
      }
    }
    return out;
  }

  /// 加密单行为服务端 SyncPushRecord 结构（字段名与
  /// com.xiji SyncPushRecord DTO 一致）。AAD 绑定记录 ID：
  /// 密文换位到其它记录无法通过 7.4 拉取侧解密认证。
  /// ciphertext 为 AEAD 密文‖GCM 认证标签拼接（服务端仅存储透传，
  /// 拼接/拆分是客户端协议约定）。
  static Future<Map<String, dynamic>> encryptRecord(
    Uint8List dataKey,
    SyncPendingRow row,
  ) =>
      _encryptHead(dataKey, _headOf(row));

  /// 单条同步实现（保留作批量路径的对照/单条调用入口）
  static Future<Map<String, dynamic>> _encryptHead(
    Uint8List dataKey,
    Map<String, dynamic> head,
  ) async {
    final plaintext = utf8.encode(jsonEncode(head['payload']));
    final box = await CryptoPrimitives.aeadEncrypt(
      dataKey,
      plaintext,
      aad: utf8.encode(head['id'] as String),
    );
    return <String, dynamic>{
      'id': head['id'],
      'version': head['version'],
      'updatedAt': head['updatedAt'],
      'deleted': head['deleted'],
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.concatenation(nonce: false)),
    };
  }

  /// 解密单条推送记录回明文载荷（7.4 拉取复用；单测验加密往返）。
  /// AAD 不匹配（记录 ID 对不上）抛 [SecretBoxAuthenticationError]。
  static Future<Map<String, dynamic>> decryptRecord(
    Uint8List dataKey,
    Map<String, dynamic> record,
  ) =>
      _decryptHead(dataKey, record);

  /// 单条同步解密实现（保留作批量路径的对照/单条调用入口）
  static Future<Map<String, dynamic>> _decryptHead(
    Uint8List dataKey,
    Map<String, dynamic> record,
  ) async {
    // 拆开 ciphertext 拼接：密文 ‖ 16 字节 GCM 认证标签
    final concatenated = base64Decode(record['ciphertext'] as String);
    const macLength = 16;
    final box = SecretBox(
      concatenated.sublist(0, concatenated.length - macLength),
      nonce: base64Decode(record['nonce'] as String),
      mac: Mac(concatenated.sublist(concatenated.length - macLength)),
    );
    final clear = await CryptoPrimitives.aeadDecrypt(
      dataKey,
      box,
      aad: utf8.encode(record['id'] as String),
    );
    return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
  }

  /// 清理已完成推送的标记（仅传入的行；批次内部分失败时只清成功条）。
  ///
  /// 条件清理（丢更新修复）：必须同时匹配出栈时的 version 与 updatedAt。
  /// 推送在途时用户编辑同一条记录会 version+1 并重新置 sync_pending，
  /// 若仍按 id 无条件清理，这笔新编辑的待推标记会被回执一并抹掉；
  /// 而本地版本更高、拉取侧 LWW 也不会翻案，该编辑将永不上云
  /// （直到用户再次编辑才自愈）。带条件后飞行中产生的更新保持待推。
  static Future<void> clearPending(
    AppDatabase db,
    List<SyncPendingRow> rows,
  ) async {
    if (rows.isEmpty) return;
    // 单批执行：batch 内部为一个事务，且只占一次 isolate 往返。
    await db.batch((b) {
      for (final r in rows) {
        switch (r.recordType) {
          case kTypeTransaction:
            b.update(
              db.transactions,
              const TransactionsCompanion(syncPending: Value(false)),
              where: (t) =>
                  t.id.equals(r.id) &
                  t.version.equals(r.version) &
                  t.updatedAt.equals(r.updatedAt),
            );
            break;
          case kTypeCategory:
            b.update(
              db.categories,
              const CategoriesCompanion(syncPending: Value(false)),
              where: (c) =>
                  c.id.equals(r.id) &
                  c.version.equals(r.version) &
                  c.updatedAt.equals(r.updatedAt),
            );
            break;
          case kTypeBudget:
            b.update(
              db.budgets,
              const BudgetsCompanion(syncPending: Value(false)),
              where: (bd) =>
                  bd.id.equals(r.id) &
                  bd.version.equals(r.version) &
                  bd.updatedAt.equals(r.updatedAt),
            );
            break;
          case kTypeCategoryRule:
            b.update(
              db.categoryRules,
              const CategoryRulesCompanion(syncPending: Value(false)),
              where: (cr) =>
                  cr.id.equals(r.id) &
                  cr.version.equals(r.version) &
                  cr.updatedAt.equals(r.updatedAt),
            );
            break;
          default:
            throw ArgumentError('未知的同步记录类型: ${r.recordType}');
        }
      }
    });
  }
}
