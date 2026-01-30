import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/api/family_service.dart';
import '../../widgets/common/bottom_nav_bar.dart';
import '../../widgets/common/font_size_inherited.dart';
import '../../widgets/common/scaled_text.dart';
import '../../utils/theme_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../models/user.dart';
import '../../l10n/app_localizations.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FamilyService _familyService = FamilyService();
  int? _auditCount;

  @override
  void initState() {
    super.initState();
    _loadAuditCount();
  }

  Future<void> _loadAuditCount() async {
    final authProvider = context.read<AuthProvider>();
    final user = authProvider.user;
    
    if (UserRole.isAdmin(user?.role)) {
      try {
        final profile = await _familyService.getUserProfile();
        if (mounted) {
          setState(() {
            _auditCount = profile['auditCount'] as int?;
          });
        }
      } catch (e) {
        // 忽略错误
      }
    }
  }

  void _onTabTapped(int index) {
    setState(() {}); // 更新当前索引状�?

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
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.user;
    // 获取字号缩放因子
    final fontSizeScale = FontSizeInherited.of(context).fontSizeScale;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.horizontalPadding(context),
                vertical: ResponsiveHelper.verticalPadding(context),
              ),
              child: Row(
                children: [
                  ScaledText(
                    AppLocalizations.of(context)!.profile,
                    style: ResponsiveHelper.responsiveTextStyle(
                      context,
                      fontSize: ResponsiveHelper.responsiveValue(
                        context,
                        small: 20.0,
                        normal: 24.0,
                        large: 28.0,
                      ),
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.horizontalPadding(context),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 用户信息卡片
                    InkWell(
                      onTap: () => context.push('/edit-profile'),
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          color: ThemeHelper.surface(context),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 32,
                              backgroundImage: user?.avatar != null
                                  ? NetworkImage(user!.avatar!)
                                  : null,
                              backgroundColor: ThemeHelper.primary(context).withValues(alpha: 0.2),
                              child: user?.avatar == null
                                  ? Text(
                                      user?.nickname[0].toUpperCase() ?? 'U',
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: ThemeHelper.primary(context),
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ScaledText(
                                    user?.nickname ?? AppLocalizations.of(context)!.noNicknameSet,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  ScaledText(
                                    user?.phone ?? '',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.white.withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.chevron_right, color: Colors.white54),
                              onPressed: () => context.push('/edit-profile'),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // 财务管理
                    _buildSectionTitle(AppLocalizations.of(context)!.financialManagement),
                    const SizedBox(height: 12),
                    _buildMenuCard(
                      icon: Icons.upload_file,
                      title: AppLocalizations.of(context)!.billImport,
                      subtitle: AppLocalizations.of(context)!.billImportSubtitle,
                      onTap: () => context.push('/import-bills'),
                    ),
                    _buildMenuCard(
                      icon: Icons.account_balance_wallet,
                      title: AppLocalizations.of(context)!.monthlyBudget,
                      subtitle: AppLocalizations.of(context)!.monthlyBudgetSubtitle,
                      onTap: () => context.push('/budget'),
                    ),
                    if (UserRole.isAdmin(user?.role))
                      _buildMenuCard(
                        icon: Icons.category,
                        title: AppLocalizations.of(context)!.categoryManagement,
                        subtitle: AppLocalizations.of(context)!.categoryManagementSubtitle,
                        onTap: () => context.push('/category-manage'),
                      ),

                    const SizedBox(height: 24),

                    // 家庭设置
                    _buildSectionTitle(AppLocalizations.of(context)!.familySettings),
                    const SizedBox(height: 12),
                    _buildMenuCard(
                      icon: Icons.group,
                      title: AppLocalizations.of(context)!.memberManagement,
                      subtitle: AppLocalizations.of(context)!.memberManagementSubtitle,
                      onTap: () => context.push('/members'),
                    ),
                    if (UserRole.isAdmin(user?.role))
                      _buildMenuCard(
                        icon: Icons.verified_user,
                        title: AppLocalizations.of(context)!.joinAudit,
                        badge: _auditCount,
                        onTap: () => context.push('/audit'),
                      ),
                    _buildMenuCard(
                      icon: Icons.person_add,
                      title: AppLocalizations.of(context)!.familyInvite,
                      onTap: () => context.push('/invite'),
                    ),

                    const SizedBox(height: 24),

                    // 外观设置
                    _buildSectionTitle(AppLocalizations.of(context)!.appearanceSettings),
                    const SizedBox(height: 12),
                    _buildMenuCard(
                      icon: Icons.palette,
                      title: AppLocalizations.of(context)!.themeColor,
                      subtitle: AppLocalizations.of(context)!.themeColorSubtitle,
                      onTap: () => context.push('/theme'),
                    ),
                    _buildMenuCard(
                      icon: Icons.language,
                      title: AppLocalizations.of(context)!.languageSettings,
                      subtitle: AppLocalizations.of(context)!.languageSettingsSubtitle,
                      onTap: () => context.push('/language'),
                    ),
                    _buildMenuCard(
                      icon: Icons.text_fields,
                      title: AppLocalizations.of(context)!.fontSizeSettings,
                      subtitle: AppLocalizations.of(context)!.fontSizeSettingsSubtitle,
                      onTap: () => context.push('/font-size'),
                    ),

                    const SizedBox(height: 24),

                    // 安全中心
                    _buildSectionTitle(AppLocalizations.of(context)!.securityCenter),
                    const SizedBox(height: 12),
                    _buildMenuCard(
                      icon: Icons.lock_reset,
                      title: AppLocalizations.of(context)!.changeLoginPassword,
                      onTap: () => context.push('/change-password'),
                    ),
                    _buildMenuCard(
                      icon: Icons.meeting_room,
                      title: AppLocalizations.of(context)!.exitCurrentFamily,
                      isDanger: true,
                      onTap: () => context.push('/exit-family'),
                    ),

                    const SizedBox(height: 32),

                    // 退出登�?
                    ElevatedButton(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(AppLocalizations.of(context)!.confirmLogout),
                            content: Text(AppLocalizations.of(context)!.logoutConfirmMessage),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text(AppLocalizations.of(context)!.cancel),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: Text(AppLocalizations.of(context)!.logout),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true && mounted) {
                          await authProvider.logout();
                          if (mounted) {
                            context.go('/welcome');
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ThemeHelper.expenseColor(context).withValues(alpha: 0.2),
                        foregroundColor: ThemeHelper.expenseColor(context),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        overlayColor: Colors.transparent,
                        splashFactory: NoSplash.splashFactory,
                      ),
                      child: ScaledText(AppLocalizations.of(context)!.logoutButton),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: 4,
        onTap: _onTabTapped,
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return ScaledText(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: Colors.white.withValues(alpha: 0.6),
        letterSpacing: 1,
      ),
    );
  }

  Widget _buildMenuCard({
    required IconData icon,
    required String title,
    String? subtitle,
    int? badge,
    bool isDanger = false,
    required VoidCallback onTap,
  }) {
    // 获取主题的亮度
    final brightness = Theme.of(context).brightness;
    // 获取主题的文本颜色
    final textColor = Theme.of(context).colorScheme.onSurface;
    // 获取边框颜色
    final borderColor = brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.1) : Colors.grey[200]!;
    // 获取右侧箭头颜色
    final arrowColor = brightness == Brightness.dark ? Colors.white54 : Colors.grey[400]!;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: ThemeHelper.surface(context),
        border: Border.all(
          color: borderColor,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isDanger
                  ? ThemeHelper.expenseColor(context).withValues(alpha: 0.2)
                  : ThemeHelper.primary(context).withValues(alpha: 0.2),
            ),
            child: Icon(
              icon,
              color: isDanger ? ThemeHelper.expenseColor(context) : ThemeHelper.primary(context),
              size: 20,
            ),
          ),
          title: ScaledText(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDanger ? ThemeHelper.expenseColor(context) : Colors.white,
            ),
          ),
          subtitle: subtitle != null
              ? ScaledText(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                )
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (badge != null && badge > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: ThemeHelper.primary(context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ScaledText(
                    badge.toString(),
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: arrowColor),
            ],
          ),
          onTap: onTap,
          splashColor: Colors.transparent,
        ),
      ),
    );
  }
}
