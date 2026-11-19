import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../crypto/crypto_primitives.dart';
import '../crypto/key_vault.dart';
import '../crypto/vault_provider.dart';
import '../data/local/app_database.dart';
import '../data/local/current_family_store.dart';
import '../data/local/db_provider.dart';
import '../data/local/local_user.dart';
import '../data/local/member_public_key_store.dart';
import '../services/api/api_client.dart';
import 'family_key_service.dart';
import 'sync_cursor_store.dart';
import 'sync_outbox.dart';
import 'sync_puller.dart';
import 'vault_sync_service.dart';

/// 推送端口：按家庭推送一批记录，返回「使命完成」的记录 ID 集合
/// （accepted 与 rejected 均含——rejected 即服务端 LWW 仲裁已有更高
/// version，本地旧值无需再推）。测试注入假实现。
abstract class SyncPushPort {
  Future<Set<String>> push(
    String familyId,
    List<Map<String, dynamic>> records,
  );
}

/// 服务端以确定性理由拒绝了这批记录（参数超限、字段校验失败等）：
/// 同一批原样重放不会成功，调度器据此拆半定位到具体坏记录。
/// 网络异常 / 5xx / 超时 / 登录态与权限问题不走此异常（按暂时性保留）。
class SyncPushDeterministicException implements Exception {
  const SyncPushDeterministicException(this.message);

  final String message;

  @override
  String toString() => 'SyncPushDeterministicException: $message';
}

/// 生产端口：走 ApiClient 调用 POST /v1/sync/push。
///
/// 失败分类依据实际接口契约：
/// - HTTP 200 + 业务 code!=200：服务端用它表达请求级拒绝，其中参数校验/
///   超限属确定性错误（抛 [SyncPushDeterministicException]），未登录/
///   无权限/系统异常仍保留标记待重试；
/// - HTTP 4xx（400/413/422）确定性；401/403/5xx/超时/断网暂时性，
///   原样上抛由调度器按家庭收敛。
class ApiSyncPushPort implements SyncPushPort {
  @override
  Future<Set<String>> push(
    String familyId,
    List<Map<String, dynamic>> records,
  ) async {
    try {
      final data = await ApiClient().post<Map<String, dynamic>>(
        '/v1/sync/push',
        data: <String, dynamic>{
          'familyId': familyId,
          'records': records,
        },
      );
      return collectDoneIds(data, records);
    } on ApiException catch (e) {
      if (isDeterministic(e)) {
        throw SyncPushDeterministicException(e.message);
      }
      rethrow;
    }
  }

  /// 契约里与「请求内容」无关、重放有救的业务错误文案：登录态、权限、
  /// 服务端内部异常（GlobalExceptionHandler 同样返回 HTTP 200 + code=500，
  /// 无法仅凭 code 与参数校验区分）。
  static const List<String> _transientBusinessMessages = <String>[
    '未登录',
    '登录',
    '权限',
    '系统异常',
    '请求失败',
  ];

  /// 是否为确定性错误：重放同一批不会成功，需要拆半/隔离。
  @visibleForTesting
  static bool isDeterministic(ApiException e) {
    final status = e.statusCode;
    if (status == 400 || status == 413 || status == 422) return true;
    if (status == 401 ||
        status == 403 ||
        status == 408 ||
        status == 429 ||
        (status != null && status >= 500)) {
      return false;
    }
    final code = e.code;
    if (code == null) return false; // 传输层失败/无业务码：暂时性
    if (code == 400 || code == 413 || code == 422) return true;
    if (code == 401 || code == 403) return false;
    // HTTP 200 + 业务 code：登录态/权限/系统异常可重试，其余按请求级
    // 校验拒绝处理（如「单次推送最多500条记录」「记录ID长度不能超过36」）
    for (final text in _transientBusinessMessages) {
      if (e.message.contains(text)) return false;
    }
    return true;
  }

