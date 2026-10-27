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
import '../../utils/theme_helper.dart';
import '../../utils/error_helper.dart';
import '../../utils/icon_constants.dart';
import '../../services/api/family_service.dart';
import '../../data/local/current_family_store.dart';
import '../../data/local/local_family_cache.dart';
import '../../models/family.dart';
import '../../models/family_member.dart';
import '../../sync/sync_scheduler.dart';
import '../../sync/vault_sync_service.dart';
import '../../l10n/app_localizations.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final FamilyService _familyService = FamilyService();
  List<Family> _families = [];
  Family? _currentFamily;
  List<FamilyMember> _members = [];
  // 上次见到的登录用户：检测「登出再登录」后账号变化重拉首页数据
  String? _lastUserId;
  // 重装恢复口令框会话内只弹一次（取消/输错关闭后不再打扰，
  // 下次启动再提示）
  bool _restorePromptShown = false;
  // 同步轮完成订阅：恢复/增量同步落库后停留页主动重拉
  StreamSubscription<void>? _syncRoundSub;
  // 手动刷新转圈：stale-while-revalidate 下静默刷新无任何视觉
  // 反馈，用户显式点击须有反馈（自动刷新保持静默不闪屏）
  bool _manualRefreshing = false;

  @override
  void initState() {
    super.initState();
    _lastUserId = context.read<AuthProvider>().user?.id;
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
    // 恢复完成时用户通常停在首页盯着看：拉取模式 Provider 不感知
    // 本地库逐页入库，须靠同步完成事件刷新停留页（否则恢复完
    // 数据仍空，要切页面才显示）
    _syncRoundSub = SyncScheduler.instance.onRoundCompleted.listen((_) {
      if (mounted) {
        context.read<HomeProvider>().fetchHomeData();
      }
    });
  }

  @override
  void dispose() {
    _syncRoundSub?.cancel();
    super.dispose();
  }

  /// 首页数据引导：先回填当前家庭再拉数据。
  /// fetchHomeData 按家庭 ID 过滤查询，登出会清空 CurrentFamilyStore，
  /// ID 未回填时 SQL family_id = null 必然空集——登录后首页空、
  /// 切页返回才恢复的根因。_loadFamilies 缓存分支毫秒级回填，
  /// 网络分支失败也不影响（catch 内，store 已有缓存值）。
  Future<void> _bootstrap() async {
    await _loadFamilies();
    if (!mounted) return;
    await context.read<HomeProvider>().fetchHomeData();
    _loadMembers();
  }
  
  Future<void> _loadMembers() async {
    try {
      final members = await _familyService.getMembers();
      if (mounted) {
        setState(() {
          _members = members;
        });
      }
    } catch (e) {
      // 加载成员失败不影响主功能
    }
  }

  /// 家庭上下文就绪后的 vault 探测恢复（6.8/6.9）：本机未配置时从云端
  /// 拉取 vault 导入（免口令，开关状态随 vault 恢复——重装/换设备
  /// 后开关不再显示关闭）；已配置时探测内部直接跳过（幂等）。探测/
  /// 导入后自动尝试自动解锁（6.9 自动解锁份：不卸载免口令）。
  ///
  /// 云备份已开但密钥仍锁定（自动解锁份缺失：重装/换设备/老版本升级
  /// 首启）时主动弹口令框完成恢复——不能等用户逛到备份页才发现记录
  /// 没上云；输对口令即解锁并触发全量拉取恢复。会话内只弹一次。
  Future<void> _restoreVaultThenSync() async {
    try {
      await VaultSyncService.restoreFromCloud();
      final vault = VaultProvider.vault;
      if (await vault.isBackupEnabled() &&
          !vault.isUnlocked &&
          !_restorePromptShown &&
          mounted) {
        _restorePromptShown = true;
        await _showRestoreUnlockDialog();
        return;
      }
      await SyncScheduler.instance.maybePush();
    } catch (_) {
      // 探测失败静默：下次家庭上下文就绪再试
    }
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
    // 先用本地缓存渲染（离线优先，无网络也显示上次家庭信息）
    final cached = await LocalFamilyCache.load();
    if (cached != null && cached.isNotEmpty && mounted) {
      final current = cached.firstWhere(
        (f) => f.isCurrent,
        orElse: () => cached.first,
      );
      // 同步当前家庭到路由源（本地库家庭维度的写入依据）
      await CurrentFamilyStore.set(current.id);
      // 家庭上下文就绪：云端探测 vault 恢复（6.8——重装/换设备后
      // 登录瞬间 CurrentFamilyStore 尚空，探测需等家庭就绪；免口令，
      // 开关状态随 vault 恢复），恢复成功且已开启则触发一轮同步
      unawaited(_restoreVaultThenSync());
      setState(() {
        _families = cached;
        _currentFamily = current;
      });
    }
    try {
      final families = await _familyService.getFamiliesList();
      await LocalFamilyCache.cache(families);
      if (families.isNotEmpty) {
        await CurrentFamilyStore.set(
          families.firstWhere(
            (f) => f.isCurrent,
            orElse: () => families.first,
          ).id,
        );
        // 同步当前家庭到路由源（本地库家庭维度的写入依据）
        unawaited(_restoreVaultThenSync());
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
          // 静默刷新期间继续渲染旧数据。错误页仅在无数据可兜底时出现
          if (provider.isLoading && provider.homeData == null) {
            return LoadingIndicator(message: AppLocalizations.of(context)!.loading);
          }

          if (provider.homeData == null) {
            return custom.CustomErrorWidget(
              message: provider.error ?? AppLocalizations.of(context)!.noData,
              onRetry: () => provider.fetchHomeData(),
            );
          }

          final data = provider.homeData!;
          final balanceNum = (data['balance'] as num?)?.toDouble() ?? 0.0;
          final todayExpenseNum = (data['todayExpense'] as num?)?.toDouble() ?? 0.0;
          final yesterdayExpenseNum = (data['yesterdayExpense'] as num?)?.toDouble() ?? 0.0;
          final balance = _formatAmount(balanceNum);
          final income = _formatAmount((data['income'] as num?)?.toDouble() ?? 0.0);
          final expense = _formatAmount((data['expense'] as num?)?.toDouble() ?? 0.0);
          final budget = data['budget'] as Map<String, dynamic>? ?? {};
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
                                  if (selectedFamily.id != _currentFamily?.id) {
                                    try {
                                      // 调用切换家庭接口
                                      await _familyService.switchFamily(selectedFamily.id);
                                      // 刷新家庭列表以获取最新的isCurrent状态
                                      await _loadFamilies();
                                      // 按当前家庭刷新用户资料缓存（role 随新家庭归位，
                                      // "我的"页入口与 /audit 守卫随 notifyListeners 重绘）；
                                      // 失败不阻断切换，资料缓存保留上次内容
                                      try {
                                        await authProvider.refreshUser();
                                      } catch (_) {}
                                      // 刷新首页数据
                                      if (mounted) {
                                        context.read<HomeProvider>().fetchHomeData();
                                      }
                                    } catch (e) {
                                      // 切换失败，显示错误提示
                                      if (mounted) {
                                        final errorMessage = ErrorHelper.extractErrorMessage(e, defaultMessage: AppLocalizations.of(context)!.changeFailed);
                                        CustomSnackBar.showError(context, errorMessage);
                                      }
                                    }
                                  }
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
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          ScaledText(
                                            '$currency${budget['used'] ?? 0}',
                                            style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          ScaledText(
                                            ' / ${budget['budget'] ?? budget['total'] ?? 0}',
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
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: LinearProgressIndicator(
                                          value: _calculateBudgetProgress(budget),
                                          backgroundColor: Colors.white.withValues(alpha: 0.05),
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                            _getBudgetProgressColor(budget),
                                          ),
                                          minHeight: 6,
                                        ),
                                      ),
                                      // 8.5：预算口径标注——预算与支出同为
                                      // 「已设预算成员」口径，X/N 提示覆盖范围；
                                      // 单人家庭（N<=1）不显示避免噪音
                                      Builder(builder: (context) {
                                        final memberCount =
                                            (budget['memberCount'] as num?)?.toInt() ?? 0;
                                        final syncingCount = _members
                                            .where((m) => m.isSyncing)
                                            .length;
                                        if (syncingCount <= 1) return const SizedBox.shrink();
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
                                          ScaledText(
                                            expenseDiff >= 0
                                                ? '+$currency${expenseDiff.toStringAsFixed(2)}'
                                                : '$currency${expenseDiff.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: expenseDiff >= 0
                                                  ? ThemeHelper.expenseColor(context)
                                                  : ThemeHelper.primary(context),
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
                                          item['title'] as String? ?? '',
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

  // Calculate budget progress
  double _calculateBudgetProgress(Map<String, dynamic> budget) {
    final used = (budget['used'] as num? ?? 0).toDouble();
    final total = (budget['total'] as num? ?? 1).toDouble();
    if (total == 0) return 0.0;
    return (used / total).clamp(0.0, 1.0);
  }

  // Get budget progress color based on percentage
  Color _getBudgetProgressColor(Map<String, dynamic> budget) {
    double percentage = 0.0;

    final used = (budget['used'] as num? ?? 0).toDouble();
    final total = (budget['total'] as num? ?? 0).toDouble();
    if (total > 0) {
      percentage = (used / total) * 100;
    }

    // Return color based on percentage
    if (percentage > 100) {
      return ThemeHelper.expenseColor(context); // Red for over budget
    } else if (percentage > 80) {
      return Colors.orange; // Orange/Yellow for warning (80-100%)
    } else {
      return ThemeHelper.primary(context); // Primary color for normal (0-80%)
    }
  }

  // 格式化金额：千分位 + 两位小数（后端返回数值，格式化由客户端负责）
  String _formatAmount(num value) {
    return NumberFormat('#,##0.00').format(value);
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
              isIncome ? Icons.arrow_upward : Icons.arrow_downward,
              color: isIncome ? ThemeHelper.primary(context) : ThemeHelper.expenseColor(context),
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
                isIncome ? AppLocalizations.of(context)!.income : AppLocalizations.of(context)!.expense,
                color: isIncome ? ThemeHelper.primary(context) : ThemeHelper.expenseColor(context)
              ),
              _buildDetailRow(
                AppLocalizations.of(context)!.category,
                item['title'] as String? ?? ''
              ),
              _buildDetailRow(
                AppLocalizations.of(context)!.amount,
                '${AppLocalizations.of(context)!.currencySymbol}${amount.toStringAsFixed(2)}',
                color: isIncome ? ThemeHelper.primary(context) : Colors.white
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
  
  Widget _buildDetailRow(String label, String value, {Color? color}) {
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
