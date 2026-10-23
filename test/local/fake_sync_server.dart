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
        _byId[id] = Map<String, dynamic>.of(r);
        accepted.add(id);
      }
    }
    return accepted;
  }

  /// 服务端 pull 分页（排序 + 游标过滤 + limit+1 探测）
  Map<String, dynamic> pull(
      String familyId, int? cursorTime, String? cursorId) {
    requests.add((cursorTime: cursorTime, cursorId: cursorId));
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

    final probe = remaining.take(pageSize + 1).toList();
    final hasMore = probe.length > pageSize;
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
      String familyId, int? cursorTime, String? cursorId) async {
    return _server.pull(familyId, cursorTime, cursorId);
  }
}