  /// 从推送响应里提取「使命完成」的记录 ID。
  ///
  /// 正常契约：results 逐条返回 accepted=true/false（rejected 也带 id）。
  /// 兜底：若服务端只回 accepted 行，用 total/accepted/rejected 计数把
  /// 未回执的 rejected 行也视为完成，避免被永久重发；计数不闭合时
  /// 不臆测，只清已明确回执的行（剩余标记保留待下轮）。
  @visibleForTesting
  static Set<String> collectDoneIds(
    Map<String, dynamic> data,
    List<Map<String, dynamic>> records,
  ) {
    final done = <String>{};
    for (final item in (data['results'] as List? ?? const [])) {
      if (item is Map<String, dynamic>) {
        final id = item['id'];
        if (id is String) done.add(id);
      }
    }
    final total = data['total'];
    final accepted = data['accepted'];
    final rejected = data['rejected'];
    if (total is int &&
        accepted is int &&
        rejected is int &&
        total == records.length &&
        accepted + rejected == total &&
        rejected > 0 &&
        done.length == accepted) {
      for (final record in records) {
        final id = record['id'];
        if (id is String) done.add(id);
      }
    }
    return done;
  }
}

/// 同步阶段（P1-6 进度呈现）
enum SyncPhase {
  /// 正在上传（存量重推 / 首轮全量上云）：可算总量，进度条确定态
  pushing,

  /// 正在拉取恢复：协议不返回云端总量，进度条不确定态
  restoring,
}

/// 同步进度快照。仅在「用户可感知的批量搬运」时产生：
/// 日常小增量全程静默（不产生任何快照）。
class SyncProgress {
  const SyncProgress({
    required this.phase,
    required this.processed,
    this.total,
  });

  final SyncPhase phase;

  /// 已完成条数（推送为已上传条数，拉取为已恢复条数）
  final int processed;

  /// 总量（仅推送可算；拉取协议无总量，为 null）
  final int? total;

  /// 是否首轮全量恢复（下拉方向）
  bool get isFullRestore => phase == SyncPhase.restoring;
}

/// 同步调度器（tasks.md 7.3/7.4）：推-拉-对账循环。
///
/// 流程：门控 → 推送发件箱 → 拉取云端增量入库 → 补推
/// （拉取仲裁跳过的本地高版本记录，一轮收敛双向一致）。
///
/// 触发方式为写路径 fire-and-forget（不阻塞本地操作）：
/// - 单飞：运行中再触发仅记重跑标记，结束后补跑一轮（天然防抖合并）
/// - 门控：备份开关开 → 已登录 → 密钥已解锁（任一不满足静默跳过，
///   标记与游标保留；解锁/登录后的下一次触发自动补推）
/// - 失败重试不丢：暂时性失败（网络/5xx/超时）保留标记与游标，
///   靠下次触发重推/重拉（LWW 幂等，重拉无害）；推送失败不阻断拉取
/// - 确定性拒绝（参数超限/字段校验）：批内拆半定位到单条后隔离，
///   队列继续前进，不因单条坏数据永久卡在队头
/// - 分批：每家庭每批 ≤ [batchSize]（默认 400，与服务端 500 上限留余量）；
///   跨家庭记录不能同批（服务端按家庭校验归属），单家庭失败互不影响
class SyncScheduler {
  SyncScheduler({
    AppDatabase? db,
    SyncPushPort? port,
    SyncPullPort? pullPort,
    KeyVault? vault,
    Future<bool> Function()? isSignedIn,
    Future<String?> Function()? currentFamilyId,
    SyncPuller? puller,
    Future<List<({String id, int role})>> Function()? membersProvider,
    Future<void> Function()? publicKeyReporter,
    this.batchSize = 400,
  })  : _injectedDb = db,
        _injectedPuller = puller,
        _pullPort = pullPort,
        _port = port ?? ApiSyncPushPort(),
        _vault = vault ?? VaultProvider.vault,
        _isSignedIn = isSignedIn ?? _defaultSignedIn,
        _currentFamilyId = currentFamilyId ?? CurrentFamilyStore.get,
        _membersProvider = membersProvider,
        _publicKeyReporter = publicKeyReporter ??
            (() => VaultSyncService.reportPublicKey(vault: vault));

  static Future<bool> _defaultSignedIn() async =>
      await ApiClient().getToken() != null;

  static SyncScheduler? _instance;

  /// 应用级单例：门面写路径统一经此触发
  static SyncScheduler get instance => _instance ??= SyncScheduler();

  final AppDatabase? _injectedDb;
  final SyncPuller? _injectedPuller;
  final SyncPullPort? _pullPort;
  final SyncPushPort _port;
  final KeyVault _vault;
  final Future<bool> Function() _isSignedIn;
  final Future<String?> Function() _currentFamilyId;
  final Future<List<({String id, int role})>> Function()? _membersProvider;

