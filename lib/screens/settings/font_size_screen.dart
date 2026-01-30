import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/font_size_provider.dart';
import '../../providers/theme_provider.dart';
import '../../widgets/common/bottom_nav_bar.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/common/scaled_text.dart';
import '../../l10n/app_localizations.dart';

class FontSizeScreen extends StatefulWidget {
  const FontSizeScreen({super.key});

  @override
  State<FontSizeScreen> createState() => _FontSizeScreenState();
}

class _FontSizeScreenState extends State<FontSizeScreen> {
  double _currentScale = 1.0;
  double _originalScale = 1.0;

  @override
  void initState() {
    super.initState();
    final fontSizeProvider = Provider.of<FontSizeProvider>(context, listen: false);
    _currentScale = fontSizeProvider.fontSizeScale;
    _originalScale = fontSizeProvider.fontSizeScale;
  }

  void _handleFontSizeChange(double scale) {
    setState(() {
      _currentScale = scale;
    });
    // 只更新本地状态，不实时更新 FontSizeProvider
    // 这样可以避免频繁触发主题重建，导致 TextStyle 断言失败
  }

  void _handleConfirm() async {
    final fontSizeProvider = Provider.of<FontSizeProvider>(context, listen: false);
    await fontSizeProvider.setFontSize(_currentScale);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ScaledText(AppLocalizations.of(context)!.fontSizeSettings),
          backgroundColor: Provider.of<ThemeProvider>(context, listen: false).currentTheme.primary,
        ),
      );
      context.pop();
    }
  }

  void _handleCancel() {
    final fontSizeProvider = Provider.of<FontSizeProvider>(context, listen: false);
    fontSizeProvider.setFontSize(_originalScale);
    setState(() {
      _currentScale = _originalScale;
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

  // 获取当前字号对应的国际化描述
  String _getFontSizeDescription(double scale) {
    if (scale < 0.9) {
      return AppLocalizations.of(context)!.fontSizeTiny;
    } else if (scale < 1.0) {
      return AppLocalizations.of(context)!.fontSizeSmall;
    } else if (scale < 1.1) {
      return AppLocalizations.of(context)!.fontSizeStandard;
    } else if (scale < 1.2) {
      return AppLocalizations.of(context)!.fontSizeLarge;
    } else if (scale < 1.3) {
      return AppLocalizations.of(context)!.fontSizeExtraLarge;
    } else {
      return AppLocalizations.of(context)!.fontSizeHuge;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fontSizeProvider = Provider.of<FontSizeProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final currentTheme = themeProvider.currentTheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _handleCancel,
        ),
        title: ScaledText(AppLocalizations.of(context)!.fontSizeSettings),
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
                    Icons.text_fields,
                    color: currentTheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ScaledText(
                          AppLocalizations.of(context)!.fontSizeSettings,
                          style: TextStyle(
                            fontSize: 12, 
                            fontWeight: FontWeight.bold,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                        const SizedBox(height: 4),
                        ScaledText(
                          AppLocalizations.of(context)!.fontSizeSettingsSubtitle,
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
            const SizedBox(height: 32),

            // 字号预览
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: currentTheme.surface,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ScaledText(
                    AppLocalizations.of(context)!.fontSizeSettingsSubtitle,
                    style: TextStyle(
                      fontSize: 14  * _currentScale,
                      fontWeight: FontWeight.bold,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ScaledText(
                    AppLocalizations.of(context)!.fontSizeSettings,
                    style: TextStyle(
                      fontSize: 18 * _currentScale,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ScaledText(
                    AppLocalizations.of(context)!.fontSizeSettingsSubtitle,
                    style: TextStyle(
                      fontSize: 14 * _currentScale,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ScaledText(
                    AppLocalizations.of(context)!.fontSizeSettingsSubtitle,
                    style: TextStyle(
                      fontSize: 12 * _currentScale,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // 字号滑块
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: currentTheme.surface,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(
                        Icons.text_fields,
                        color: currentTheme.primary,
                        size: 20,
                      ),
                      ScaledText(
                        _getFontSizeDescription(_currentScale),
                        style: TextStyle(
                          fontSize: 14,
                          color: currentTheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Icon(
                        Icons.text_fields,
                        color: currentTheme.primary,
                        size: 24,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Slider(
                    value: _currentScale,
                    min: 0.8,
                    max: 1.4,
                    divisions: 6, // 0.8 到 1.4 之间 6 个档位
                    onChanged: _handleFontSizeChange,
                    activeColor: currentTheme.primary,
                    inactiveColor: Colors.white.withValues(alpha: 0.2),
                    thumbColor: currentTheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ScaledText(
                        AppLocalizations.of(context)!.small,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                      ScaledText(
                        AppLocalizations.of(context)!.standard,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                      ScaledText(
                        AppLocalizations.of(context)!.large,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

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
                        AppLocalizations.of(context)!.saveChanges,
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
