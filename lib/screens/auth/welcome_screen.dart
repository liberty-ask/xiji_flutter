import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/theme_helper.dart';
import '../../widgets/common/scaled_text.dart';
import '../../l10n/app_localizations.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: ResponsiveHelper.containerMargin(context),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              // Logo
              Image.asset(
                'assets/images/logo.png',
                width: ResponsiveHelper.responsiveValue(
                  context,
                  small: 100.0,
                  normal: 120.0,
                  large: 140.0,
                ),
                height: ResponsiveHelper.responsiveValue(
                  context,
                  small: 100.0,
                  normal: 120.0,
                  large: 140.0,
                ),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  // 如果图片加载失败，显示默认图标
                  return Icon(
                    Icons.auto_awesome,
                    size: ResponsiveHelper.responsiveValue(
                      context,
                      small: 80.0,
                      normal: 100.0,
                      large: 120.0,
                    ),
                    color: ThemeHelper.primary(context),
                  );
                },
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, small: 24, normal: 32, large: 40)),
              ScaledText(
                AppLocalizations.of(context)!.appTitle,
                style: ResponsiveHelper.responsiveTextStyle(
                  context,
                  fontSize: ResponsiveHelper.responsiveValue(
                    context,
                    small: 28.0,
                    normal: 32.0,
                    large: 36.0,
                  ),
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context)),
              ScaledText(
                AppLocalizations.of(context)!.welcomeSlogan,
                style: ResponsiveHelper.responsiveTextStyle(
                  context,
                  color: Colors.white70,
                ),
              ),
              const Spacer(),
              // 登录按钮
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    context.push('/login');
                  },
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.buttonPadding(context).horizontal,
                      vertical: ResponsiveHelper.spacing(context, small: 14, normal: 16, large: 18),
                    ),
                  ),
                  child: ScaledText(AppLocalizations.of(context)!.login, style: ResponsiveHelper.responsiveTextStyle(context)),
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context)),
              // 注册按钮
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    context.push('/register');
                  },
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.buttonPadding(context).horizontal,
                      vertical: ResponsiveHelper.spacing(context, small: 14, normal: 16, large: 18),
                    ),
                    side: BorderSide(color: ThemeHelper.primary(context)),
                  ),
                  child: ScaledText(AppLocalizations.of(context)!.register, style: ResponsiveHelper.responsiveTextStyle(context)),
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, small: 24, normal: 32, large: 40)),
            ],
          ),
        ),
      ),
    );
  }
}