  /// 公钥上报端口：默认走 ApiClient；测试注入空实现避免真实网络
  final Future<void> Function() _publicKeyReporter;
  final int batchSize;

  /// 当前库：注入（测试）优先；默认随 Db 单例动态取——Db.close()
  /// 重开新库后（登出/账号切换）自动指向新库，防止持有已关闭
  /// 旧库的引用导致同步静默失效。
  AppDatabase get _db => _injectedDb ?? Db.database;

  /// 拉取器：注入（测试）优先；否则每轮基于当前库新建（薄对象，
  /// 天然跟随 _db 动态指向，不缓存旧库引用）。
  SyncPuller get _puller => _injectedPuller ??
      SyncPuller(
        db: _db,
        port: _pullPort,
        currentFamilyId: _currentFamilyId,
        vault: _vault,
      );

  bool _running = false;
  bool _rerun = false;

  /// 批量进度（P1-6）：null 表示无可见任务。只在首轮全量恢复与
  /// 存量重推（待推条数 ≥ [kSyncProgressMinRows]）时非空，日常增量
  /// 保持 null（UI 全程静默）。
  final ValueNotifier<SyncProgress?> _progress =
      ValueNotifier<SyncProgress?>(null);

  SyncProgress? get currentProgress => _progress.value;
  ValueListenable<SyncProgress?> get progress => _progress;

  /// 「同步执行中」信号：备份页据此在同步期间禁用「重置密钥 /
  /// 关闭备份」（其他交互一律不禁）。
  final ValueNotifier<bool> _syncing = ValueNotifier<bool>(false);

  bool get isSyncing => _syncing.value;
  ValueListenable<bool> get syncing => _syncing;

  /// 「等待家庭密钥分发」信号：本机无 F 且本轮确有家庭密文解不开
  /// （新成员刚入伙、持钥方还没把包裹推上来）。为 true 时调度器会
  /// 按退避自动重试，拿到 F 后会清游标全量重拉补齐，无需用户操作。
  final ValueNotifier<bool> _waitingFamilyKey = ValueNotifier<bool>(false);

  bool get isWaitingForFamilyKey => _waitingFamilyKey.value;
  ValueListenable<bool> get waitingForFamilyKey => _waitingFamilyKey;

  /// 等待密钥的自动重试定时器（同一时刻最多一个）与退避档位
  Timer? _waitRetryTimer;
  int _waitRetryStep = 0;
  static const Duration _waitRetryBase = Duration(seconds: 30);
  static const int _waitRetryMaxStep = 3;

  /// 同步轮完成广播：门控通过且整轮成功（含拉取入库）后触发一次；
  /// 门控跳过/失败不触发。页面 Provider 是拉取一次模式（非响应式
  /// watch 本地库），恢复/增量同步落库后须靠此事件主动重拉——
  /// 典型场景：重装恢复时用户停在首页，数据逐页入库但首页无感，
  /// 恢复完成后停留页仍是空的，需切页面才显示。
  final StreamController<void> _roundCompletedController =
      StreamController<void>.broadcast();

  /// 订阅同步完成（广播流，多页面可同时订阅）
  Stream<void> get onRoundCompleted => _roundCompletedController.stream;

  /// 推送进度呈现门限：待推条数达到一个推送批次（500）才视为
  /// 「存量重推 / 首轮上云」并显示进度；日常小增量静默。
  static const int kSyncProgressMinRows = 500;

  /// 尽力而为同步：调用方一律 fire-and-forget（unawaited），
  /// 任何异常不出函数边界（后台任务的既定语义，真机日志可查
  /// debugPrint 输出）。
  Future<void> maybePush() async {
    // 单飞：运行中再触发仅记重跑标记
    if (_running) {
      _rerun = true;
      return;
    }
    _running = true;
    try {
      await _syncOnce();
      // 运行期间再次触发：合并补跑一轮（不递归，避免深层嵌套）
      while (_rerun) {
        _rerun = false;
        await _syncOnce();
      }
    } catch (e) {
      debugPrint('[SyncScheduler] 同步中断，标记与游标保留待重试: $e');
    } finally {
      // 进度与「同步中」状态必须在 finally 复位：账号切换、断网、
      // 密钥锁定等任何中断都不能在 UI 留下永挂的进度条
      _running = false;
      _progress.value = null;
      _syncing.value = false;
    }
  }

