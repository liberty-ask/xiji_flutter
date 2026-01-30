import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';

import 'package:image_picker/image_picker.dart';
import '../../utils/theme_helper.dart';

/// 图片选择结果回调（仅选择模式）
typedef ImagePickerCallback = void Function(XFile? file, String? previewPath);

/// 图片上传结果回调（自动上传模式）
typedef ImageUploadCallback = void Function(String? imageUrl);

/// 自定义上传函数类型
typedef ImageUploadFunction = Future<String> Function(XFile file);

/// 可复用的图片选择组件
/// 支持PC端和手机端，自动处理平台差异
/// 支持两种模式：
/// 1. 仅选择模式：只选择图片，返回文件，由调用方处理上传
/// 2. 自动上传模式：选择图片后自动上传，返回URL
class ImagePickerWidget extends StatefulWidget {
  /// 当前显示的图片（URL或base64）
  final String? initialImage;

  /// 图片选择回调（仅选择模式）
  final ImagePickerCallback? onImagePicked;

  /// 图片上传回调（自动上传模式）
  final ImageUploadCallback? onImageUploaded;

  /// 自定义上传函数（自动上传模式）
  /// 如果提供此函数，组件会在选择图片后自动调用上传
  final ImageUploadFunction? uploadFunction;

  /// 最大文件大小（字节），默认5MB
  final int maxFileSize;

  /// 图片最大宽度，默认1024
  final int maxWidth;

  /// 图片最大高度，默认1024
  final int maxHeight;

  /// 图片质量（0-100），默认85
  final int imageQuality;

  /// 头像大小，默认128
  final double avatarSize;

  /// 是否显示选择按钮
  final bool showPickButton;

  /// 选择按钮文本
  final String pickButtonText;

  /// 选择按钮图标
  final IconData? pickButtonIcon;

  /// 是否显示预览标签
  final bool showPreviewLabel;

  /// 预览标签文本
  final String previewLabelText;

  /// 是否禁用
  final bool disabled;

  /// 错误回调
  final ValueChanged<String>? onError;

  /// 上传中回调（自动上传模式）
  final ValueChanged<bool>? onUploading;

  const ImagePickerWidget({
    super.key,
    this.initialImage,
    this.onImagePicked,
    this.onImageUploaded,
    this.uploadFunction,
    this.maxFileSize = 5 * 1024 * 1024, // 5MB
    this.maxWidth = 1024,
    this.maxHeight = 1024,
    this.imageQuality = 85,
    this.avatarSize = 128,
    this.showPickButton = true,
    this.pickButtonText = '选择图片',
    this.pickButtonIcon,
    this.showPreviewLabel = false,
    this.previewLabelText = '头像预览',
    this.disabled = false,
    this.onError,
    this.onUploading,
  });

  @override
  State<ImagePickerWidget> createState() => _ImagePickerWidgetState();
}

