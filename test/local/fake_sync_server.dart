import 'package:xiji_flutter/sync/sync_puller.dart';

/// 内存假服务端：模拟服务端 (updated_at, id) 游标分页 + LWW upsert。
/// push 侧按 id 幂等、完整 LWW（version 高者胜 → 同 version 看
/// updated_at 新者胜 → 完全相同幂等接受），与 SyncRecordService 对齐。
class FakeSyncServer {
  final Map<String, Map<String, dynamic>> _byId = {};
  final int pageSize;
  final List<({int? cursorTime, String? cursorId})> requests = [];

  FakeSyncServer({this.pageSize = 500});

  /// 设备推送一批记录（服务端 upsert 语义）。
  /// 返回被服务端接受的 id 集合（rejected 的记录服务端保留更高 version）。
  Set<String> push(String familyId, List<Map<String, dynamic>> records) {
    final accepted = <String>{};
    for (final r in records) {
      final id = r['id'] as String;
      final existing = _byId[id];
      if (existing == null ||
          (r['version'] as int) > (existing['version'] as int) ||
          ((r['version'] as int) == (existing['version'] as int) &&
              (r['updatedAt'] as int) > (existing['updatedAt'] as int))) {
        // 落库副本带家庭归属（recordId 精确拉取按它过滤）
        final stored = Map<String, dynamic>.of(r);
        stored['familyId'] = familyId;
        _byId[id] = stored;
        accepted.add(id);
      }
    }
    return accepted;
  }

  /// 服务端 pull 分页（排序 + 游标过滤 + limit+1 探测）；
  /// recordId 非空时精确拉取该单条（家庭归属不匹配返回空，对齐 7.10
  /// 服务端实现）
  Map<String, dynamic> pull(
      String familyId, int? cursorTime, String? cursorId,
      {String? recordId, int? limit}) {
    requests.add((cursorTime: cursorTime, cursorId: cursorId));
    if (recordId != null) {
      final hit = _byId[recordId];
      final mine = (hit != null && hit['familyId'] == familyId)
          ? [Map<String, dynamic>.of(hit)]
          : <Map<String, dynamic>>[];
      return <String, dynamic>{'records': mine, 'hasMore': false};
    }
    final sorted = _byId.values.toList()
      ..sort((a, b) {
        final at = (a['updatedAt'] as int).compareTo(b['updatedAt'] as int);
        return at != 0
            ? at
            : (a['id'] as String).compareTo(b['id'] as String);
      });
    final remaining = sorted.where((r) {
      if (cursorTime == null || cursorId == null) return true;
      final at = (r['updatedAt'] as int).compareTo(cursorTime);
      if (at != 0) return at > 0;
      return (r['id'] as String).compareTo(cursorId) > 0;
    }).toList();

    final effectivePageSize = limit != null && limit > 0
        ? (limit < pageSize ? limit : pageSize)
        : pageSize;
    final probe = remaining.take(effectivePageSize + 1).toList();
    final hasMore = probe.length > effectivePageSize;
    if (hasMore) probe.removeLast();
    return <String, dynamic>{
      // 拷贝返回（调用方篡改不得污染服务端存储）
      'records': probe.map((r) => Map<String, dynamic>.of(r)).toList(),
      'hasMore': hasMore,
      if (hasMore && probe.isNotEmpty)
        'nextCursorTime': probe.last['updatedAt'],
      if (hasMore && probe.isNotEmpty) 'nextCursorId': probe.last['id'],
    };
  }

  /// 服务端当前某条记录（测试断言用）
  Map<String, dynamic>? record(String id) => _byId[id];
}

/// FakeSyncServer 的拉取端口适配
class FakeServerPullPort implements SyncPullPort {
  FakeServerPullPort(this._server);
  final FakeSyncServer _server;

  @override
  Future<Map<String, dynamic>> pull(
    String familyId,
    int? cursorTime,
    String? cursorId, {
    String? recordId,
    int? limit,
  }) async {
    return _server.pull(familyId, cursorTime, cursorId,
        recordId: recordId, limit: limit);
  }
}