  Future<void> _syncOnce() async {
    final gate = await _gate();
    if (gate == null) {
      debugPrint('[SyncScheduler] 门控未通过，本轮跳过');
      return;
    }
    _syncing.value = true;
    debugPrint('[SyncScheduler] 门控通过，开始同步');
    final familyId = await _currentFamilyId();
    // vault 托管补位（6.7）：每轮幂等推送最新 vault 到当前家庭通道，
    // 云端 upsert 覆盖——改口令/重置后下轮同步自动更新云端副本；
    // 新开启用户首轮同步即补上云端 vault。内部自吞异常，失败下轮重试
    await VaultSyncService.pushVault();
    // 公钥随成员关系下发：每轮幂等上报本机公钥（失败静默，下轮重报）。
    // 入伙后首轮上报即把公钥写进新建的成员行，持钥方下一轮拉成员
    // 列表就能包裹 F——不再依赖 vaultDoc 的增量可达性。
    await _publicKeyReporter();

    // 三期 8.4：家庭密钥 F 保障。先做自身包裹探测（缺陷修复）：
    // fkey 记录为 epoch 时间戳，在已推进的游标之前——增量拉取永远
    // 够不到，后开启成员首拉错过包裹会导致 F 永久失联。无 F 时用
    // recordId 精确拉取（不走游标），命中即解 F 落库（普通成员后
    // 开启、admin 换设备恢复同一把 F，避免误生成裂脑）。
    // 探测先于分发：恢复到的 F 直接进入下方分发/重密封链路
    final gainedFamilyKey = await FamilyKeyService.ensureOwnFamilyKey(
      vault: _vault,
      pullPort: _pullPort,
      currentFamilyId: _currentFamilyId,
    );

    // admin 首次生成 / 云端缺份的成员补包裹分发。成员列表拉取失败
    // 静默跳过（下轮重试），不阻断同步
    final members = await _loadMembers();
    // 新成员公钥保障：其 vaultDoc 固定 epoch 时间戳，落在已推进的
    // 游标之前，增量拉取永远够不到——不靠 recordId 精确探测补公钥，
    // admin 就永远发不出其 F 包裹（新成员空库的直接原因）
    await VaultSyncService.ensureMemberPublicKeys(
      members: members,
      port: _pullPort,
      currentFamilyId: _currentFamilyId,
    );
    await FamilyKeyService.ensureDistributed(
      members: members,
      vault: _vault,
      pushPort: _port,
      pullPort: _pullPort,
      currentFamilyId: _currentFamilyId,
    );

    // F 分发可能本轮新生成（admin 路径），重新读取
    final familyKey =
        familyId == null ? null : await _vault.familyDataKey(familyId);

    // 存量重密封（8.4）：首次拿到 F 时把该家庭已上云密文从个人 key
    // 迁移到家庭 key——version 不变、updated_at 刷新、syncPending 重标，
    // 下方推送环节用家庭 key 全量重推（LWW 同 version 时间新者胜覆盖）
    if (familyId != null && familyKey != null) {
      // 升级一次性迁移：清全部家庭游标做一轮全量重拉（见方法注释）
      await _maybeFullRespullOnUpgrade();
      await _maybeReseal(familyId);
      // 首获 F（探测送达）：重置拉取游标——此前无 F 时历史密文被
      // 跳过且游标推进，须全量重拉以家庭 key 解开入库（LWW 幂等）
      if (gainedFamilyKey) {
        final user = await LocalUser.load();
        await SyncCursorStore.clear(familyId, user?.id ?? '');
      }
    }

    // 三段各自兜住异常：推送失败不连坐拉取，拉取失败也不阻断对账补推。
    // 暂时性推送失败由 _pushAll 在家庭级收敛并保留标记；这里只兜
    // 发件箱读取等意外异常，避免整轮直接终止。
    var pushOk = true;
    try {
      pushOk = await _pushAll();
    } catch (e) {
      pushOk = false;
      debugPrint('[SyncScheduler] 推送阶段异常，继续拉取: $e');
    }

    Object? pullError;
    ({int pulled, int applied, int skipped, int unreadable, bool needsFullRespull})?
        pullOutcome;
    try {
      pullOutcome = await _puller.pullAll(
        gate.personal,
        // 惰性家庭密钥源：fkey 记录可能在本轮拉取中途送达 F（后加入
        // 成员首拉），解出后同页后续业务记录立即可解
        familyDataKeyProvider: familyId == null
            ? null
            : () async => await _vault.familyDataKey(familyId),
        // 每页进度（P1-6）：仅首轮全量恢复对外呈现；日常增量拉取
        // （有游标）不上报，保持全程静默
        onPage: (processed, isFullRestore) {
          if (isFullRestore) {
            _progress.value = SyncProgress(
              phase: SyncPhase.restoring,
              processed: processed,
            );
          }
        },
      );
    } catch (e) {
      pullError = e;
      debugPrint('[SyncScheduler] 拉取阶段异常，继续对账补推: $e');
    }

    // 拉取结束即撤下恢复进度（对账补推若量大再按推送阶段呈现）
    if (_progress.value?.phase == SyncPhase.restoring) {
      _progress.value = null;
    }

    // 等待家庭密钥分发（新成员刚入伙）：本机无 F，本轮确有家庭密文
    // 解不开。不静默空库——置等待态并按退避自动重试；持钥方把包裹
    // 推上来后，下一轮 ensureOwnFamilyKey 命中即清游标全量补齐，
    // 全程无需用户操作。
    if (pullError == null && pullOutcome != null) {
      final waiting = pullOutcome.unreadable > 0;
      _waitingFamilyKey.value = waiting;
      if (waiting) {
        _scheduleWaitRetry(
          pullOutcome.unreadable,
          urgent: pullOutcome.needsFullRespull,
        );
      } else {
        _cancelWaitRetry();
      }
    }
    // 对账补推：拉取仲裁跳过的本地高版本记录（或推送环节部分
    // 失败遗留）推上去，一轮收敛；已推净则空转返回
    try {
      if (!await _pushAll()) pushOk = false;
    } catch (e) {
      pushOk = false;
      debugPrint('[SyncScheduler] 对账补推异常: $e');
    }

    // 拉取失败本轮未完成：游标保留，上抛给 maybePush 记录并按需重试
    if (pullError != null) throw pullError;

    if (pushOk) {
      debugPrint('[SyncScheduler] 一轮同步完成');
      // 通知停留页面重拉数据（拉取模式 Provider 不感知本地库变更）
      _roundCompletedController.add(null);
    } else {
      debugPrint('[SyncScheduler] 一轮同步完成（部分推送失败，标记保留待重试）');
    }
  }

