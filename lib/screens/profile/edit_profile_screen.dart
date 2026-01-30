import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/auth_provider.dart';
import '../../services/api/family_service.dart';
import '../../widgets/common/custom_snackbar.dart';
import '../../utils/theme_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/common/scaled_text.dart';
import '../../l10n/app_localizations.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final FamilyService _familyService = FamilyService();
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _imagePicker = ImagePicker();
  
  String? _avatar; // 当前头像URL（用于保存）
  String? _avatarPreview; // 头像预览（可能是base64或URL）
  XFile? _selectedImageFile; // 选择的本地图片文件
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final authProvider = context.read<AuthProvider>();
    final user = authProvider.user;
    if (user != null) {
      _nicknameController.text = user.nickname;
      _avatar = user.avatar;
      _avatarPreview = user.avatar;
      _emailController.text = user.email ?? '';
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  // 选择本地图片
  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        try {
          // 读取文件字节以验证大小和生成预览
          final bytes = await pickedFile.readAsBytes();
          
          // 验证文件大小（限制5MB）
          if (bytes.length > 5 * 1024 * 1024) {
            if (mounted) {
              setState(() {
                _error = AppLocalizations.of(context)!.imageSizeCannotExceed5MB;
              });
            }
            return;
          }

          // 在Web平台上，使用base64预览；在移动平台上，使用文件路径
          String previewPath = pickedFile.path;
          if (pickedFile.path.isEmpty) {
            // Web平台：使用base64预览
            final base64String = base64Encode(bytes);
            final extension = pickedFile.name.split('.').last.toLowerCase();
            previewPath = 'data:image/$extension;base64,$base64String';
          }

          if (mounted) {
            setState(() {
              _selectedImageFile = pickedFile;
              _avatarPreview = previewPath;
              _avatar = previewPath; // 临时使用，保存时会上传到服务器获取真实URL
              _error = null;
            });
          }
        } catch (fileError) {
          // 处理文件操作错误
          if (mounted) {
            setState(() {
              _error = AppLocalizations.of(context)!.processingImageFailed(fileError.toString());
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        // 更友好的错误提示
        String errorMessage = AppLocalizations.of(context)!.selectImageFailed;
        if (e.toString().contains('Permission') || e.toString().contains('权限')) {
          errorMessage = AppLocalizations.of(context)!.needGalleryPermission;
        } else if (e.toString().contains('User cancelled') || e.toString().contains('取消')) {
          // 用户取消选择，不显示错误
          return;
        } else {
          errorMessage = AppLocalizations.of(context)!.selectImageFailed;
        }
        setState(() {
          _error = errorMessage;
        });
      }
    }
  }

  // 验证邮箱格式
  bool _isValidEmail(String email) {
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return emailRegex.hasMatch(email);
  }

  // 构建头像预览
  Widget _buildAvatarPreview() {
    if (_avatarPreview == null || _avatarPreview!.isEmpty) {
      return Container(
        color: ThemeHelper.surfaceLight(context),
        child: Icon(
          Icons.person,
          size: 64,
          color: Colors.white.withValues(alpha: 0.2),
        ),
      );
    }

    try {
      // 检查是否是base64格式（Web平台）
      if (_avatarPreview!.startsWith('data:image/')) {
        try {
          final parts = _avatarPreview!.split(',');
          if (parts.length > 1) {
            final base64String = parts[1];
            final bytes = base64Decode(base64String);
            return Image.memory(
              bytes,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: ThemeHelper.surfaceLight(context),
                  child: Icon(
                    Icons.person,
                    size: 64,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                );
              },
            );
          }
        } catch (e) {
          // base64解码失败，显示默认图标
          return Container(
            color: ThemeHelper.surfaceLight(context),
            child: Icon(
              Icons.person,
              size: 64,
              color: Colors.white.withValues(alpha: 0.2),
            ),
          );
        }
      }

      // 检查是否是本地文件路径
      if (_selectedImageFile != null && _selectedImageFile!.path.isNotEmpty) {
        try {
          final file = File(_selectedImageFile!.path);
          return Image.file(
            file,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              // 文件读取失败，尝试网络图片
              return Image.network(
                _avatarPreview!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: ThemeHelper.surfaceLight(context),
                    child: Icon(
                      Icons.person,
                      size: 64,
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  );
                },
              );
            },
          );
        } catch (e) {
          // 文件读取失败，继续尝试网络图片
        }
      }

      // 尝试作为网络URL显示
      return Image.network(
        _avatarPreview!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: ThemeHelper.surfaceLight(context),
            child: Icon(
              Icons.person,
              size: 64,
              color: Colors.white.withValues(alpha: 0.2),
            ),
          );
        },
      );
    } catch (e) {
      // 所有方式都失败，显示默认图标
      return Container(
        color: ThemeHelper.surfaceLight(context),
        child: Icon(
          Icons.person,
          size: 64,
          color: Colors.white.withValues(alpha: 0.2),
        ),
      );
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_nicknameController.text.trim().isEmpty) {
      setState(() {
        _error = AppLocalizations.of(context)!.pleaseEnterNickname;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 如果有选择的本地图片文件，先上传到服务器获取URL
      String? avatarToSave = _avatar;
      if (_selectedImageFile != null) {
        // 上传文件到服务器
        avatarToSave = await _familyService.uploadFile(_selectedImageFile!);
        // 更新预览为上传后的URL
        setState(() {
          _avatarPreview = avatarToSave;
          _avatar = avatarToSave;
        });
      }

      // 准备邮箱参数（如果输入了的话）
      String? email = _emailController.text.trim();
      if (email.isEmpty) {
        email = null;
      }

      await _familyService.updateProfile(
        nickname: _nicknameController.text.trim(),
        avatar: avatarToSave?.isNotEmpty == true ? avatarToSave : null,
        email: email,
      );

      // 更新用户信息
      final authProvider = context.read<AuthProvider>();
      await authProvider.refreshUser();

      if (mounted) {
        CustomSnackBar.showSuccess(context, AppLocalizations.of(context)!.saveSuccessfully);
        context.pop();
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _isLoading ? null : () => context.pop(),
        ),
        title: ScaledText(AppLocalizations.of(context)!.editProfile),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: ResponsiveHelper.containerMargin(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 头像预览区域
              Container(
                padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, small: 24, normal: 32, large: 40),
                ),
                child: Column(
                  children: [
                    // 头像预览（带模糊背景效果）
                    Container(
                      alignment: Alignment.center,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // 模糊背景效果
                          Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              shape: BoxShape.rectangle,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: ThemeHelper.primary(context).withValues(alpha: 0.3),
                                  blurRadius: 40,
                                  spreadRadius: 10,
                                ),
                              ],
                            ),
                          ),
                          // 头像容器
                          Container(
                            width: 128,
                            height: 128,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: ThemeHelper.surface(context),
                                width: 4,
                              ),
                              color: ThemeHelper.surfaceLight(context),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: _buildAvatarPreview(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // 选择图片按钮
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _pickImage,
                      icon: const Icon(Icons.photo_camera, size: 18),
                      label: ScaledText(AppLocalizations.of(context)!.selectImage),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ThemeHelper.primary(context).withValues(alpha: 0.1),
                        foregroundColor: ThemeHelper.primary(context),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: ThemeHelper.primary(context).withValues(alpha: 0.2),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ScaledText(
                      AppLocalizations.of(context)!.avatarPreview,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white.withValues(alpha: 0.3),
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 表单
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 昵称输入
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.badge,
                            size: 18,
                            color: ThemeHelper.primary(context),
                          ),
                          const SizedBox(width: 8),
                          ScaledText(
                            AppLocalizations.of(context)!.nickname,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _nicknameController,
                        decoration: InputDecoration(
                          hintText: AppLocalizations.of(context)!.pleaseEnterNickname,
                        ),
                        maxLength: 20,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return AppLocalizations.of(context)!.pleaseEnterNickname;
                          }
                          return null;
                        },
                        onChanged: (value) {
                          setState(() {
                            _error = null;
                          });
                        },
                      ),
                      const SizedBox(height: 4),
                      ScaledText(
                        AppLocalizations.of(context)!.max20Chars,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // 邮箱输入（可选）
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.email,
                            size: 18,
                            color: ThemeHelper.primary(context),
                          ),
                          const SizedBox(width: 8),
                          ScaledText(
                            'Email',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _emailController,
                        decoration: InputDecoration(
                          hintText: AppLocalizations.of(context)!.enterEmailOptional,
                        ),
                        keyboardType: TextInputType.emailAddress,
                        enabled: !_isLoading,
                        validator: (value) {
                          // 如果输入了邮箱，则验证格式；如果不输入，则通过验证
                          if (value != null && value.trim().isNotEmpty) {
                            if (!_isValidEmail(value.trim())) {
                              return AppLocalizations.of(context)!.pleaseEnterValidEmail;
                            }
                          }
                          return null;
                        },
                        onChanged: (value) {
                          setState(() {
                            _error = null;
                          });
                        },
                      ),
                      const SizedBox(height: 4),
                      ScaledText(
                        AppLocalizations.of(context)!.emailOptionalInfo,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // 错误提示
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ThemeHelper.expenseColor(context).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ThemeHelper.expenseColor(context).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error, color: ThemeHelper.expenseColor(context), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ScaledText(
                          _error!,
                          style: TextStyle(color: ThemeHelper.expenseColor(context), fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 24),

              // 保存按钮
              ElevatedButton.icon(
                onPressed: (_isLoading || _nicknameController.text.trim().isEmpty)
                    ? null
                    : _saveProfile,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: ScaledText(_isLoading ? AppLocalizations.of(context)!.saving : AppLocalizations.of(context)!.saveChanges),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // 提示信息
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: ThemeHelper.surface(context).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info,
                      color: ThemeHelper.primary(context),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ScaledText(
                            AppLocalizations.of(context)!.tip,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ScaledText(
                            AppLocalizations.of(context)!.profileUpdateInfo,
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
            ],
          ),
        ),
      ),
    );
  }
}