class _ImagePickerWidgetState extends State<ImagePickerWidget> {
  final ImagePicker _imagePicker = ImagePicker();
  XFile? _selectedImageFile;
  String? _previewPath;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _previewPath = widget.initialImage;
  }

  @override
  void didUpdateWidget(ImagePickerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialImage != oldWidget.initialImage) {
      _previewPath = widget.initialImage;
      _selectedImageFile = null;
    }
  }

  /// 判断是否为自动上传模式
  bool get _isAutoUploadMode => widget.uploadFunction != null;

  /// 选择图片
  Future<void> _pickImage() async {
    if (widget.disabled) return;

    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: widget.maxWidth.toDouble(),
        maxHeight: widget.maxHeight.toDouble(),
        imageQuality: widget.imageQuality,
      );

      if (pickedFile != null) {
        try {
          // 读取文件字节以验证大小和生成预览
          final bytes = await pickedFile.readAsBytes();

          // 验证文件大小
          if (bytes.length > widget.maxFileSize) {
            final errorMsg = '图片大小不能超过${(widget.maxFileSize / 1024 / 1024).toStringAsFixed(0)}MB';
            if (widget.onError != null) {
              widget.onError!(errorMsg);
            } else if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(errorMsg)),
              );
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
              _previewPath = previewPath;
            });

            // 根据模式处理
            if (_isAutoUploadMode) {
              // 自动上传模式：上传文件并返回URL
              await _uploadImage(pickedFile);
            } else {
              // 仅选择模式：返回文件
              widget.onImagePicked?.call(pickedFile, previewPath);
            }
          }
        } catch (fileError) {
          // 处理文件操作错误
          final errorMsg = '处理图片文件失败: ${fileError.toString()}';
          if (widget.onError != null) {
            widget.onError!(errorMsg);
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(errorMsg)),
            );
          }
        }
      }
    } catch (e) {
      // 更友好的错误提示
      String errorMessage = '选择图片失败';
      if (e.toString().contains('Permission') || e.toString().contains('权限')) {
        errorMessage = '需要相册访问权限，请在设置中开启';
      } else if (e.toString().contains('User cancelled') || e.toString().contains('取消')) {
        // 用户取消选择，不显示错误
        return;
      } else {
        errorMessage = '选择图片失败，请重试';
      }

      if (widget.onError != null) {
        widget.onError!(errorMessage);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    }
  }

  /// 上传图片（自动上传模式）
  Future<void> _uploadImage(XFile file) async {
    if (widget.uploadFunction == null) return;

    setState(() {
      _isUploading = true;
    });
    widget.onUploading?.call(true);

    try {
      final imageUrl = await widget.uploadFunction!(file);
      
      if (mounted) {
        setState(() {
          _previewPath = imageUrl;
          _isUploading = false;
        });
        widget.onUploading?.call(false);
        widget.onImageUploaded?.call(imageUrl);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
        widget.onUploading?.call(false);
        
        final errorMsg = '上传图片失败: ${e.toString().replaceFirst('Exception: ', '')}';
        if (widget.onError != null) {
          widget.onError!(errorMsg);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorMsg)),
          );
        }
      }
    }
  }

  /// 构建图片预览
  Widget _buildImagePreview() {
    if (_previewPath == null || _previewPath!.isEmpty) {
      return Container(
        width: widget.avatarSize,
        height: widget.avatarSize,
        decoration: BoxDecoration(
          color: ThemeHelper.surfaceLight(context),
          borderRadius: BorderRadius.circular(widget.avatarSize * 0.2),
        ),
        child: Icon(
          Icons.person,
          size: widget.avatarSize * 0.5,
          color: Colors.white.withValues(alpha: 0.2),
        ),
      );
    }

    try {
      // 检查是否是base64格式（Web平台）
      if (_previewPath!.startsWith('data:image/')) {
        try {
          final parts = _previewPath!.split(',');
          if (parts.length > 1) {
            final base64String = parts[1];
            final bytes = base64Decode(base64String);
            return ClipRRect(
              borderRadius: BorderRadius.circular(widget.avatarSize * 0.2),
              child: Image.memory(
                bytes,
                width: widget.avatarSize,
                height: widget.avatarSize,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildDefaultIcon();
                },
              ),
            );
          }
        } catch (e) {
          // base64解码失败，显示默认图标
          return _buildDefaultIcon();
        }
      }

      // 检查是否是本地文件路径
      if (_selectedImageFile != null && _selectedImageFile!.path.isNotEmpty) {
        try {
          final file = File(_selectedImageFile!.path);
          return ClipRRect(
            borderRadius: BorderRadius.circular(widget.avatarSize * 0.2),
            child: Image.file(
              file,
              width: widget.avatarSize,
              height: widget.avatarSize,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                // 文件读取失败，尝试网络图片
                return _buildNetworkImage();
              },
            ),
          );
        } catch (e) {
          // 文件读取失败，继续尝试网络图片
        }
      }

      // 尝试作为网络URL显示
      return _buildNetworkImage();
    } catch (e) {
      // 所有方式都失败，显示默认图标
      return _buildDefaultIcon();
    }
  }

  Widget _buildNetworkImage() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.avatarSize * 0.2),
      child: Image.network(
        _previewPath!,
        width: widget.avatarSize,
        height: widget.avatarSize,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildDefaultIcon();
        },
      ),
    );
  }

  Widget _buildDefaultIcon() {
    return Container(
      width: widget.avatarSize,
      height: widget.avatarSize,
      decoration: BoxDecoration(
        color: ThemeHelper.surfaceLight(context),
        borderRadius: BorderRadius.circular(widget.avatarSize * 0.2),
      ),
      child: Icon(
        Icons.person,
        size: widget.avatarSize * 0.5,
        color: Colors.white.withValues(alpha: 0.2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 头像预览（带模糊背景效果）
        Container(
          alignment: Alignment.center,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 模糊背景效果
              Container(
                width: widget.avatarSize + 12,
                height: widget.avatarSize + 12,
                decoration: BoxDecoration(
                  shape: BoxShape.rectangle,
                  borderRadius: BorderRadius.circular(widget.avatarSize * 0.2 + 4),
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
                width: widget.avatarSize,
                height: widget.avatarSize,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.avatarSize * 0.2),
                  border: Border.all(
                    color: ThemeHelper.surface(context),
                    width: 4,
                  ),
                  color: ThemeHelper.surfaceLight(context),
                ),
                child: _buildImagePreview(),
              ),
            ],
          ),
        ),
        if (widget.showPickButton) ...[
          const SizedBox(height: 24),
          // 选择图片按钮
          ElevatedButton.icon(
            onPressed: (widget.disabled || _isUploading) ? null : _pickImage,
            icon: _isUploading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        ThemeHelper.primary(context),
                      ),
                    ),
                  )
                : Icon(
                    widget.pickButtonIcon ?? Icons.photo_camera,
                    size: 18,
                  ),
            label: Text(_isUploading ? '上传中...' : widget.pickButtonText),
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
        ],
        if (widget.showPreviewLabel) ...[
          const SizedBox(height: 8),
          Text(
            widget.previewLabelText,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white.withValues(alpha: 0.3),
              letterSpacing: 2,
            ),
          ),
        ],
      ],
    );
  }

  /// 获取当前选择的文件
  XFile? get selectedFile => _selectedImageFile;

  /// 获取当前预览路径
  String? get previewPath => _previewPath;
}