  /// 等待家庭密钥的退避重试：30s → 60s → 120s → 240s 封顶，同一时刻
  /// 只排一个定时器。拿到 F（waiting=false）立即撤销并复位退避。
  /// [urgent] 表示本轮中途才拿到 F 且已清游标——下一轮需尽快全量补齐。
  void _scheduleWaitRetry(int pendingRows, {bool urgent = false}) {
    if (_waitRetryTimer != null) return;
    final delay = urgent
        ? const Duration(seconds: 10)
        : Duration(seconds: _waitRetryBase.inSeconds * (1 << _waitRetryStep));
    debugPrint('[SyncScheduler] 等待家庭密钥分发：$pendingRows 条家庭密文待 F，'
        '${delay.inSeconds}s 后自动重试');
    _waitRetryTimer = Timer(delay, () {
      _waitRetryTimer = null;
      if (!_waitingFamilyKey.value) return;
      if (!urgent && _waitRetryStep < _waitRetryMaxStep) _waitRetryStep++;
      unawaited(maybePush());
    });
  }

  /// 撤销等待重试并复位退避档位（拿到 F / 本轮无不可解密文）
  void _cancelWaitRetry() {
    _waitRetryTimer?.cancel();
    _waitRetryTimer = null;
    _waitRetryStep = 0;
  }

