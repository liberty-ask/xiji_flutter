import 'dart:typed_data';

import '../data/local/app_database.dart';
import '../data/local/current_family_store.dart';
import '../data/local/local_user.dart';
import '../services/api/api_client.dart';
import 'sync_cursor_store.dart';
import 'sync_ingest.dart';

/// 拉取端口：按家庭拉取一页云端记录。测试注入假实现。
/// 响应结构与服务端 SyncPullResponse 一致：
/// {records: [{id, version, updatedAt, deleted, nonce, ciphertext}],
///  hasMore, nextCursorTime, nextCursorId}
abstract class SyncPullPort {
  Future<Map<String, dynamic>> pull(
    String familyId,
    int? cursorTime,
    String? cursorId,
  );
}

/// 生产端口：走 ApiClient 调用 GET /v1/sync/pull。
class ApiSyncPullPort implements SyncPullPort {
  @override
  Future<Map<String, dynamic>> pull(
    String familyId,
    int? cursorTime,
    String? cursorId,
  ) async {
    return await ApiClient().get<Map<String, dynamic>>(
      '/v1/sync/pull',
      queryParameters: <String, dynamic>{
        'familyId': familyId,
        if (cursorTime != null) 'cursorTime': cursorTime,
        if (cursorId != null) 'cursorId': cursorId,
      },
    );
  }
}

/// 拉取-解密-入库循环（tasks.md 7.4）：
///
/// - 增量：从持久化游标继续；新设备无游标 → 服务端全量返回
/// - 分页：hasMore 翻页直到取完（全量恢复时页数多但一次性完成）
/// - 崩溃安全：每页全部入库成功才推进游标，中途失败游标不动，
///   下次从断点重拉（LWW 幂等，重拉无害）
/// - 解密失败单页整体终止（密钥错=全量失败，不推进游标）
/// - 拉取范围：当前家庭（查看哪个家庭就同步哪个家庭）
class SyncPuller {
  SyncPuller({
    required AppDatabase db,
    SyncPullPort? port,
    Future<String?> Function()? currentFamilyId,
  })  : _db = db,
        _port = port ?? ApiSyncPullPort(),
        _currentFamilyId = currentFamilyId ?? CurrentFamilyStore.get;

  final AppDatabase _db;
  final SyncPullPort _port;
  final Future<String?> Function() _currentFamilyId;

  /// 拉取当前家庭的全部增量并入库。
  /// 任何失败异常上抛（由调度器按「游标不动、下次重拉」处理）。
  Future<void> pullAll(Uint8List dataKey) async {
    final familyId = await _currentFamilyId();
    if (familyId == null) return;

    final ingest = SyncIngest(
      _db,
      userId: () => LocalUser.load().then((u) => u?.id),
    );
    var cursor = await SyncCursorStore.load(familyId);

    while (true) {
      final page = await _port.pull(
        familyId,
        cursor?.time,
        cursor?.id,
      );
      final records =
          (page['records'] as List? ?? const []).cast<Map<String, dynamic>>();
      // 页级事务（全量恢复性能优化）：每页 500 条包一个事务提交，
      // 避免逐条独立提交的 journal fsync（万条数据恢复从几十秒降到
      // 秒级）。页内任一条失败整页回滚、游标不推进，与页级断点续拉
      // 语义完全一致（LWW 幂等，重拉无害）。首页 watch 流在提交后
      // 一次刷新（比逐条连刷更省 UI 开销）。
      if (records.isNotEmpty) {
        await _db.transaction(() async {
          for (final record in records) {
            await ingest.applyRecord(dataKey, record);
          }
        });
      }
      final hasMore = page['hasMore'] as bool? ?? false;
      if (hasMore) {
        // 服务端在 hasMore=true 时给出本页末条位置作为下页游标
        final nextTime = page['nextCursorTime'] as int;
        final nextId = page['nextCursorId'] as String;
        await SyncCursorStore.save(familyId, nextTime, nextId);
        cursor = (time: nextTime, id: nextId);
      } else {
        // 尾页服务端不给游标，取本页末条 (updatedAt, id) 落位，
        // 下次增量从此继续；空页（云端无记录）保持旧游标不动
        if (records.isNotEmpty) {
          final last = records.last;
          await SyncCursorStore.save(familyId, last['updatedAt'] as int,
              last['id'] as String);
        }
        break;
      }
    }
  }
}
