import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiji_flutter/crypto/key_vault.dart';
import 'package:xiji_flutter/crypto/vault_store.dart';
import 'package:xiji_flutter/data/local/app_database.dart';
import 'package:xiji_flutter/services/api/api_client.dart';
import 'package:xiji_flutter/sync/sync_puller.dart';
import 'package:xiji_flutter/sync/sync_scheduler.dart';

/// 任务 7.8：同步与鉴权交互回归。
///
/// 鉴权链路既有实现（ApiClient 401 刷新锁，双 token 改造落地）：
/// - 仅业务请求 401 触发无感刷新（排除 /auth/refresh 自身）
/// - QueuedInterceptor 串行队列：并发 401 仅一次刷新
/// - refresh 被服务端确认拒绝（HTTP 401）→ SessionExpiredException
///   → 清凭证 + onSessionExpired 登出（确定性拒绝才登出）
/// - refresh 网络错误 → 保留凭证与登录态、原请求按普通失败处理
///   （网络错误仅重试不登出）
///
/// 本文件回归 SyncScheduler 侧边界：两类终态异常都不出 maybePush
/// 函数边界、发件箱标记保留待重试；登出动作由 ApiClient 层回调
/// 完成，调度器不参与。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const diningId = '01a15d13-bded-710c-a3bd-aba94a5aeb36';

  late AppDatabase db;

  Future<void> insertTx(String id) async {
    await db.into(db.transactions).insertReturning(
        TransactionsCompanion.insert(
      id: Value(id),
      type: 1,
      categoryId: diningId,
      amountCents: 3000,
      date: DateTime(2026, 10, 1),
      userId: 'user-1',
      familyId: const Value('f1'),
    ));
  }

  Future<int> pendingCount() => db
      .customSelect('SELECT COUNT(*) AS c FROM transactions WHERE sync_pending = 1')
      .map((row) => row.read<int>('c'))
      .getSingle();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'backup_enabled': true,
    });
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  SyncScheduler buildScheduler(SyncPushPort port) {
    final vault = KeyVault(InMemoryVaultStore(), profile: Argon2Profile.fast());
    return SyncScheduler(
      db: db,
      port: port,
      pullPort: _ThrowingPullPort(),
      vault: vault..setup('pw123456'),
      isSignedIn: () async => true,
      currentFamilyId: () async => 'f1',
    );
  }

  group('7.8：同步异常与登出边界', () {
    test('服务端确定性拒绝（SessionExpired）：不崩、标记保留，登出由 ApiClient 层负责', () async {
      await insertTx('tx-1');
      final scheduler = buildScheduler(_SessionExpiredPort());

      // fire-and-forget 语义：异常不出函数边界
      await scheduler.maybePush();

      expect(await pendingCount(), 1,
          reason: '确定性拒绝时发件箱标记保留（登出后回登可补推）');
    });

    test('网络错误（DioException）：不崩、标记保留、不触发登出', () async {
      await insertTx('tx-1');
      var sessionExpiredCalls = 0;
      ApiClient.onSessionExpired = () => sessionExpiredCalls++;
      addTearDown(() => ApiClient.onSessionExpired = null);

      final scheduler = buildScheduler(_NetworkErrorPort());
      await scheduler.maybePush();

      expect(await pendingCount(), 1, reason: '网络错误仅保留标记待重试');
      expect(sessionExpiredCalls, 0,
          reason: '网络错误不触发登出（凭证保留，下次触发自动重推）');
    });

    test('服务端 5xx（业务失败异常）：不崩、标记保留', () async {
      await insertTx('tx-1');
      final scheduler = buildScheduler(_ServerErrorPort());
      await scheduler.maybePush();

      expect(await pendingCount(), 1, reason: '服务端内部错误保留标记待重试');
    });
  });
}

/// 推送端口抛 SessionExpiredException：模拟 refresh 被服务端确认无效
/// 后业务请求以 401 终态失败（ApiClient 拦截器已先行完成登出回调）
class _SessionExpiredPort implements SyncPushPort {
  @override
  Future<Set<String>> push(
      String familyId, List<Map<String, dynamic>> records) async {
    throw SessionExpiredException();
  }
}

/// 推送端口抛连接错误：模拟断网/超时（无服务端响应）
class _NetworkErrorPort implements SyncPushPort {
  @override
  Future<Set<String>> push(
      String familyId, List<Map<String, dynamic>> records) async {
    throw DioException.connectionError(
      requestOptions: RequestOptions(path: '/v1/sync/push'),
      reason: 'Connection refused',
    );
  }
}

/// 推送端口抛业务异常：模拟服务端 5xx / code!=200
class _ServerErrorPort implements SyncPushPort {
  @override
  Future<Set<String>> push(
      String familyId, List<Map<String, dynamic>> records) async {
    throw Exception('服务器内部错误');
  }
}

/// 拉取端口默认抛网络错误：验证任一环节失败整轮安全终止
class _ThrowingPullPort implements SyncPullPort {
  @override
  Future<Map<String, dynamic>> pull(
    String familyId,
    int? cursorTime,
    String? cursorId, {
    String? recordId,
    int? limit,
  }) async {
    throw DioException.connectionError(
      requestOptions: RequestOptions(path: '/v1/sync/pull'),
      reason: 'Connection refused',
    );
  }
}
