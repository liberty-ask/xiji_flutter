import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/home_provider.dart';
import '../../providers/auth_provider.dart';
import '../../crypto/key_vault.dart' show KeyVaultUnlockException;
import '../../crypto/vault_provider.dart';
import '../../widgets/common/bottom_nav_bar.dart';
import '../../widgets/common/scaled_text.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_widget.dart' as custom;
import '../../widgets/common/custom_snackbar.dart';
import '../../widgets/common/budget_progress_bar.dart';
import '../../utils/theme_helper.dart';
import '../../utils/transaction_type_style.dart';
import '../../utils/error_helper.dart';
import '../../utils/icon_constants.dart';
import '../../utils/amount_format.dart';
import '../../services/api/family_service.dart';
import '../../data/local/current_family_store.dart';
import '../../data/local/family_member_cache.dart';
import '../../data/local/local_family_cache.dart';
import '../../data/local/pending_family_switch_store.dart';
import '../../models/family.dart';
import '../../models/family_member.dart';
import '../../sync/sync_scheduler.dart';
import '../../sync/vault_sync_service.dart';
import '../../sync/vault_prompt_coordinator.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/category_l10n.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  final FamilyService _familyService = FamilyService();
  List<Family> _families = [];
  Family? _currentFamily;
  List<FamilyMember> _members = [];
  // 家庭切换期间的加载态：切换后立即隐藏旧家庭的成员/预算数据
  bool _familySwitching = false;
  // 切换请求序号：快速连续切换时只让最新一次结果落地
  int _familySwitchSeq = 0;
  // 服务端「切换当前家庭」串行队列：保证连续切换按点击顺序补发，
  // 失败只记待补发，不影响本地已生效的切换
  Future<void> _serverSwitchQueue = Future<void>.value();
  // 上次见到的登录用户：检测「登出再登录」后账号变化重拉首页数据
  String? _lastUserId;
  // 重装恢复口令框：幂等协调器（会话内只弹一次；探测失败可重试，
  // 不依赖页面重建）
  late final VaultPromptCoordinator _vaultPrompt = VaultPromptCoordinator(
    probe: _probeVault,
    prompt: _showRestoreUnlockDialog,
  );
  // 同步轮完成订阅：恢复/增量同步落库后停留页主动重拉
  StreamSubscription<void>? _syncRoundSub;
  // 手动刷新转圈：stale-while-revalidate 下静默刷新无任何视觉
  // 反馈，用户显式点击须有反馈（自动刷新保持静默不闪屏）
  bool _manualRefreshing = false;
  // 同步进度（P1-6）：批量恢复/重推时展示细进度条；日常增量不产生
  // 进度事件，UI 保持静默
  DateTime _lastProgressRefresh = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _progressRefreshTimer;

  @override
  void initState() {
    super.initState();
    _lastUserId = context.read<AuthProvider>().user?.id;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
    // 恢复完成时用户通常停在首页盯着看：拉取模式 Provider 不感知
    // 本地库逐页入库，须靠同步完成事件刷新停留页（否则恢复完
    // 数据仍空，要切页面才显示）
    _syncRoundSub = SyncScheduler.instance.onRoundCompleted.listen((_) {
      if (mounted) {
        // 联网恢复/同步轮完成后补发离线切换的家庭
        _flushPendingFamilySwitch();
        // 冷启动探测失败（网络/上下文未就绪）时，联网后补弹口令框
        unawaited(_ensureVaultPrompt());
        context.read<HomeProvider>().fetchHomeData();
      }
    });
    SyncScheduler.instance.progress.addListener(_onSyncProgress);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 回前台补一次探测：冷启动首探失败后不依赖用户切页面
    if (state == AppLifecycleState.resumed) {
      unawaited(_ensureVaultPrompt());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncRoundSub?.cancel();
    _progressRefreshTimer?.cancel();
    SyncScheduler.instance.progress.removeListener(_onSyncProgress);
    super.dispose();
  }

  /// 同步进度变化：重绘进度条 / 骨架屏，并在恢复期按页节流刷新首页。
  /// 节流规则：每页最多触发一次、两次刷新间隔不少于 500ms；间隔不足
  /// 时用定时器补最后一次，避免最后一页被吞掉导致收尾不刷新。
  void _onSyncProgress() {
    if (!mounted) return;
    setState(() {});
    final progress = SyncScheduler.instance.currentProgress;
    if (progress == null || progress.phase != SyncPhase.restoring) return;
    // processed == 0 只是「恢复开始」标记（用于切骨架屏），无新数据可刷
    if (progress.processed <= 0) return;
    const interval = Duration(milliseconds: 500);
    final elapsed = DateTime.now().difference(_lastProgressRefresh);
    if (elapsed >= interval) {
      _refreshFromProgress();
    } else {
      _progressRefreshTimer?.cancel();
      _progressRefreshTimer = Timer(interval - elapsed, () {
        if (mounted) _refreshFromProgress();
      });
    }
  }

  void _refreshFromProgress() {
    _lastProgressRefresh = DateTime.now();
    context.read<HomeProvider>().fetchHomeData();
  }

  /// 恢复中且本地无数据：骨架屏 + 顶部细进度条。与「无数据且无任务」
  /// （错误/空态）区分，让用户明确知道数据正在路上。
  /// 保留底部导航：恢复期间照常可切 tab / 记账，不做任何阻断。
  Widget _buildRestoringSkeleton(SyncProgress progress) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _SyncProgressBar(progress: progress),
            const Expanded(child: _HomeSkeleton()),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
      ),
    );
  }

  /// 后台追平服务端当前家庭：串行执行避免乱序；失败只记待补发，
  /// 不回滚本地状态、不弹错（离线优先）。
  void _enqueueServerSwitch(String familyId) {
    _serverSwitchQueue = _serverSwitchQueue.then((_) async {
      try {
        await _familyService.switchFamily(familyId);
        await PendingFamilySwitchStore.clear();
      } catch (_) {
        await PendingFamilySwitchStore.save(familyId);
      }
    });
  }

  /// 补发上次离线切换（启动/手动刷新/下一轮同步时调用），失败静默保留
  void _flushPendingFamilySwitch() {
    _serverSwitchQueue = _serverSwitchQueue.then((_) async {
      final pending = await PendingFamilySwitchStore.load();
      if (pending == null) return;
      try {
        await _familyService.switchFamily(pending);
        await PendingFamilySwitchStore.clear();
      } catch (_) {
        // 仍未联网，保留待补发，下次再试
      }
    });
  }

  Future<void> _refreshUserQuietly(AuthProvider authProvider) async {
    try {
      await authProvider.refreshUser();
    } catch (_) {
      // 离线/失败不影响切换结果，资料缓存保留上次内容
    }
  }

  /// 首页数据引导：先回填当前家庭再拉数据。
  /// fetchHomeData 按家庭 ID 过滤查询，登出会清空 CurrentFamilyStore，
  /// ID 未回填时 SQL family_id = null 必然空集——登录后首页空、
  /// 切页返回才恢复的根因。_loadFamilies 缓存分支毫秒级回填，
  /// 网络分支失败也不影响（catch 内，store 已有缓存值）。
  Future<void> _bootstrap() async {
    await _loadFamilies();
    if (!mounted) return;
    // 启动即补发上次离线切换（失败静默保留待补发）
    _flushPendingFamilySwitch();
    // 家庭上下文就绪后、首页数据加载前判定口令框：重装 + 云端有 vault
    // 时首屏即弹，不依赖用户切页面
    await _ensureVaultPrompt();
    if (!mounted) return;
    await context.read<HomeProvider>().fetchHomeData();
    _loadMembers();
    // 冷启动主动触发一轮同步（密钥锁定时调度器自行跳过）
    unawaited(SyncScheduler.instance.maybePush());
  }
  
  /// 本地成员缓存先行：切换家庭/进入首页时立即用缓存还原 N，
  /// 随后网络结果覆盖；缓存缺失则保持隐藏（不报错）
  Future<void> _applyCachedMembers(String familyId, int? seq) async {
    if (familyId.isEmpty) return;
    final cached = await FamilyMemberCache.load(familyId);
    if (cached == null || cached.isEmpty || !mounted) return;
    if (seq != null && seq != _familySwitchSeq) return;
    if (familyId != _currentFamily?.id) return;
    setState(() {
      _members = cached;
    });
  }

  /// [expectedFamilyId]/[seq]：家庭切换场景传入，晚到的旧请求不落地
  Future<void> _loadMembers({String? expectedFamilyId, int? seq}) async {
    final familyId = expectedFamilyId ?? _currentFamily?.id;
    if (familyId != null) {
      await _applyCachedMembers(familyId, seq);
    }
    try {
      final members = await _familyService.getMembers();
      if (!mounted) return;
      if (seq != null && seq != _familySwitchSeq) return;
      if (expectedFamilyId != null && expectedFamilyId != _currentFamily?.id) {
        return;
      }
      setState(() {
        _members = members;
      });
    } catch (e) {
      // 加载成员失败不影响主功能（服务层已尝试回退本地缓存）
    }
  }

  /// 探测 vault 状态：本机未配置时从云端拉取 vault 导入（免口令），
  /// 再尝试自动解锁（不卸载场景免口令）。
  ///
  /// 判定只看两点：设置过口令（vault 已配置）+ 本机锁定（重装/换设备/
  /// 首启无自动解锁份）→ 需要口令；不依赖备份开关状态（开关真值恢复
  /// 本身依赖解锁，判它必死锁）。家庭上下文未就绪/网络失败会向上抛，
  /// 由协调器重试，而不是被误判成「云端无 vault」。
  Future<({bool configured, bool unlocked})> _probeVault() async {
    await VaultSyncService.restoreFromCloud(throwOnError: true);
    final vault = VaultProvider.vault;
    return (
      configured: await vault.isConfigured(),
      unlocked: vault.isUnlocked,
    );
  }

  /// 幂等确保重装口令框弹出：启动、同步轮完成、回前台都会调用，
  /// 会话内只弹一次（取消/输错关闭后不再打扰）
  Future<void> _ensureVaultPrompt() async {
    if (!mounted) return;
    await _vaultPrompt.ensurePrompt();
  }

  /// 云备份重装恢复口令框：输对口令解锁并触发全量恢复（自动解锁份
  /// 随即重建，之后启动恢复无感）；输错留在框内重试；取消则下次
  /// 启动再提示。
  Future<void> _showRestoreUnlockDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    var obscure = true;
    String? error;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(l10n.backupRestoreUnlockTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.backupRestoreUnlockDesc,
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller,
                obscureText: obscure,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.backupPasswordLabel,
                  errorText: error,
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () =>
                        setDialogState(() => obscure = !obscure),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await VaultProvider.vault.unlock(controller.text);
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                  if (mounted) {
                    CustomSnackBar.showSuccess(
                        context, l10n.backupRestoreStarted);
                  }
                  // 解锁完成即触发一轮同步：重装场景首轮全量拉取恢复
                  unawaited(SyncScheduler.instance.maybePush());
                } on KeyVaultUnlockException {
                  setDialogState(() {
                    error = l10n.backupRestoreWrongPassword;
                    controller.clear();
                  });
                } catch (_) {
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                  if (mounted) {
                    CustomSnackBar.showError(
                        context, l10n.backupVaultUnlockFailed);
                  }
                }
              },
              child: Text(l10n.confirm),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  Future<void> _loadFamilies() async {
    final authProvider = context.read<AuthProvider>();
    // 期间发生过家庭切换（本地已立即生效）时，本次结果整体作废，
    // 避免晚到的旧家庭列表/缓存覆盖刚切好的新家庭
    final startSwitchSeq = _familySwitchSeq;
    bool staledBySwitch() => startSwitchSeq != _familySwitchSeq;

    // 先用本地缓存渲染（离线优先，无网络也显示上次家庭信息）
    final cached = await LocalFamilyCache.load();
    if (staledBySwitch()) return;
    if (cached != null && cached.isNotEmpty && mounted) {
      final current = cached.firstWhere(
        (f) => f.isCurrent,
        orElse: () => cached.first,
      );
      // 同步当前家庭到路由源（本地库家庭维度的写入依据）
      await CurrentFamilyStore.set(current.id);
      // 角色随家庭变化：切家庭后立即纠正鉴权快照（加入审核等入口依赖它）
      await authProvider.updateCurrentFamilyRole(current.role);
      if (staledBySwitch()) return;
      setState(() {
        _families = cached;
        _currentFamily = current;
      });
    }
    try {
      final families = await _familyService.getFamiliesList();
      if (staledBySwitch()) return;
      await LocalFamilyCache.cache(families);
      if (staledBySwitch()) return;
      if (families.isNotEmpty) {
        final currentFamily = families.firstWhere(
          (f) => f.isCurrent,
          orElse: () => families.first,
        );
        await CurrentFamilyStore.set(currentFamily.id);
        // 角色随家庭变化：以服务端家庭列表的角色为准，非管理员不再
        // 沿用「个人家庭管理员」的旧快照
        await authProvider.updateCurrentFamilyRole(currentFamily.role);
        if (staledBySwitch()) return;
      }
      setState(() {
        _families = families;
        if (families.isNotEmpty) {
          _currentFamily = families.firstWhere(
            (f) => f.isCurrent,
            orElse: () => families.first,
          );
        }
      });
    } catch (e) {
      // 网络失败保持缓存数据，不影响首页显示
    }
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });

    switch (index) {
      case 0:
        context.go('/home');
        break;
      case 1:
        context.go('/calendar');
        break;
      case 2:
        context.push('/add-transaction');
        break;
      case 3:
        context.go('/statistics');
        break;
      case 4:
        context.go('/profile');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听登录用户变化：HomeScreen 未销毁时（同路径 go 不重建等场景）
    // 检测账号变化走统一引导——与 initState 相同的「先家庭后数据」
    // 顺序，防止 fetch 先于家庭回填跑空查询
    final currentUser = context.watch<AuthProvider>().user;
    if (currentUser?.id != _lastUserId) {
      _lastUserId = currentUser?.id;
      if (currentUser != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          await _bootstrap();
        });
      }
    }
    return Scaffold(
      body: Consumer<HomeProvider>(
        builder: (context, provider, _) {
          // 闪屏修复：仅「加载中且无旧数据」才显示 loading（首启场景）；
          // 静默刷新期间继续渲染旧数据。错误页仅在无数据可兜底时出现。
          // P1-6：恢复中且本地无数据 → 骨架屏（区别于「无数据且无任务」）
          if (provider.homeData == null) {
            final progress = SyncScheduler.instance.currentProgress;
            if (progress != null && progress.phase == SyncPhase.restoring) {
              return _buildRestoringSkeleton(progress);
            }
            if (provider.isLoading) {
              return LoadingIndicator(
                  message: AppLocalizations.of(context)!.loading);
            }
            return custom.CustomErrorWidget(
              message: provider.error ?? AppLocalizations.of(context)!.noData,
              onRetry: () => provider.fetchHomeData(),
            );
          }

          final syncProgress = SyncScheduler.instance.currentProgress;

          final data = provider.homeData!;
          final balanceNum = (data['balance'] as num?)?.toDouble() ?? 0.0;
          final todayExpenseNum = (data['todayExpense'] as num?)?.toDouble() ?? 0.0;
          final yesterdayExpenseNum = (data['yesterdayExpense'] as num?)?.toDouble() ?? 0.0;
          final balance = _formatAmount(balanceNum);
          final income = _formatAmount((data['income'] as num?)?.toDouble() ?? 0.0);
          final expense = _formatAmount((data['expense'] as num?)?.toDouble() ?? 0.0);
          final budget = data['budget'] as Map<String, dynamic>? ?? {};
          // 家庭切换中，或当前数据仍属于旧家庭：预算区块按加载态处理，
          // 不闪一下旧家庭的数字
          final currentFamilyId = _currentFamily?.id;
          final providerFamilyId = provider.dataFamilyId;
          final budgetSwitching = _familySwitching ||
              (currentFamilyId != null &&
                  providerFamilyId != null &&
                  providerFamilyId != currentFamilyId);
          final todayExpense = _formatAmount(todayExpenseNum);
          final activities = data['activities'] as List<dynamic>? ?? [];
          final currency = AppLocalizations.of(context)!.currencySymbol;

          // 计算今日支出趋势
          final expenseDiff = todayExpenseNum - yesterdayExpenseNum;

          final balanceParts = balance.split('.');
          final balanceInt = balanceParts[0];
          final balanceDec = balanceParts.length > 1 ? balanceParts[1] : '00';

          return Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: ThemeHelper.surface(context).withValues(alpha: 0.9),
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withValues(alpha: 0.05),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        _families.length > 1
                            ? PopupMenuButton<Family>(
                                offset: const Offset(0, 50),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: ThemeHelper.surfaceLight(context),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                                        child: _currentFamily?.avatar != null && _currentFamily!.avatar!.isNotEmpty
                                            ? CachedNetworkImage(
                                                imageUrl: _currentFamily!.avatar!,
                              fit: BoxFit.cover,
                                                errorWidget: (context, url, error) {
                                                  return _buildFamilyAvatarPlaceholder();
                                                },
                                              )
                                            : _buildFamilyAvatarPlaceholder(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ScaledText(
                                          _currentFamily?.name ?? AppLocalizations.of(context)!.loading,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            ScaledText(
                                              '${_families.length} ${AppLocalizations.of(context)!.family}',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.white.withAlpha(128),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Icon(
                                              Icons.keyboard_arrow_down,
                                              size: 14,
                                              color: Colors.white.withAlpha(128),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                itemBuilder: (context) => _families.map((family) {
                                  return PopupMenuItem<Family>(
                                    value: family,
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(8),
                                            color: ThemeHelper.primary(context).withValues(alpha: 0.2),
                                          ),
                                          child: family.avatar != null && family.avatar!.isNotEmpty
                                              ? ClipRRect(
                                                  borderRadius: BorderRadius.circular(8),
                                                  child: CachedNetworkImage(
                                                    imageUrl: family.avatar!,
                                                    fit: BoxFit.cover,
                                                    errorWidget: (context, url, error) {
                                                      return Center(
                                                        child: Text(
                                                          family.name.isNotEmpty ? family.name[0].toUpperCase() : 'H',
                                                          style: TextStyle(
                                                            fontSize: 14,
                                                            fontWeight: FontWeight.bold,
                                                            color: ThemeHelper.primary(context),
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                )
                                              : Center(
                                                  child: Text(
                                                    family.name.isNotEmpty ? family.name[0].toUpperCase() : 'H',
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.bold,
                                                      color: ThemeHelper.primary(context),
                                                    ),
                                                  ),
                                                ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                family.name,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                  color: family.isCurrent
                                                      ? ThemeHelper.primary(context)
                                                      : Colors.white,
                                                ),
                                              ),
                                              if (FamilyRole.isAdmin(family.role))
                                                ScaledText(
                                                  AppLocalizations.of(context)!.admin,
                                                    style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.white.withValues(alpha: 0.6),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        if (family.isCurrent)
                                          Icon(
                                            Icons.check,
                                            size: 18,
                                color: ThemeHelper.primary(context),
                                          ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onSelected: (selectedFamily) async {
                                  // 同步段先取引用，避免 async gap 后使用 context
                                  final authProvider = context.read<AuthProvider>();
                                  if (selectedFamily.id == _currentFamily?.id) return;

                                  // 切换一开始就进入加载态并清空旧成员，避免
                                  // 「成员数是旧家庭、预算也是旧家庭」的过渡态
                                  final switchSeq = ++_familySwitchSeq;
                                  setState(() {
                                    _familySwitching = true;
                                    _members = const [];
                                  });
                                  try {
                                    // 离线优先：本地立即生效，不等待服务端
                                    await CurrentFamilyStore.set(selectedFamily.id);
                                    await LocalFamilyCache.setCurrent(selectedFamily.id);
                                    // 角色随家庭走：立即纠正鉴权快照，避免
                                    // 用旧家庭的 admin 身份看到「加入审核」
                                    await authProvider.updateCurrentFamilyRole(selectedFamily.role);
                                    if (!mounted || switchSeq != _familySwitchSeq) return;
                                    setState(() {
                                      _currentFamily = selectedFamily;
                                      _families = [
                                        for (final f in _families)
                                          Family(
                                            id: f.id,
                                            name: f.name,
                                            isCurrent: f.id == selectedFamily.id,
                                            role: f.role,
                                            avatar: f.avatar,
                                          ),
                                      ];
                                    });
                                    // 本地库数据刷新（预算进度/收支，不触网）
                                    await context.read<HomeProvider>().fetchHomeData();
                                    // 本地成员缓存先行，N 在结束加载态前就位
                                    await _applyCachedMembers(selectedFamily.id, switchSeq);
                                  } catch (e) {
                                    // 本地写入失败才会走到这里（罕见），提示后结束
                                    if (mounted) {
                                      final errorMessage = ErrorHelper.extractErrorMessage(e, defaultMessage: AppLocalizations.of(context)!.changeFailed);
                                      CustomSnackBar.showError(context, errorMessage);
                                    }
                                  } finally {
                                    if (mounted && switchSeq == _familySwitchSeq) {
                                      setState(() => _familySwitching = false);
                                    }
                                  }
                                  if (!mounted || switchSeq != _familySwitchSeq) return;
                                  // 后台补齐（不阻塞加载态，失败静默）：
                                  // 成员数 N、用户角色、服务端当前家庭
                                  unawaited(_loadMembers(
                                    expectedFamilyId: selectedFamily.id,
                                    seq: switchSeq,
                                  ));
                                  unawaited(_refreshUserQuietly(authProvider));
                                  _enqueueServerSwitch(selectedFamily.id);
                                },
                              )
                            : Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      color: ThemeHelper.surfaceLight(context),
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.1),
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: _currentFamily?.avatar != null && _currentFamily!.avatar!.isNotEmpty
                                          ? CachedNetworkImage(
                                              imageUrl: _currentFamily!.avatar!,
                                              fit: BoxFit.cover,
                                              errorWidget: (context, url, error) {
                                                return _buildFamilyAvatarPlaceholder();
                                              },
                                            )
                                          : _buildFamilyAvatarPlaceholder(),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  ScaledText(
                                    _currentFamily?.name ?? AppLocalizations.of(context)!.loading,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        IconButton(
                          icon: _manualRefreshing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white),
                                )
                              : const Icon(Icons.sync,
                                  color: Colors.white54),
                          onPressed: _manualRefreshing ? null : () async {
                            setState(() => _manualRefreshing = true);
                            try {
                              await provider.fetchHomeData();
                              await _loadFamilies();
                              _flushPendingFamilySwitch();
                            } finally {
                              if (mounted) {
                                setState(() => _manualRefreshing = false);
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ),

                  // 同步进度（P1-6）：首轮恢复 / 存量重推时页头下方细线，
                  // 日常增量不出现；不遮罩、不影响记账与切 tab
                  if (syncProgress != null)
                    _SyncProgressBar(progress: syncProgress),

                  // Content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Balance Card
                          Container(
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(40),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  ThemeHelper.surfaceHighlight(context),
                                  ThemeHelper.background(context),
                                ],
                              ),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    ScaledText(
                                      AppLocalizations.of(context)!.availableBalance,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white38,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      Icons.visibility,
                                      size: 14,
                                      color: Colors.white.withValues(alpha: 0.2),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    ScaledText(
                                      currency,
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: ThemeHelper.primary(context),
                                      ),
                                    ),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.baseline,
                                        textBaseline: TextBaseline.alphabetic,
                                        children: [
                                          ScaledText(
                                            balanceInt,
                                            style: const TextStyle(
                                              fontSize: 48,
                                              fontWeight: FontWeight.w900,
                                              color: Colors.white,
                                              letterSpacing: -2,
                                            ),
                                          ),
                                          ScaledText(
                                            '.$balanceDec',
                                            style: TextStyle(
                                              fontSize: 24,
                                              fontWeight: FontWeight.w900,
                                              color: Colors.white.withValues(alpha: 0.2),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 32),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(16),
                                          color: Colors.white.withValues(alpha: 0.05),
                                          border: Border.all(
                                            color: Colors.white.withValues(alpha: 0.05),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            ScaledText(
                                              AppLocalizations.of(context)!.monthlyIncome,
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white38,
                                                letterSpacing: 1,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: Alignment.centerLeft,
                                              child: ScaledText(
                                                '$currency$income',
                                                style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(16),
                                          color: Colors.white.withValues(alpha: 0.05),
                                          border: Border.all(
                                            color: Colors.white.withValues(alpha: 0.05),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            ScaledText(
                                              AppLocalizations.of(context)!.monthlyExpense,
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white38,
                                                letterSpacing: 1,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: Alignment.centerLeft,
                                              child: ScaledText(
                                                '$currency$expense',
                                                style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Quick Actions
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () => context.push('/voice-transaction'),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(20),
                                      color: ThemeHelper.primary(context).withValues(alpha: 0.2),
                                      border: Border.all(
                                        color: ThemeHelper.primary(context).withValues(alpha: 0.5),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.mic,
                                          color: ThemeHelper.primary(context),
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: ScaledText(
                                            AppLocalizations.of(context)!.voiceTransaction,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: InkWell(
                                  onTap: () => context.push('/add-transaction'),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(20),
                                      color: Colors.white.withValues(alpha: 0.05),
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.1),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.edit,
                                          color: Colors.white70,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: ScaledText(
                                            AppLocalizations.of(context)!.manualTransaction,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white70,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Stats
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(32),
                                    color: ThemeHelper.surface(context),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.05),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      ScaledText(
                                        AppLocalizations.of(context)!.budgetProgress,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white38,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      if (budgetSwitching)
                                        const SizedBox(
                                          height: 74,
                                          child: Center(
                                            child: SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white24,
                                              ),
                                            ),
                                          ),
                                        )
                                      else ...[
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: Alignment.centerLeft,
                                              child: ScaledText(
                                                '$currency${AmountFormat.format(budget['used'] as num?)}',
                                                style: const TextStyle(
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                                maxLines: 1,
                                              ),
                                            ),
                                            ScaledText(
                                              ' / ${AmountFormat.format((budget['budget'] ?? budget['total']) as num?)}',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.white.withValues(alpha: 0.2),
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        BudgetProgressBar(
                                          used: budget['used'] as num?,
                                          total: budget['total'] as num?,
                                        ),
                                        // 8.5：预算口径标注——预算与支出同为
                                        // 「已设预算成员」口径，X/N 提示覆盖范围；
                                        // N<=1（单人家庭）或 X=0（无人设预算）
                                        // 时整行不显示
                                        Builder(builder: (context) {
                                          final memberCount =
                                              (budget['memberCount'] as num?)?.toInt() ?? 0;
                                          final syncingCount = _members
                                              .where((m) => m.isSyncing)
                                              .length;
                                          if (memberCount <= 0 || syncingCount <= 1) {
                                            return const SizedBox.shrink();
                                          }
                                          return Padding(
                                            padding: const EdgeInsets.only(top: 8),
                                            child: ScaledText(
                                              AppLocalizations.of(context)!
                                                  .budgetMemberNote(memberCount, syncingCount),
                                              style: TextStyle(
                                                fontSize: 9,
                                                color: Colors.white.withValues(alpha: 0.4),
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          );
                                        }),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(32),
                                    color: ThemeHelper.surface(context),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.05),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      ScaledText(
                                        AppLocalizations.of(context)!.todayExpense,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white38,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      ScaledText(
                                        '$currency$todayExpense',
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Icon(
                                            expenseDiff >= 0
                                                ? Icons.trending_up
                                                : Icons.trending_down,
                                            size: 14,
                                            color: expenseDiff >= 0
                                                ? ThemeHelper.expenseColor(context)
                                                : ThemeHelper.primary(context),
                                          ),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: Alignment.centerLeft,
                                              child: ScaledText(
                                                expenseDiff >= 0
                                                    ? '+$currency${AmountFormat.format(expenseDiff)}'
                                                    : '$currency${AmountFormat.format(expenseDiff)}',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: expenseDiff >= 0
                                                      ? ThemeHelper.expenseColor(context)
                                                      : ThemeHelper.primary(context),
                                                ),
                                                maxLines: 1,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 32),

                          // Recent Activities
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              ScaledText(
                                AppLocalizations.of(context)!.recentActivities,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              TextButton(
                                onPressed: () => context.push('/detail'),
                                child: ScaledText(
                                  AppLocalizations.of(context)!.all,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: ThemeHelper.primary(context),
                                    letterSpacing: 2,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // Activities List
                          ...activities.map((item) {
                            final isIncome = item['isIncome'] as bool? ?? false;
                            return InkWell(
                              onTap: () => _showTransactionDetail(item),
                              borderRadius: BorderRadius.circular(24),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24),
                                  color: ThemeHelper.surface(context),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.05),
                                  ),
                                ),
                                child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      color: Colors.white.withValues(alpha: 0.05),
                                    ),
                                    child: Icon(
                                      IconConstants.getIconFromString(item['icon'] as String? ?? ''),
                                      color: isIncome
                                          ? ThemeHelper.primary(context)
                                          : Colors.white38,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        ScaledText(
                                          CategoryL10n.display(
                                            AppLocalizations.of(context)!,
                                            nameKey:
                                                item['nameKey'] as String?,
                                            fallbackName: item['title']
                                                    as String? ??
                                                (isIncome
                                                    ? AppLocalizations.of(
                                                            context)!
                                                        .income
                                                    : AppLocalizations.of(
                                                            context)!
                                                        .expense),
                                          ),
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        ScaledText(
                                          '${item['user'] ?? ''} · ${item['time'] ?? ''}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.white.withValues(alpha: 0.2),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  ScaledText(
                                    '${isIncome ? '+' : '-'}${_formatAmount((item['amount'] as num?)?.toDouble() ?? 0.0)}',
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: isIncome
                                          ? ThemeHelper.primary(context)
                                          : Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                          }).toList(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: BottomNavBar(
              currentIndex: _currentIndex,
              onTap: _onTabTapped,
            ),
          );
        },
      ),
    );
  }

  // 格式化金额：千分位 + 两位小数（复用全局 AmountFormat）
  String _formatAmount(num value) {
    return AmountFormat.format(value);
  }

  Widget _buildFamilyAvatarPlaceholder() {
    final name = _currentFamily?.name ?? '';
    final firstChar = name.isNotEmpty ? name[0].toUpperCase() : 'H';
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: ThemeHelper.primary(context).withValues(alpha: 0.2),
      ),
      child: Center(
        child: Text(
          firstChar,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: ThemeHelper.primary(context),
          ),
        ),
      ),
    );
  }

  /// 显示交易详情（与交易明细列表保持一致）
  void _showTransactionDetail(Map<String, dynamic> item) {
    final isIncome = item['isIncome'] as bool? ?? false;
    
    // 查找用户信息
    String userName = item['user'] as String? ?? AppLocalizations.of(context)!.unknown;

    // 解析金额（后端返回数值，正负号由isIncome决定）
    final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;

    // 解析日期
    DateTime transactionDate = DateTime.now();
    // 优先使用date字段（完整日期）
    final dateStr = item['date'] as String?;
    if (dateStr != null && dateStr.isNotEmpty) {
      try {
        transactionDate = DateTime.parse(dateStr);
      } catch (e) {
        // 解析失败，尝试其他格式
        try {
          // 尝试解析 "yyyy-MM-dd" 格式
          final parts = dateStr.split('-');
          if (parts.length == 3) {
            transactionDate = DateTime(
              int.parse(parts[0]),
              int.parse(parts[1]),
              int.parse(parts[2]),
            );
          }
        } catch (e2) {
          // 解析失败，使用当前日期
          transactionDate = DateTime.now();
        }
      }
    } else {
      // 如果没有date字段，尝试从time字段解析
      final timeStr = item['time'] as String?;
      if (timeStr != null && timeStr.isNotEmpty) {
        try {
          // 尝试解析日期，格式可能是 "2026-01-15" 或 "01-15"
          if (timeStr.contains('-')) {
            final parts = timeStr.split('-');
            if (parts.length == 3) {
              transactionDate = DateTime.parse(timeStr);
            } else if (parts.length == 2) {
              // 只有月-日，使用当前年份
              final now = DateTime.now();
              transactionDate = DateTime(now.year, int.parse(parts[0]), int.parse(parts[1]));
            }
          }
        } catch (e) {
          // 解析失败，使用当前日期
          transactionDate = DateTime.now();
        }
      }
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ThemeHelper.surface(context),
        title: Row(
          children: [
            Icon(
              TransactionTypeStyle.icon(isIncome),
              color: TransactionTypeStyle.color(context, isIncome),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ScaledText(
                AppLocalizations.of(context)!.transactionDetail,
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow(
                AppLocalizations.of(context)!.type,
                TransactionTypeStyle.label(AppLocalizations.of(context)!, isIncome),
                color: TransactionTypeStyle.color(context, isIncome)
              ),
              _buildDetailRow(
                AppLocalizations.of(context)!.category,
                CategoryL10n.display(
                  AppLocalizations.of(context)!,
                  nameKey: item['nameKey'] as String?,
                  fallbackName: item['title'] as String? ??
                      (isIncome
                          ? AppLocalizations.of(context)!.income
                          : AppLocalizations.of(context)!.expense),
                ),
              ),
              _buildDetailRow(
                AppLocalizations.of(context)!.amount,
                '${AppLocalizations.of(context)!.currencySymbol}${AmountFormat.format(amount)}',
                color: isIncome ? ThemeHelper.primary(context) : Colors.white,
                autoFit: true
              ),
              _buildDetailRow(
                AppLocalizations.of(context)!.date,
                DateFormat.yMMMMd(Localizations.localeOf(context).toString()).format(transactionDate)
              ),
              _buildDetailRow(
                AppLocalizations.of(context)!.user,
                userName
              ),
              if (item['counterparty'] != null && (item['counterparty'] as String).isNotEmpty)
                _buildDetailRow(
                  AppLocalizations.of(context)!.counterparty,
                  item['counterparty'] as String
                ),
              if (item['description'] != null && (item['description'] as String).isNotEmpty)
                _buildDetailRow(
                  AppLocalizations.of(context)!.note,
                  item['description'] as String
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: ScaledText(
              AppLocalizations.of(context)!.close,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDetailRow(String label, String value, {Color? color, bool autoFit = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScaledText(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 4),
          if (autoFit)
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: ScaledText(
                value,
                style: TextStyle(
                  fontSize: 16,
                  color: color ?? Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
              ),
            )
          else
            ScaledText(
              value,
              style: TextStyle(
                fontSize: 16,
                color: color ?? Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

}

/// 同步进度条（P1-6）：页头下方 2px 细线 + 一行小字。
/// 不弹模态、不加遮罩、不禁用任何交互。
class _SyncProgressBar extends StatelessWidget {
  const _SyncProgressBar({required this.progress});

  final SyncProgress progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final total = progress.total;
    final double? value = total != null && total > 0
        ? (progress.processed / total).clamp(0.0, 1.0)
        : null;
    final label = progress.phase == SyncPhase.restoring
        ? l10n.syncRestoringData(progress.processed)
        : l10n.syncUploadingHistory(progress.processed, total ?? 0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LinearProgressIndicator(
          value: value,
          minHeight: 2,
          backgroundColor: Colors.white.withValues(alpha: 0.06),
          color: ThemeHelper.primary(context),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: ScaledText(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
    );
  }
}

/// 首页骨架屏：仅「正在恢复且本地尚无数据」时替代空白/错误页，
/// 用脉冲占位块表示数据正在路上。
class _HomeSkeleton extends StatefulWidget {
  const _HomeSkeleton();

  @override
  State<_HomeSkeleton> createState() => _HomeSkeletonState();
}

class _HomeSkeletonState extends State<_HomeSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _block(double height, {double radius = 12}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _block(150, radius: 40),
            const SizedBox(height: 24),
            _block(20),
            const SizedBox(height: 12),
            _block(16),
            const SizedBox(height: 24),
            _block(72),
            const SizedBox(height: 12),
            _block(72),
            const SizedBox(height: 12),
            _block(72),
          ],
        ),
      ),
    );
  }
}
