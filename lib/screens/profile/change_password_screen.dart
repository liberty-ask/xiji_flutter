import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api/family_service.dart';
import '../../widgets/common/custom_snackbar.dart';
import '../../widgets/common/scaled_text.dart';
import '../../utils/responsive_helper.dart';
import '../../l10n/app_localizations.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final FamilyService _familyService = FamilyService();
  final _formKey = GlobalKey<FormState>();
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureOldPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _familyService.changePassword(
        oldPassword: _oldPasswordController.text,
        newPassword: _newPasswordController.text,
      );

      if (mounted) {
        CustomSnackBar.showSuccess(context, AppLocalizations.of(context)!.changeSuccessfully);
        context.pop();
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
        title: ScaledText(AppLocalizations.of(context)!.changePassword),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: ResponsiveHelper.containerMargin(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: ResponsiveHelper.spacing(context)),
              TextFormField(
                controller: _oldPasswordController,
                obscureText: _obscureOldPassword,
                decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.currentPassword,
                    prefixIcon: Icon(Icons.lock, size: ResponsiveHelper.iconSize(context)),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureOldPassword ? Icons.visibility : Icons.visibility_off,
                        size: ResponsiveHelper.iconSize(context),
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureOldPassword = !_obscureOldPassword;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return AppLocalizations.of(context)!.pleaseEnterCurrentPassword;
                    }
                    return null;
                  },
              ),
              SizedBox(height: ResponsiveHelper.spacing(context)),
              TextFormField(
                controller: _newPasswordController,
                obscureText: _obscureNewPassword,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.newPassword,
                  prefixIcon: Icon(Icons.lock_outline, size: ResponsiveHelper.iconSize(context)),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureNewPassword ? Icons.visibility : Icons.visibility_off,
                      size: ResponsiveHelper.iconSize(context),
                    ),
                    onPressed: () {
                      setState(() {
                        _obscureNewPassword = !_obscureNewPassword;
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
                  if (value == _oldPasswordController.text) {
                    return AppLocalizations.of(context)!.newPasswordCannotBeSame;
                  }
                  return null;
                },
              ),
              SizedBox(height: ResponsiveHelper.spacing(context)),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.confirmNewPassword,
                  prefixIcon: Icon(Icons.lock_reset, size: ResponsiveHelper.iconSize(context)),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword ? Icons.visibility : Icons.visibility_off,
                      size: ResponsiveHelper.iconSize(context),
                    ),
                    onPressed: () {
                      setState(() {
                        _obscureConfirmPassword = !_obscureConfirmPassword;
                      });
                    },
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return AppLocalizations.of(context)!.pleaseConfirmNewPassword;
                  }
                  if (value != _newPasswordController.text) {
                    return AppLocalizations.of(context)!.passwordsDoNotMatch;
                  }
                  return null;
                },
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, small: 20, normal: 24, large: 32)),
              ElevatedButton(
                onPressed: _isLoading ? null : _changePassword,
                style: ElevatedButton.styleFrom(
                  padding: ResponsiveHelper.buttonPadding(context),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : ScaledText(AppLocalizations.of(context)!.confirmChange, style: ResponsiveHelper.responsiveTextStyle(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