  /// 把成员列表下发的公钥登记进本地缓存（公钥随成员关系下发）。
  ///
  /// 服务端 family_member.public_key 由各成员客户端在同步轮次里上报，
  /// 因此在审批通过后的第一轮同步就会写进新建的成员行——不再需要
  /// 「持钥方某次全量重拉恰好扫到对方 vaultDoc」。老服务端/老客户端
  /// 未上报时为 null，跳过并由 vaultDoc 精确探测兜底。
  @visibleForTesting
  static Future<void> registerMemberPublicKeys(List<dynamic> members) async {
    for (final m in members) {
      if (m is! Map) continue;
      final id = m['id'];
      final publicKey = m['publicKey'];
      if (id is String &&
          id.isNotEmpty &&
          publicKey is String &&
          publicKey.isNotEmpty) {
        await MemberPublicKeyStore.register(id, publicKey);
      }
    }
  }

  /// 当前家庭成员（分发 F 的检测范围）。注入（测试）优先；
  /// 网络失败返回空列表（本轮跳过分发，成员数据同步不受影响）。
  /// 注意：该接口 data 为顶层数组（同 FamilyService.getMembers），
  /// 不能用 get<Map> 泛型——cast 失败会导致 F 分发每轮静默跳过。
  Future<List<({String id, int role})>> _loadMembers() async {
    if (_membersProvider != null) return await _membersProvider!();
    try {
      final result = await ApiClient().get<dynamic>('/v1/families/members');
      final list = result as List? ?? const [];
      // 公钥随成员关系下发（服务端 family_member.public_key）：持有 F
      // 的成员拉一次成员列表即可包裹分发，不再依赖对方 vaultDoc 的
      // 增量可达性。老服务端/老客户端未上报时为 null，回落探测兜底
      await registerMemberPublicKeys(list);
      return list
          .map((m) => (id: (m as Map)['id'] as String, role: m['role'] as int))
          .toList();
    } catch (e) {
      debugPrint('[SyncScheduler] 成员列表拉取失败，本轮跳过 F 分发: $e');
      return const [];
    }
  }

  /// 首次拿到 F 的家庭做一次存量重密封标记（per 家庭 per 账号 per F）：
  /// 该家庭全部业务行 syncPending 重标 + updated_at 刷新，
  /// 让推送环节以家庭 key 重加密重推（云端旧个人密文被覆盖，
  /// 其他成员从「不可读跳过」变为可解——家庭数据共享的存量闭环）。
  /// 学习表（用户级、走当前家庭通道）全表重标。version 不动，
  /// 多设备侧按同 version 时间新者胜收敛，无翻案冲突。
  ///
  /// 账本键含 F 指纹（前 4 字节 hex）：F 轮换（互救重置/换设备重生成）
  /// 后键名变化，新 F 自动视为「未重推」而重新全量重推——云端密文
  /// 需要用新 F 重新覆盖。旧版无指纹键自然作废：升级用户全部重推
  /// 一次（修复「账本在数据到达前置位」的时序缺陷，重推幂等无害）。
  Future<void> _maybeReseal(String familyId) async {
    final f = await _vault.getFamilyKey(familyId);
    if (f == null) return;
    final fingerprint = f
        .sublist(0, 4)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final user = await LocalUser.load();
    final key =
        'xiji_reseal_done@$familyId@${user?.id ?? ''}@$fingerprint';
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(key) == true) return;

    final now = DateTime.now();
    await (_db.update(_db.transactions)
          ..where((t) => t.familyId.equals(familyId)))
        .write(TransactionsCompanion(
            syncPending: const Value(true), updatedAt: Value(now)));
    await (_db.update(_db.categories)
          ..where((c) => c.familyId.equals(familyId)))
        .write(CategoriesCompanion(
            syncPending: const Value(true), updatedAt: Value(now)));
    await (_db.update(_db.budgets)..where((b) => b.familyId.equals(familyId)))
        .write(BudgetsCompanion(
            syncPending: const Value(true), updatedAt: Value(now)));
    await (_db.update(_db.categoryRules))
        .write(CategoryRulesCompanion(
            syncPending: const Value(true), updatedAt: Value(now)));

