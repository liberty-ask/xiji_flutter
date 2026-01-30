import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/custom_snackbar.dart';
import '../../widgets/common/scaled_text.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/error_helper.dart';
import '../../l10n/app_localizations.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await authProvider.login(
        _accountController.text.trim(),
        _passwordController.text,
      );

      // 只有在成功登录后才跳转
      if (mounted && authProvider.isAuthenticated) {
        context.go('/home');
      }
    } catch (e) {
      // 登录失败，显示错误提示，不跳转
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        // 提取错误消息
        final errorMessage = ErrorHelper.extractErrorMessage(e, defaultMessage: AppLocalizations.of(context)!.loginFailed);
        CustomSnackBar.showError(context, errorMessage);
      }
      return; // 确保不再执行后续代码
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ScaledText(AppLocalizations.of(context)!.login),
      ),
      body: SafeArea(
        child: Padding(
          padding: ResponsiveHelper.containerMargin(context),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: ResponsiveHelper.spacing(context, small: 24, normal: 32, large: 40)),
                TextFormField(
                  controller: _accountController,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.phoneOrUsername,
                    prefixIcon: Icon(Icons.person, size: ResponsiveHelper.iconSize(context)),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return AppLocalizations.of(context)!.pleaseEnterPhoneOrUsername;
                    }
                    return null;
                  },
                ),
                SizedBox(height: ResponsiveHelper.spacing(context)),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.password,
                    prefixIcon: Icon(Icons.lock, size: ResponsiveHelper.iconSize(context)),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility : Icons.visibility_off,
                        size: ResponsiveHelper.iconSize(context),
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return AppLocalizations.of(context)!.pleaseEnterPassword;
                    }
                    return null;
                  },
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, small: 20, normal: 24, large: 32)),
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleLogin,
                  style: ElevatedButton.styleFrom(
                    padding: ResponsiveHelper.buttonPadding(context),
                  ),
                  child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : ScaledText(AppLocalizations.of(context)!.login, style: ResponsiveHelper.responsiveTextStyle(context)),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () {
                        context.push('/forgot-password');
                      },
                      child: ScaledText(AppLocalizations.of(context)!.forgotPasswordQuestion, style: ResponsiveHelper.responsiveTextStyle(context)),
                    ),
                    TextButton(
                      onPressed: () {
                        context.push('/register');
                      },
                      child: ScaledText(AppLocalizations.of(context)!.noAccountRegister, style: ResponsiveHelper.responsiveTextStyle(context)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

