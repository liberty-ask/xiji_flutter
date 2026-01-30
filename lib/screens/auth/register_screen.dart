import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/api/auth_service.dart';
import '../../widgets/common/custom_snackbar.dart';
import '../../widgets/common/scaled_text.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/constants.dart';
import '../../l10n/app_localizations.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nicknameController = TextEditingController();
  
  bool _obscurePassword = true;
  bool _isLoading = false; // 注册按钮的loading状态
  bool _isSendingCode = false; // 发送验证码按钮的loading状态
  int _countdown = 0;
  final AuthService _authService = AuthService();

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(phone)) {
      CustomSnackBar.showError(context, AppLocalizations.of(context)!.pleaseEnterCorrectPhone);
      return;
    }

    setState(() {
      _isSendingCode = true;
    });

    try {
      await _authService.sendRegisterCode(phone);
      if (mounted) {
        setState(() {
          _countdown = 60;
          _isSendingCode = false;
        });
      }
      
      // 倒计时
      while (_countdown > 0 && mounted) {
        await Future.delayed(const Duration(seconds: AppConstants.commonDelaySeconds));
        if (mounted) {
          setState(() {
            _countdown--;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSendingCode = false;
        });
        String errorMessage = AppLocalizations.of(context)!.error;
        if (e.toString().contains('Exception:')) {
          errorMessage = e.toString().replaceFirst('Exception: ', '');
        }
        CustomSnackBar.showError(context, errorMessage);
      }
    }
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final result = await _authService.register(
        phone: _phoneController.text.trim(),
        code: _codeController.text.trim(),
        password: _passwordController.text,
        nickname: _nicknameController.text.trim(),
      );

      // 注册接口直接返回token和用户信息，直接使用
      await authProvider.setUserFromRegisterResponse(result);

      if (mounted) {
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = AppLocalizations.of(context)!.error;
        if (e.toString().contains('Exception:')) {
          errorMessage = e.toString().replaceFirst('Exception: ', '');
        }
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
        title: ScaledText(AppLocalizations.of(context)!.register),
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
                      child: _isSendingCode
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : ScaledText(
                                _countdown > 0 ? '${_countdown}s' : AppLocalizations.of(context)!.getVerificationCode,
                                style: ResponsiveHelper.responsiveTextStyle(
                                  context,
                                  fontSize: ResponsiveHelper.responsiveValue(context, small: 11.0, normal: 14.0),
                                ),
                              ),
                    ),
                  ],
                ),
                SizedBox(height: ResponsiveHelper.spacing(context)),
                TextFormField(
                  controller: _nicknameController,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.nickname,
                    prefixIcon: Icon(Icons.person, size: ResponsiveHelper.iconSize(context)),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return AppLocalizations.of(context)!.pleaseEnterNickname;
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
                    if (value.length < 6) {
                      return AppLocalizations.of(context)!.passwordAtLeast6Chars;
                    }
                    return null;
                  },
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, small: 20, normal: 24, large: 32)),
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleRegister,
                  style: ElevatedButton.styleFrom(
                    padding: ResponsiveHelper.buttonPadding(context),
                  ),
                  child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : ScaledText(AppLocalizations.of(context)!.register, style: ResponsiveHelper.responsiveTextStyle(context)),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context)),
                TextButton(
                  onPressed: () {
                    context.push('/login');
                  },
                  child: ScaledText(AppLocalizations.of(context)!.haveAccountLogin, style: ResponsiveHelper.responsiveTextStyle(context)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
