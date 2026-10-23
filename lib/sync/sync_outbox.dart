import 'dart:convert';

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
          'type': c.type,
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

  /// 加密单行为服务端 SyncPushRecord 结构（字段名与
  /// com.xiji SyncPushRecord DTO 一致）。AAD 绑定记录 ID：
  /// 密文换位到其它记录无法通过 7.4 拉取侧解密认证。
  /// ciphertext 为 AEAD 密文‖GCM 认证标签拼接（服务端仅存储透传，
  /// 拼接/拆分是客户端协议约定）。
  static Future<Map<String, dynamic>> encryptRecord(
    Uint8List dataKey,
    SyncPendingRow row,
  ) async {
    final plaintext = utf8.encode(jsonEncode(row.payload));
    final box = await CryptoPrimitives.aeadEncrypt(
      dataKey,
      plaintext,
      aad: utf8.encode(row.id),
    );
    return <String, dynamic>{
      'id': row.id,
      'version': row.version,
      'updatedAt': row.updatedAt.millisecondsSinceEpoch,
      'deleted': row.deleted ? 1 : 0,
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.concatenation(nonce: false)),
    };
  }

  /// 解密单条推送记录回明文载荷（7.4 拉取复用；单测验加密往返）。
  /// AAD 不匹配（记录 ID 对不上）抛 [SecretBoxAuthenticationError]。
  static Future<Map<String, dynamic>> decryptRecord(
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
  static Future<void> clearPending(
    AppDatabase db,
    List<SyncPendingRow> rows,
  ) async {
    final idsByTable = <String, Set<String>>{};
    for (final r in rows) {
      idsByTable.putIfAbsent(r.recordType, () => <String>{}).add(r.id);
    }
    await db.transaction(() async {
      for (final entry in idsByTable.entries) {
        final ids = entry.value.toList();
        final placeholders = List.filled(ids.length, '?').join(', ');
        await db.customUpdate(
          'UPDATE ${_tableName(entry.key)} '
          'SET sync_pending = 0 WHERE id IN ($placeholders)',
          variables: [for (final id in ids) Variable(id)],
        );
      }
    });
  }

  /// 表名白名单映射（customUpdate 表名不可参数化）
  static String _tableName(String recordType) => switch (recordType) {
        kTypeTransaction => 'transactions',
        kTypeCategory => 'categories',
        kTypeBudget => 'budgets',
        kTypeCategoryRule => 'category_rules',
        _ => throw ArgumentError('未知的同步记录类型: $recordType'),
      };
}
