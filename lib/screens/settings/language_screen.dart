import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/language_provider.dart';
import '../../providers/theme_provider.dart';
import '../../models/theme_config.dart';
import '../../widgets/common/bottom_nav_bar.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/common/scaled_text.dart';
import '../../l10n/app_localizations.dart';

class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  Locale? _selectedLocale;
  Locale? _originalLocale;

  @override
  void initState() {
    super.initState();
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    _selectedLocale = languageProvider.currentLocale;
    _originalLocale = languageProvider.currentLocale;
  }

  void _handleLanguageSelect(Locale? locale) {
    setState(() {
      _selectedLocale = locale;
    });
  }

  void _handleConfirm() async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    await languageProvider.setLanguage(_selectedLocale);
    if (mounted) {
      final appLocalizations = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${appLocalizations.language} ${appLocalizations.successfullySaved}'),
          backgroundColor: Provider.of<ThemeProvider>(context, listen: false).currentTheme.primary,
        ),
      );
      context.pop();
    }
  }

  void _handleCancel() {
    setState(() {
      _selectedLocale = _originalLocale;
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
    final languageProvider = Provider.of<LanguageProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final currentTheme = themeProvider.currentTheme;
    final languages = languageProvider.supportedLanguages;
    final confirmText = AppLocalizations.of(context)!.confirm;
    final saveText = AppLocalizations.of(context)!.save;
    final cancelText = AppLocalizations.of(context)!.cancel;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _handleCancel,
        ),
        title: ScaledText(AppLocalizations.of(context)!.language),
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
                    Icons.language,
                    color: currentTheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ScaledText(
                          AppLocalizations.of(context)!.language,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                        const SizedBox(height: 4),
                        ScaledText(
                          '选择应用的显示语言，设置会保存到本地，即使退出登录也会保留。',
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

            // 语言列表
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
                children: languages.map((option) {
                  final isSelected = _selectedLocale?.toString() == option.locale?.toString();
                  return Column(
                    children: [
                      _buildLanguageOption(
                        context, 
                        option.locale, 
                        option.name, 
                        option.icon,
                        currentTheme
                      ),
                      if (languages.indexOf(option) < languages.length - 1)
                        SizedBox(height: 12),
                    ],
                  );
                }).toList(),
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
                        '$confirmText $saveText',
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
                      cancelText,
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

  Widget _buildLanguageOption(BuildContext context, Locale? locale, String title, IconData icon, ThemeConfig currentTheme) {
    final isSelected = _selectedLocale?.toString() == locale?.toString();
    return InkWell(
      onTap: () => _handleLanguageSelect(locale),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isSelected ? currentTheme.primary.withValues(alpha: 0.1) : currentTheme.surfaceDark,
          border: Border.all(
            color: isSelected ? currentTheme.primary : Colors.white.withValues(alpha: 0.1),
            width: isSelected ? 1 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? currentTheme.primary : Colors.white.withValues(alpha: 0.7),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ScaledText(
                title,
                style: TextStyle(
                  fontSize: 14,
                  color: isSelected ? currentTheme.primary : Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: currentTheme.primary,
                size: 20,
              )
            else
              Icon(
                Icons.circle_outlined,
                color: Colors.white.withValues(alpha: 0.3),
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
