import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/home_provider.dart';
import '../../widgets/common/bottom_nav_bar.dart';
import '../../widgets/common/font_size_inherited.dart';
import '../../widgets/common/scaled_text.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_widget.dart' as custom;
import '../../widgets/common/custom_snackbar.dart';
import '../../utils/theme_helper.dart';
import '../../utils/error_helper.dart';
import '../../services/api/family_service.dart';
import '../../models/family.dart';
import '../../models/family_member.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeProvider>().fetchHomeData();
      _loadFamilies();
      _loadMembers();
    });
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

  Future<void> _loadFamilies() async {
    try {
      final families = await _familyService.getFamiliesList();
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
      // 静默失败，不影响首页显示
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
    // 获取字号缩放因子
    final fontSizeScale = FontSizeInherited.of(context).fontSizeScale;
    
    return Scaffold(
      body: Consumer<HomeProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return LoadingIndicator(message: AppLocalizations.of(context)!.loading);
          }

          if (provider.error != null || provider.homeData == null) {
            return custom.CustomErrorWidget(
              message: provider.error ?? AppLocalizations.of(context)!.noData,
              onRetry: () => provider.fetchHomeData(),
            );
          }

          final data = provider.homeData!;
          final balance = data['balance'] as String? ?? '0.00';
          final income = data['income'] as String? ?? '0';
          final expense = data['expense'] as String? ?? '0';
          final budget = data['budget'] as Map<String, dynamic>? ?? {};
          final todayExpense = data['todayExpense'] as String? ?? '0';
          final yesterdayExpense = data['yesterdayExpense'] as String? ?? '0';
          final activities = data['activities'] as List<dynamic>? ?? [];
          
          // 计算今日支出趋势
          final todayExpenseNum = double.tryParse(todayExpense) ?? 0.0;
          final yesterdayExpenseNum = double.tryParse(yesterdayExpense) ?? 0.0;
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
                                            ? Image.network(
                                                _currentFamily!.avatar!,
                              fit: BoxFit.cover,
                                                errorBuilder: (context, error, stackTrace) {
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
                                                  child: Image.network(
                                                    family.avatar!,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (context, error, stackTrace) {
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
                                  if (selectedFamily.id != _currentFamily?.id) {
                                    try {
                                      // 调用切换家庭接口
                                      await _familyService.switchFamily(selectedFamily.id);
                                      // 刷新家庭列表以获取最新的isCurrent状态
                                      await _loadFamilies();
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
                                          ? Image.network(
                                              _currentFamily!.avatar!,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) {
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
                          icon: const Icon(Icons.sync, color: Colors.white54),
                          onPressed: () {
                            provider.fetchHomeData();
                            _loadFamilies();
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
                                      '¥',
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
                                            ScaledText(
                                              '¥$income',
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
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
                                            ScaledText(
                                              '¥$expense',
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
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
                                            '¥${budget['used'] ?? 0}',
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
                                        '¥$todayExpense',
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
                                                ? '+¥${expenseDiff.toStringAsFixed(2)}'
                                                : '¥${expenseDiff.toStringAsFixed(2)}',
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
                                      _getIconFromString(item['icon'] as String? ?? ''),
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
                                    item['amount'] as String? ?? '',
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

  // Calculate budget progress (supports both old and new API formats)
  double _calculateBudgetProgress(Map<String, dynamic> budget) {
    // Try percentage first (new API format)
    if (budget['percentage'] != null) {
      final percentage = (budget['percentage'] as num).toDouble();
      return (percentage / 100).clamp(0.0, 1.0);
    }
    // Fall back to used/total calculation (old API format)
    final used = (budget['used'] as num? ?? 0).toDouble();
    final total = (budget['budget'] as num? ?? budget['total'] as num? ?? 1).toDouble();
    if (total == 0) return 0.0;
    return (used / total).clamp(0.0, 1.0);
  }

  // Get budget progress color based on percentage
  Color _getBudgetProgressColor(Map<String, dynamic> budget) {
    double percentage = 0.0;
    
    // Calculate percentage
    if (budget['percentage'] != null) {
      percentage = (budget['percentage'] as num).toDouble();
    } else {
      final used = (budget['used'] as num? ?? 0).toDouble();
      final total = (budget['budget'] as num? ?? budget['total'] as num? ?? 0).toDouble();
      if (total > 0) {
        percentage = (used / total) * 100;
      }
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

  IconData _getIconFromString(String iconName) {
    // 简单的图标映射，实际应该使用更完整的映射表
    switch (iconName) {
      case 'shopping_cart':
        return Icons.shopping_cart;
      case 'restaurant':
        return Icons.restaurant;
      case 'directions_car':
        return Icons.directions_car;
      default:
        return Icons.category;
    }
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
    final userId = item['userId'] as String?;
    if (userId != null && userId.isNotEmpty) {
      final member = _members.firstWhere(
        (m) => m.id == userId,
        orElse: () => FamilyMember(id: '', name: userName, role: FamilyMemberRole.member),
      );
      userName = member.name;
    }
    
    // 解析金额
    final amountStr = item['amount'] as String? ?? '0';
    final amount = double.tryParse(amountStr.replaceAll('¥', '').replaceAll(',', '')) ?? 0.0;
    
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
                '¥${amount.toStringAsFixed(2)}',
                color: isIncome ? ThemeHelper.primary(context) : Colors.white
              ),
              _buildDetailRow(
                AppLocalizations.of(context)!.date,
                DateFormat.yMMMMd(Localizations.localeOf(context).languageCode).format(transactionDate)
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
