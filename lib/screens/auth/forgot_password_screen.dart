import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api/auth_service.dart';
import '../../widgets/common/custom_snackbar.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/error_helper.dart';
import '../../utils/theme_helper.dart';
import '../../widgets/common/scaled_text.dart';
import '../../l10n/app_localizations.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _obscurePassword = true;
  bool _isLoading = false; // 用于重置密码按钮
  bool _isSendingCode = false; // 用于发送验证码按钮
  int _countdown = 0;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(phone)) {
      CustomSnackBar.showError(context, AppLocalizations.of(context)!.pleaseEnterCorrectPhone);
      return;
    }

    // 立即开始倒计时，不显示loading
    setState(() {
      _countdown = 60;
      _isSendingCode = true; // 防止重复点击
    });

    // 启动倒计时计时器
    Future.delayed(Duration.zero, () async {
      while (_countdown > 0 && mounted) {
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          setState(() {
            _countdown--;
          });
        }
      }
      
      // 倒计时结束，允许重新发送
      if (mounted) {
        setState(() {
          _isSendingCode = false;
        });
      }
    });

    // 在后台发送验证码
    try {
      await _authService.sendForgotPasswordCode(phone);
      if (mounted) {
        CustomSnackBar.showSuccess(context, AppLocalizations.of(context)!.verificationCodeSentSuccessfully);
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = ErrorHelper.extractErrorMessage(e, defaultMessage: AppLocalizations.of(context)!.error);
        CustomSnackBar.showError(context, errorMessage);
      }
    }
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _authService.resetPassword(
        phone: _phoneController.text.trim(),
        code: _codeController.text.trim(),
        newPassword: _passwordController.text,
      );

      if (mounted) {
        CustomSnackBar.showSuccess(context, AppLocalizations.of(context)!.passwordResetSuccessfully);
        context.go('/login');
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = ErrorHelper.extractErrorMessage(e, defaultMessage: AppLocalizations.of(context)!.error);
        CustomSnackBar.showError(context, errorMessage);
      }
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
        title: ScaledText(AppLocalizations.of(context)!.forgotPassword),
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
                // 手机号输入框
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.phone,
                    prefixIcon: Icon(Icons.phone, size: ResponsiveHelper.iconSize(context)),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return AppLocalizations.of(context)!.pleaseEnterPhone;
                    }
                    if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(value)) {
                      return AppLocalizations.of(context)!.pleaseEnterCorrectPhone;
                    }
                    return null;
                  },
                ),
                SizedBox(height: ResponsiveHelper.spacing(context)),
                // 验证码输入框和发送按钮
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _codeController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: AppLocalizations.of(context)!.verificationCode,
                          prefixIcon: Icon(Icons.sms, size: ResponsiveHelper.iconSize(context)),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return AppLocalizations.of(context)!.pleaseEnterVerificationCode;
                          }
                          return null;
                        },
                      ),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, small: 10, normal: 12)),
                    ElevatedButton(
                      onPressed: _countdown > 0 || _isSendingCode
                          ? null
                          : _sendCode,
                      style: ElevatedButton.styleFrom(
                        padding: ResponsiveHelper.buttonPadding(context),
                      ),
                      child: _countdown > 0
                          ? Text(
                              '${_countdown}s',
                              style: ResponsiveHelper.responsiveTextStyle(
                                context,
                                fontSize: ResponsiveHelper.responsiveValue(context, small: 11.0, normal: 14.0),
                              ),
                            )
                          : _isSendingCode
                              ? SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(ThemeHelper.primary(context)),
                                  ),
                                )
                              : ScaledText(
                                  AppLocalizations.of(context)!.sendVerificationCode,
                                  style: ResponsiveHelper.responsiveTextStyle(
                                    context,
                                    fontSize: ResponsiveHelper.responsiveValue(context, small: 11.0, normal: 14.0),
                                  ),
                                ),
                    ),
                  ],
                ),
                SizedBox(height: ResponsiveHelper.spacing(context)),
                // 新密码输入框
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.newPassword,
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
                      return AppLocalizations.of(context)!.pleaseEnterNewPassword;
                    }
                    if (value.length < 6) {
                      return AppLocalizations.of(context)!.passwordAtLeast6Chars;
                    }
                    return null;
                  },
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, small: 20, normal: 24, large: 32)),
                // 重置密码按钮
                ElevatedButton(
                  onPressed: _isLoading ? null : _resetPassword,
                  style: ElevatedButton.styleFrom(
                    padding: ResponsiveHelper.buttonPadding(context),
                  ),
                  child: _isLoading
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(ThemeHelper.primary(context)),
                      ),
                    )
                  : ScaledText(AppLocalizations.of(context)!.resetPassword, style: ResponsiveHelper.responsiveTextStyle(context)),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context)),
                TextButton(
                  onPressed: () {
                    context.push('/login');
                  },
                  child: ScaledText(AppLocalizations.of(context)!.backToLogin, style: ResponsiveHelper.responsiveTextStyle(context)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