    await prefs.setBool(key, true);
    debugPrint('[SyncScheduler] 存量重密封完成：$familyId 全量重标待推');
  }

  /// 升级一次性迁移（v1）：清全部家庭拉取游标，触发一轮全量重拉。
  ///
  /// 修复场景：修复前版本的设备曾以个人 key 回落解密拉回存量
  /// （pending=0 落库、游标推进），升级后云端密文仍是个人 key 版，
  /// 增量拉取永远不会再路过这些记录——其他成员拿 F 解不开（空库）。
  /// 清游标后全量重拉：旧个人密文重新路过时回落解密并标 pending
  /// 重推（家庭 key 覆盖云端），云端密文版本自愈。
  ///
  /// 一次性开关（prefs 布尔标记）：新装用户首轮本来就无游标（全量），
  /// 此迁移对它是无操作；LWW 幂等保证重拉无害。
  static const _fullRespullMigrationKey = 'xiji_full_respull_v1';
  Future<void> _maybeFullRespullOnUpgrade() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_fullRespullMigrationKey) == true) return;
    final cursorKeys = prefs
        .getKeys()
        .where((k) =>
            k.startsWith('sync_cursor_time_') || k.startsWith('sync_cursor_id_'))
        .toList();
    for (final k in cursorKeys) {
      await prefs.remove(k);
    }
    await prefs.setBool(_fullRespullMigrationKey, true);
    debugPrint('[SyncScheduler] 升级迁移：已清 ${cursorKeys.length ~/ 2} 个'
        '家庭游标，本轮全量重拉');
  }

  /// 门控：备份开关 → 登录态 → 密钥解锁 → 派生双数据密钥。
  /// 任一不满足返回 null（静默跳过，标记与游标保留）。
  /// 备份开关真值源 = vault.enabled（6.8：账号级，随 vault 云端漫游）。
  /// 返回个人密钥（回落解密/无 F 家庭兜底）与当前家庭密钥（8.4；
  /// 未获 F 为 null——业务推送跳过、拉取保留）。
  Future<({Uint8List personal, Uint8List? family})?> _gate() async {
    if (!await _vault.isBackupEnabled()) {
      debugPrint('[SyncScheduler] 门控跳过：备份开关未开');
      return null;
    }
    if (!await _isSignedIn()) {
      debugPrint('[SyncScheduler] 门控跳过：未登录');
      return null;
    }
    final keyPair = _vault.unlockedKeyPair;
    if (keyPair == null) {
      debugPrint('[SyncScheduler] 门控跳过：密钥未解锁');
      return null;
    }
    final privateKey = Uint8List.fromList(await keyPair.extractPrivateKeyBytes());
    final personal = CryptoPrimitives.hkdfSha256(privateKey,
        info: CryptoPrimitives.kSyncDataKeyInfo);
    final familyId = await _currentFamilyId();
    final family = familyId == null ? null : await _vault.familyDataKey(familyId);
    return (personal: personal, family: family);
  }

  /// 确定性失败记录隔离账本键前缀：值记录 version + updatedAt 指纹，
  /// 记录被本地编辑（版本或时间变化）后指纹失配，自动重新尝试。
  static const String _isolateKeyPrefix = 'xiji_sync_isolated_v1';

  static String _isolateKey(SyncPendingRow row) =>
      '$_isolateKeyPrefix@${row.recordType}@${row.id}';

  static String _isolateFingerprint(SyncPendingRow row) =>
      '${row.version}@${row.updatedAt.millisecondsSinceEpoch}';

  static bool _isIsolated(SharedPreferences prefs, SyncPendingRow row) =>
      prefs.getString(_isolateKey(row)) == _isolateFingerprint(row);

  /// 单条记录被服务端确定性拒绝：转入本地隔离账本（不删除本地数据、
  /// 不动 syncPending），本版本不再重试，队列继续前进。
  /// 选择隔离而非保留待推：确定性错误每轮原样重放只会反复拆批浪费
  /// RTT；隔离后用户编辑该记录（version/updatedAt 变化）即自动解除。
  Future<void> _isolate(SyncPendingRow row, String reason) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_isolateKey(row), _isolateFingerprint(row));
    debugPrint('[SyncScheduler] 单条记录被确定性拒绝，已隔离（本地保留，'
        '编辑后自动重试）：${row.recordType}/${row.id}，原因：$reason');
  }

  /// 推送全部待推行；返回 false 表示存在暂时性失败（标记保留待下轮）。
  /// 确定性拒绝在批内拆半定位到单条后隔离，不视为整轮失败。
  Future<bool> _pushAll() async {
    final prefs = await SharedPreferences.getInstance();
    final rows = (await SyncOutbox.collectAll(_db, await _currentFamilyId()))
        .where((row) => !_isIsolated(prefs, row))
        .toList(growable: false);
    if (rows.isEmpty) {
      debugPrint('[SyncScheduler] 发件箱为空，无需推送');
      return true;
    }

    // 按家庭分组推送（服务端按家庭整批校验，跨家庭不能同批）
    final byFamily = <String, List<SyncPendingRow>>{};
    for (final row in rows) {
      byFamily.putIfAbsent(row.familyId, () => <SyncPendingRow>[]).add(row);
    }

    // 8.4：行级加密键选择——该家庭有 F 用家庭密钥（家庭数据共享），
    // 无 F（未获分发的家庭）跳过推送，标记保留待拿到 F 后重推。
    // 预取各家庭密钥：无 F 家庭整组跳过，不计入进度总量（否则进度
    // 永远到不了 100% 才消失）。
    final familyKeys = <String, Uint8List>{};
    for (final entry in byFamily.entries) {
      final key = await _vault.familyDataKey(entry.key);
      if (key == null) {
        debugPrint('[SyncScheduler] 家庭 ${entry.key} 未获 F，'
            '业务推送跳过（标记保留）');
        continue;
      }
      familyKeys[entry.key] = key;
    }

    // 存量重推 / 首轮上云的进度呈现（P1-6）：待推量达到一个批次才
    // 显示；日常小增量保持静默
    final totalToPush = byFamily.entries
        .where((e) => familyKeys.containsKey(e.key))
        .fold<int>(0, (sum, e) => sum + e.value.length);
    final showProgress = totalToPush >= kSyncProgressMinRows;
    var processed = 0;
    var pushOk = true;
    if (showProgress) {
      _progress.value = SyncProgress(
        phase: SyncPhase.pushing,
        processed: 0,
        total: totalToPush,
      );
    }

    try {
      for (final entry in byFamily.entries) {
        final familyDataKey = familyKeys[entry.key];
        if (familyDataKey == null) continue;
        var start = 0;
        try {
          while (start < entry.value.length) {
            final batch = entry.value
                .skip(start)
                .take(batchSize)
                .toList(growable: false);
            debugPrint('[SyncScheduler] 推送家庭 ${entry.key} '
                '批次 ${start ~/ batchSize + 1}：${batch.length} 条');
            await _pushBatchIsolated(entry.key, familyDataKey, batch);
            start += batch.length;
            processed += batch.length;
            if (showProgress) {
              _progress.value = SyncProgress(
                phase: SyncPhase.pushing,
                processed: processed,
                total: totalToPush,
              );
            }
          }
        } catch (e) {
          // 家庭隔离：单家庭暂时性失败不中止其他家庭与本轮流程，
          // 该家庭剩余批次标记保留，下一轮继续
          pushOk = false;
          debugPrint('[SyncScheduler] 家庭 ${entry.key} 推送中断，'
              '标记保留待重试: $e');
        }
      }
    } finally {
      if (showProgress) {
        _progress.value = null;
      }
    }
    return pushOk;
  }

  /// 推送一批并清理成功行；确定性拒绝时拆半重试到单条，单条仍失败
  /// 则隔离，让队列继续前进。暂时性异常原样上抛，由家庭级边界收敛。
  Future<void> _pushBatchIsolated(
    String familyId,
    Uint8List familyDataKey,
    List<SyncPendingRow> batch,
  ) async {
    try {
      // 批量加密下放 isolate（P1-5）：整批纯 CPU 计算在后台隔离线程
      // 完成，主隔离只等结果。
      final records = await SyncOutbox.encryptBatch(familyDataKey, batch);
      final done = await _port.push(familyId, records);
      debugPrint('[SyncScheduler] 家庭 $familyId 回执：'
          '${done.length}/${batch.length} 条完成');
      final cleared = batch.where((row) => done.contains(row.id)).toList();
      if (cleared.isNotEmpty) {
        await SyncOutbox.clearPending(_db, cleared);
      }
    } on SyncPushDeterministicException catch (e) {
      if (batch.length <= 1) {
        await _isolate(batch.single, e.message);
        return;
      }
      // 拆半：确定性拒绝通常只由个别坏记录触发，二分定位到单条后
      // 其余记录照常推净
      final mid = batch.length ~/ 2;
      await _pushBatchIsolated(
          familyId, familyDataKey, batch.sublist(0, mid));
      await _pushBatchIsolated(familyId, familyDataKey, batch.sublist(mid));
    }
  }
}
