import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';
import '../../models/theme_config.dart';
import '../../widgets/common/bottom_nav_bar.dart';
import '../../widgets/common/scaled_text.dart';
import '../../utils/responsive_helper.dart';
import '../../l10n/app_localizations.dart';

class ThemeScreen extends StatefulWidget {
  const ThemeScreen({super.key});

  @override
  State<ThemeScreen> createState() => _ThemeScreenState();
}

class _ThemeScreenState extends State<ThemeScreen> {
  String _selectedThemeId = ThemeConfig.defaultTheme.id;
  String _originalThemeId = ThemeConfig.defaultTheme.id;

  @override
  void initState() {
    super.initState();
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    _selectedThemeId = themeProvider.currentTheme.id;
    _originalThemeId = themeProvider.currentTheme.id;
  }

  void _handleThemeSelect(String themeId) {
    setState(() {
      _selectedThemeId = themeId;
    });
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    if (themeId != _originalThemeId) {
      themeProvider.applyPreviewTheme(themeId);
    } else {
      themeProvider.clearPreview();
    }
  }

  void _handleConfirm() async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    await themeProvider.setTheme(_selectedThemeId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.themeSaved),
          backgroundColor: themeProvider.currentTheme.primary,
        ),
      );
      context.pop();
    }
  }

  void _handleCancel() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    themeProvider.clearPreview();
    setState(() {
      _selectedThemeId = _originalThemeId;
    });
    context.pop();
  }

  void _onTabTapped(int index) {
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
    final themeProvider = Provider.of<ThemeProvider>(context);
    final currentTheme = themeProvider.activeTheme;
    final hasPreview = themeProvider.previewTheme != null;
    
    // 使用Provider中的主题列表
    final themes = ThemeConfig.themes;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _handleCancel,
        ),
        title: ScaledText(AppLocalizations.of(context)!.theme),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          ResponsiveHelper.horizontalPadding(context),
          ResponsiveHelper.spacing(context, small: 20, normal: 24, large: 32),
          ResponsiveHelper.horizontalPadding(context),
          100,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 提示信息
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: currentTheme.surface.withValues(alpha: 0.5),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.palette,
                    color: currentTheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ScaledText(
                          AppLocalizations.of(context)!.themePreview,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                        const SizedBox(height: 4),
                        ScaledText(
                          AppLocalizations.of(context)!.themePreviewDescription,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.white.withValues(alpha: 0.4),
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 主题列表标题
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ScaledText(
                AppLocalizations.of(context)!.selectTheme,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 主题网格（2列布局，匹配原始设计）
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 32,
                childAspectRatio: 0.8,
              ),
              itemCount: themes.length,
              itemBuilder: (context, index) {
                final theme = themes[index];
                final isSelected = _selectedThemeId == theme.id;

                // 获取本地化的主题名称
                String getLocalizedThemeName(String themeId) {
                  switch (themeId) {
                    case 'green':
                      return AppLocalizations.of(context)!.themeGreen;
                    case 'blue':
                      return AppLocalizations.of(context)!.themeBlue;
                    case 'purple':
                      return AppLocalizations.of(context)!.themePurple;
                    case 'orange':
                      return AppLocalizations.of(context)!.themeOrange;
                    case 'pink':
                      return AppLocalizations.of(context)!.themePink;
                    case 'cyan':
                      return AppLocalizations.of(context)!.themeCyan;
                    default:
                      return theme.name;
                  }
                }

                return InkWell(
                  onTap: () => _handleThemeSelect(theme.id),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    constraints: const BoxConstraints(minHeight: 240),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? currentTheme.primary
                            : Colors.white.withValues(alpha: 0.1),
                        width: isSelected ? 2 : 1,
                      ),
                      color: isSelected
                          ? currentTheme.primary.withValues(alpha: 0.1)
                          : currentTheme.surface,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // 主题颜色预览圆形
                        Stack(
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: theme.primary,
                                border: Border.all(
                                  color: currentTheme.surface,
                                  width: 4,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: theme.primary.withValues(alpha: 0.3),
                                    blurRadius: 20,
                                    spreadRadius: 0,
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              Positioned(
                                top: -4,
                                right: -4,
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: currentTheme.primary,
                                    border: Border.all(
                                      color: currentTheme.surface,
                                      width: 2,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.check,
                                    color: currentTheme.background,
                                    size: 14,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // 主题名称
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.center,
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 120),
                              child: ScaledText(
                                getLocalizedThemeName(theme.id),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? currentTheme.primary
                                      : Colors.white.withValues(alpha: 0.8),
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 颜色预览条
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 8,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  color: theme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              width: 32,
                              height: 8,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                color: theme.primaryDark,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              width: 24,
                              height: 8,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                color: theme.surface,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // 预览提示
            if (hasPreview && themeProvider.previewTheme != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: currentTheme.primary.withValues(alpha: 0.1),
                  border: Border.all(
                    color: currentTheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.preview,
                      color: currentTheme.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ScaledText(
                            AppLocalizations.of(context)!.previewingTheme(() {
                              // 获取本地化的主题名称
                              final previewTheme = themeProvider.previewTheme!;
                              switch (previewTheme.id) {
                                case 'green':
                                  return AppLocalizations.of(context)!.themeGreen;
                                case 'blue':
                                  return AppLocalizations.of(context)!.themeBlue;
                                case 'purple':
                                  return AppLocalizations.of(context)!.themePurple;
                                case 'orange':
                                  return AppLocalizations.of(context)!.themeOrange;
                                case 'pink':
                                  return AppLocalizations.of(context)!.themePink;
                                case 'cyan':
                                  return AppLocalizations.of(context)!.themeCyan;
                                default:
                                  return previewTheme.name;
                              }
                            }()),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: currentTheme.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ScaledText(
                            AppLocalizations.of(context)!.previewingThemeDescription,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),

            // 操作按钮
            Column(
              children: [
                ElevatedButton(
                  onPressed: _handleConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: currentTheme.primary,
                    foregroundColor: currentTheme.background,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check, size: 20),
                      SizedBox(width: 8),
                      ScaledText(
                        AppLocalizations.of(context)!.confirmAndSave,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _handleCancel,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                      color: currentTheme.surface,
                    ),
                    child: ScaledText(
                        AppLocalizations.of(context)!.cancel,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                        textAlign: TextAlign.center,
                      ),
                  ),
                ),
              ],
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
}

