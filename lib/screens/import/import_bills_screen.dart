import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../../services/api/bill_service.dart';
import '../../models/bill_platform.dart';
import '../../models/bill_upload_result.dart';
import '../../models/bill_import_result.dart';
import '../../models/bill_task_status.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/custom_snackbar.dart';
import '../../widgets/common/scaled_text.dart';
import '../../utils/theme_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../l10n/app_localizations.dart';

enum ImportStep {
  platformList, // 选择平台
  uploadPreview, // 预览数据
  importResult, // 导入结果
  processing, // 异步处理中
}

class ImportBillsScreen extends StatefulWidget {
  const ImportBillsScreen({super.key});

  @override
  State<ImportBillsScreen> createState() => _ImportBillsScreenState();
}

class _ImportBillsScreenState extends State<ImportBillsScreen> with SingleTickerProviderStateMixin {
  final BillService _billService = BillService();
  
  ImportStep _currentStep = ImportStep.platformList;
  bool _isLoading = false;
  String? _error;
  
  List<BillPlatform> _platforms = [];
  BillUploadResult? _uploadResult;
  BillImportResult? _importResult;
  
  // 异步任务相关
  String? _currentTaskId;
  BillTaskFullStatus? _currentTaskStatus;
  Timer? _pollingTimer;
  int _pollingCount = 0;
  static const int _maxPollingCount = 30;
  static const int _pollingInterval = 3000; // 3秒
  TaskType? _currentTaskType;
  String? _billUploadId; // 保存从task中获取的billUploadId
  
  // 动画相关
  late AnimationController _animationController;
  late Animation<double> _progressAnimation;
  double _targetProgress = 0.0;
  double _currentAnimationValue = 0.0;
  
  @override
  void initState() {
    super.initState();
    _loadPlatforms();
    
    // 初始化动画控制器
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    
    // 创建进度动画（平滑过渡）
    _progressAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );
  }
  
  @override
  void dispose() {
    // 取消轮询
    _pollingTimer?.cancel();
    // 释放动画资源
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadPlatforms() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final platforms = await _billService.getSupportedPlatforms();
      if (mounted) {
        setState(() {
          _platforms = platforms;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _selectFile(BillPlatform platform) async {
    try {
      FilePickerResult? result;
      
      if (kIsWeb) {
        // Web平台：必须使用withData: true来获取bytes
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: platform.supportedFormats,
          withData: true, // Web平台必须使用withData
        );
      } else {
        // 移动平台：不使用withData，避免Platform._operatingSystem错误
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: platform.supportedFormats,
          withData: false, // 移动平台不使用withData
        );
      }

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.single;
        
        if (kIsWeb) {
          // Web平台：必须使用bytes
          if (file.bytes != null && file.bytes!.isNotEmpty) {
            await _uploadAndParseFile(platform.code, file);
          } else {
            throw Exception(AppLocalizations.of(context)!.cannotGetFileData);
          }
        } else {
          // 移动平台：优先使用bytes（更安全），如果没有bytes则尝试path
          if (file.bytes != null && file.bytes!.isNotEmpty) {
            // 优先使用bytes，避免访问path可能导致的错误
            await _uploadAndParseFile(platform.code, file);
          } else {
            // 尝试使用path（需要安全访问）
            try {
              final path = file.path;
              if (path != null && path.isNotEmpty) {
                await _uploadAndParseFile(platform.code, file);
              } else {
                throw Exception(AppLocalizations.of(context)!.cannotGetFileData);
              }
            } catch (e) {
              // 如果访问path失败，抛出错误
              if (e.toString().contains("path' is unavailable")) {
                throw Exception(AppLocalizations.of(context)!.fileSelectionFailedPleaseReselect);
              }
              rethrow;
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = AppLocalizations.of(context)!.fileSelectionFailed;
        final errorStr = e.toString();
        
        if (errorStr.contains('Platform._operatingSystem')) {
          errorMessage = AppLocalizations.of(context)!.fileSelectionNotSupported;
        } else if (errorStr.contains("path' is unavailable")) {
          errorMessage = AppLocalizations.of(context)!.fileSelectionFailedPleaseRetry;
        } else if (errorStr.contains('Permission') || errorStr.contains('权限')) {
          errorMessage = AppLocalizations.of(context)!.needFileAccessPermission;
        } else if (errorStr.contains('User cancelled') || errorStr.contains('取消')) {
          // 用户取消，不显示错误
          return;
        } else {
          errorMessage = errorStr.replaceFirst('Exception: ', '').replaceFirst('文件选择失败：', '');
        }
        
        CustomSnackBar.showError(context, errorMessage);
      }
    }
  }

  Future<void> _uploadAndParseFile(String platform, PlatformFile file) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _currentStep = ImportStep.processing;
      _currentTaskType = TaskType.uploadParse;
    });

    try {
      late BillTaskResponse taskResponse;
      
      // 优先使用 bytes（Web 平台和移动平台都可以使用）
      if (file.bytes != null && file.bytes!.isNotEmpty) {
        taskResponse = await _billService.uploadAndParseBillWithBytesAsync(
          bytes: file.bytes!,
          fileName: file.name,
          platform: platform,
        );
      } else if (!kIsWeb) {
        // 移动平台：尝试使用 path（仅在非Web平台）
        try {
          final path = file.path;
          if (path != null && path.isNotEmpty) {
            taskResponse = await _billService.uploadAndParseBillAsync(
              file: File(path),
              platform: platform,
            );
          } else {
            throw Exception(AppLocalizations.of(context)!.filePathUnavailable);
          }
        } catch (e) {
          // 如果path访问失败，尝试使用bytes（如果有）
          if (file.bytes != null && file.bytes!.isNotEmpty) {
            taskResponse = await _billService.uploadAndParseBillWithBytesAsync(
              bytes: file.bytes!,
              fileName: file.name,
              platform: platform,
            );
          } else {
            throw Exception('${AppLocalizations.of(context)!.fileDataUnavailable}：${e.toString()}');
          }
        }
      } else {
        throw Exception(AppLocalizations.of(context)!.fileDataUnavailable);
      }

      if (mounted) {
        setState(() {
          _currentTaskId = taskResponse.taskId;
        });
        // 启动轮询
        _startPolling();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
          _currentStep = ImportStep.platformList;
        });
      }
    }
  }

  Future<void> _confirmImport() async {
    if (_uploadResult == null) return;
    
    // 检查billUploadId是否存在
    final billUploadId = _billUploadId;
    if (billUploadId == null || billUploadId.isEmpty) {
        if (mounted) {
          CustomSnackBar.showError(context, AppLocalizations.of(context)!.billUploadIdCannotBeEmpty);
        }
        return;
      }

    setState(() {
      _isLoading = true;
      _error = null;
      _currentStep = ImportStep.processing;
      _currentTaskType = TaskType.import;
    });

    try {
      late BillTaskResponse taskResponse;
      taskResponse = await _billService.importTransactionsAsync(
        billUploadId: billUploadId,
        skipDuplicates: true,
        autoMatchCategory: true,
      );

      if (mounted) {
        setState(() {
          _currentTaskId = taskResponse.taskId;
        });
        // 启动轮询
        _startPolling();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
          _currentStep = ImportStep.uploadPreview;
        });
        CustomSnackBar.showError(context, e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  void _reset() {
    // 取消轮询
    _pollingTimer?.cancel();
    setState(() {
      _currentStep = ImportStep.platformList;
      _uploadResult = null;
      _importResult = null;
      _error = null;
      _currentTaskId = null;
      _currentTaskStatus = null;
      _currentTaskType = null;
      _billUploadId = null; // 清空billUploadId
      // 重置动画进度
      _targetProgress = 0.0;
      _currentAnimationValue = 0.0;
    });
  }
  
  // 启动轮询
  void _startPolling() {
    // 取消之前的轮询
    _pollingTimer?.cancel();
    _pollingCount = 0;
    
    // 立即执行一次
    _pollTaskStatus();
    
    // 设置定时器
    _pollingTimer = Timer.periodic(const Duration(milliseconds: _pollingInterval), (timer) {
      _pollTaskStatus();
    });
  }
  
  // 轮询任务状态
  Future<void> _pollTaskStatus() async {
    if (_currentTaskId == null) return;
    
    try {
      _pollingCount++;
      
      final taskStatus = await _billService.getTaskStatus(taskId: _currentTaskId!);
      
      if (mounted) {
        setState(() {
          _currentTaskStatus = taskStatus;
        });
        
        // 更新目标进度并触发动画
        final newProgress = taskStatus.task.progress / 100;
        if (newProgress != _targetProgress) {
          setState(() {
            _targetProgress = newProgress;
          });
          
          // 触发进度动画
          _progressAnimation = Tween<double>(
            begin: _currentAnimationValue,
            end: _targetProgress,
          ).animate(
            CurvedAnimation(
              parent: _animationController,
              curve: Curves.easeInOut,
            ),
          );
          
          _animationController.forward(from: 0);
        }
        
        // 如果任务正在处理中，启动脉动动画
        final status = TaskStatus.fromValue(taskStatus.task.status);
        if (status == TaskStatus.processing && !_animationController.isAnimating) {
          _animationController.forward();
        }
        
        // 检查任务状态
        if (status == TaskStatus.success || status == TaskStatus.failed || _pollingCount >= _maxPollingCount) {
          // 任务完成或超时，停止轮询
          _stopPolling();
          
          if (_pollingCount >= _maxPollingCount) {
            // 超时
            setState(() {
              _error = AppLocalizations.of(context)!.processingTimeoutPleaseRetry;
              _isLoading = false;
              _currentStep = _currentTaskType == TaskType.uploadParse ? ImportStep.platformList : ImportStep.uploadPreview;
            });
            CustomSnackBar.showError(context, AppLocalizations.of(context)!.processingTimeoutPleaseRetry);
          } else if (status == TaskStatus.success) {
            // 任务成功
            if (_currentTaskType == TaskType.uploadParse) {
              // 上传解析成功，获取预览数据
              await _handleUploadParseSuccess(taskStatus);
            } else if (_currentTaskType == TaskType.import) {
              // 导入成功，处理导入结果
              await _handleImportSuccess(taskStatus);
            }
          } else if (status == TaskStatus.failed) {
            // 任务失败
            setState(() {
              _error = AppLocalizations.of(context)!.processingFailed;
              _isLoading = false;
              _currentStep = _currentTaskType == TaskType.uploadParse ? ImportStep.platformList : ImportStep.uploadPreview;
            });
            CustomSnackBar.showError(context, AppLocalizations.of(context)!.processingFailed);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        _stopPolling();
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
          _currentStep = _currentTaskType == TaskType.uploadParse ? ImportStep.platformList : ImportStep.uploadPreview;
        });
        CustomSnackBar.showError(context, '${AppLocalizations.of(context)!.queryTaskStatusFailed}：${e.toString()}');
      }
    }
  }
  
  // 停止轮询
  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }
  
  // 处理上传解析成功
  Future<void> _handleUploadParseSuccess(BillTaskFullStatus taskStatus) async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // 使用解析结果直接更新状态
      if (mounted) {
        setState(() {
          _isLoading = false;
          _currentStep = ImportStep.uploadPreview;
          _uploadResult = taskStatus.parseResult;
          // 从task对象中获取billUploadId并保存
          _billUploadId = taskStatus.task.billUploadId;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
          _currentStep = ImportStep.platformList;
        });
        CustomSnackBar.showError(context, '${AppLocalizations.of(context)!.getPreviewDataFailed}：${e.toString()}');
      }
    }
  }
  
  // 处理导入成功
  Future<void> _handleImportSuccess(BillTaskFullStatus taskStatus) async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // 解析失败原因
      List<BillImportError> errors = [];
      final errorMessage = taskStatus.task.errorMessage;
      if (errorMessage != null && errorMessage.isNotEmpty) {
        try {
          final List<dynamic> errorList = json.decode(errorMessage);
          errors = errorList.map((error) {
            final errorMap = error as Map<String, dynamic>;
            return BillImportError(
              reason: errorMap['reason'] as String? ?? '',
              rawData: errorMap['rawData'] as String?,
            );
          }).toList();
        } catch (e) {
          // 如果解析失败，将整个errorMessage作为一个错误
          errors = [
            BillImportError(reason: errorMessage)
          ];
        }
      }
      
      setState(() {
        _isLoading = false;
        _currentStep = ImportStep.importResult;
        _importResult = BillImportResult(
          successCount: taskStatus.task.successCount,
          failCount: taskStatus.task.failCount,
          skipCount: 0,
          totalCount: taskStatus.task.totalCount,
          transactionIds: [],
          errors: errors,
        );
      });
      CustomSnackBar.showSuccess(
        context,
        AppLocalizations.of(context)!.importCompleted,
      );
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
        _currentStep = ImportStep.uploadPreview;
      });
      CustomSnackBar.showError(context, '${AppLocalizations.of(context)!.getImportResultFailed}：${e.toString()}');
    }
  }
  
  // 构建处理中视图
  Widget _buildProcessingView() {
    if (_currentTaskStatus == null) {
      return LoadingIndicator(message: AppLocalizations.of(context)!.initializingTask);
    }
    
    final status = TaskStatus.fromValue(_currentTaskStatus!.task.status);
    final taskType = _currentTaskType ?? TaskType.uploadParse;
    
    return Center(
      child: Padding(
        padding: ResponsiveHelper.containerMargin(context),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 任务图标
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: ThemeHelper.primary(context).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(40),
              ),
              child: Icon(
                status == TaskStatus.processing 
                    ? Icons.refresh 
                    : status == TaskStatus.success 
                        ? Icons.check 
                        : Icons.error,
                size: 48,
                color: ThemeHelper.primary(context),
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, small: 24, normal: 32)),
            
            // 任务标题
            ScaledText(
              '${taskType.label}${AppLocalizations.of(context)!.inProgress}',
              style: ResponsiveHelper.responsiveTextStyle(
                context,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, small: 8, normal: 12)),
            
            // 任务状态
            ScaledText(
              status.label,
              style: ResponsiveHelper.responsiveTextStyle(
                context,
                color: Colors.white70,
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, small: 32, normal: 48)),
            
            // 进度条
            Container(
              width: double.infinity,
              padding: ResponsiveHelper.containerMargin(context),
              child: Column(
                children: [
                  // 进度百分比
                  AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      // 更新当前动画值
                      _currentAnimationValue = _progressAnimation.value;
                      final animatedProgress = (_currentAnimationValue * 100).round();
                      return ScaledText(
                        '$animatedProgress%',
                        style: ResponsiveHelper.responsiveTextStyle(
                          context,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, small: 16, normal: 24)),
                  
                  // 进度条
                  AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      // 更新当前动画值
                      _currentAnimationValue = _progressAnimation.value;
                      return LinearProgressIndicator(
                        value: _currentAnimationValue,
                        minHeight: 8,
                        backgroundColor: Colors.white.withValues(alpha: 0.1),
                        valueColor: ColorTween(
                          begin: ThemeHelper.primary(context).withValues(alpha: 0.8),
                          end: ThemeHelper.primary(context),
                        ).animate(
                          CurvedAnimation(
                            parent: _animationController,
                            curve: Curves.easeInOut,
                          ),
                        ),
                        borderRadius: BorderRadius.circular(4),
                      );
                    },
                  ),
                ],
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, small: 32, normal: 48)),
            
            // 统计信息
            if (_currentTaskStatus!.task.totalCount > 0) 
              Container(
                padding: ResponsiveHelper.cardPadding(context),
                decoration: BoxDecoration(
                  color: ThemeHelper.surface(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Column(
                  children: [
                    _buildStatRow(AppLocalizations.of(context)!.totalRecords, '${_currentTaskStatus!.task.totalCount}'),
                    _buildStatRow(AppLocalizations.of(context)!.processed, '${_currentTaskStatus!.task.successCount + _currentTaskStatus!.task.failCount}'),
                    _buildStatRow(AppLocalizations.of(context)!.success, '${_currentTaskStatus!.task.successCount}', color: Colors.green),
                    _buildStatRow(AppLocalizations.of(context)!.fail, '${_currentTaskStatus!.task.failCount}', color: ThemeHelper.expenseColor(context)),
                  ],
                ),
              ),
            SizedBox(height: ResponsiveHelper.spacing(context, small: 32, normal: 48)),
            
            // 错误信息
            if (status == TaskStatus.failed) 
              ScaledText(
                AppLocalizations.of(context)!.processingFailed,
                style: ResponsiveHelper.responsiveTextStyle(
                  context,
                  color: ThemeHelper.expenseColor(context),
                ),
                textAlign: TextAlign.center,
              ),
            
            // 取消按钮
            if (status == TaskStatus.processing) 
              TextButton(
                onPressed: () {
                  _stopPolling();
                  _reset();
                },
                style: TextButton.styleFrom(
                  overlayColor: Colors.transparent,
                  splashFactory: NoSplash.splashFactory,
                ),
                child: ScaledText(AppLocalizations.of(context)!.cancel),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ScaledText(AppLocalizations.of(context)!.billImport),
        actions: _currentStep != ImportStep.platformList
            ? [
                TextButton(
                  onPressed: _reset,
                  style: TextButton.styleFrom(
                    overlayColor: Colors.transparent,
                    splashFactory: NoSplash.splashFactory,
                  ),
                  child: ScaledText(AppLocalizations.of(context)!.retry),
                ),
              ]
            : null,
      ),
      body: SafeArea(
        child: _isLoading && _currentStep == ImportStep.platformList
            ? LoadingIndicator(message: AppLocalizations.of(context)!.loading)
            : _error != null && _currentStep == ImportStep.platformList
                ? _buildErrorView()
                : _buildContent(),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: ResponsiveHelper.containerMargin(context),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: ThemeHelper.expenseColor(context),
            ),
            const SizedBox(height: 16),
            ScaledText(
              AppLocalizations.of(context)!.error,
              style: ResponsiveHelper.responsiveTitleStyle(context),
            ),
            const SizedBox(height: 8),
            ScaledText(
              _error ?? AppLocalizations.of(context)!.unknown,
              style: ResponsiveHelper.responsiveTextStyle(
                context,
                color: Colors.white70,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadPlatforms,
              style: ElevatedButton.styleFrom(
                overlayColor: Colors.transparent,
                splashFactory: NoSplash.splashFactory,
              ),
              child: ScaledText(AppLocalizations.of(context)!.retry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_currentStep) {
      case ImportStep.platformList:
        return _buildPlatformList();
      case ImportStep.uploadPreview:
        return _buildPreviewView();
      case ImportStep.importResult:
        return _buildImportResultView();
      case ImportStep.processing:
        return _buildProcessingView();
    }
  }

  Widget _buildPlatformList() {
    return SingleChildScrollView(
      padding: ResponsiveHelper.containerMargin(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: ResponsiveHelper.spacing(context, small: 24, normal: 32, large: 40)),
          ScaledText(
            AppLocalizations.of(context)!.billImport,
            style: ResponsiveHelper.responsiveTitleStyle(
              context,
              color: Colors.white,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, small: 6, normal: 8)),
          ScaledText(
            AppLocalizations.of(context)!.billImportSubtitle,
            style: ResponsiveHelper.responsiveTextStyle(
              context,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, small: 32, normal: 48, large: 56)),
          if (_platforms.isEmpty)
            Center(
              child: ScaledText(
                AppLocalizations.of(context)!.noData,
                style: ResponsiveHelper.responsiveTextStyle(
                  context,
                  color: Colors.white70,
                ),
              ),
            )
          else
            ..._platforms.map((platform) => Padding(
                  padding: EdgeInsets.only(
                    bottom: ResponsiveHelper.spacing(context),
                  ),
                  child: _buildPlatformCard(platform),
                )),
          SizedBox(height: ResponsiveHelper.spacing(context, small: 24, normal: 32, large: 40)),
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              color: ThemeHelper.surface(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: ResponsiveHelper.iconSize(context, defaultSize: 20),
                      color: Colors.white70,
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, small: 6, normal: 8)),
                    ScaledText(
                      AppLocalizations.of(context)!.tip,
                      style: ResponsiveHelper.responsiveTextStyle(
                        context,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, small: 6, normal: 8)),
                ScaledText(
                  '1. ${AppLocalizations.of(context)!.billImport}\n2. ${AppLocalizations.of(context)!.selectCategory}\n3. ${AppLocalizations.of(context)!.billImport}\n4. ${AppLocalizations.of(context)!.confirmAdd}',
                  style: ResponsiveHelper.responsiveTextStyle(
                    context,
                    fontSize: ResponsiveHelper.responsiveValue(
                      context,
                      small: 11.0,
                      normal: 12.0,
                      large: 13.0,
                    ),
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlatformCard(BillPlatform platform) {
    IconData icon;
    switch (platform.code) {
      case 'alipay':
        icon = Icons.account_balance_wallet;
        break;
      case 'wechat':
        icon = Icons.wechat;
        break;
      case 'cmb':
        icon = Icons.account_balance;
        break;
      default:
        icon = Icons.receipt;
    }

    return InkWell(
      onTap: () => _selectFile(platform),
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: ThemeHelper.surface(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: ThemeHelper.primary(context).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: ThemeHelper.primary(context),
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ScaledText(
                    platform.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ScaledText(
                    '${AppLocalizations.of(context)!.supportedFormats}${platform.supportedFormats.join(', ').toUpperCase()}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewView() {
    if (_isLoading) {
      return LoadingIndicator(message: AppLocalizations.of(context)!.parsingBillFile);
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: ResponsiveHelper.containerMargin(context),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: ThemeHelper.expenseColor(context),
              ),
              const SizedBox(height: 16),
              ScaledText(
              AppLocalizations.of(context)!.error,
              style: ResponsiveHelper.responsiveTitleStyle(context),
            ),
            const SizedBox(height: 8),
            ScaledText(
              _error ?? AppLocalizations.of(context)!.unknown,
              style: ResponsiveHelper.responsiveTextStyle(
                context,
                color: Colors.white70,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _reset,
              style: ElevatedButton.styleFrom(
                overlayColor: Colors.transparent,
                splashFactory: NoSplash.splashFactory,
              ),
              child: ScaledText(AppLocalizations.of(context)!.back),
            ),
            ],
          ),
        ),
      );
    }

    if (_uploadResult == null) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      padding: ResponsiveHelper.containerMargin(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: ResponsiveHelper.spacing(context, small: 16, normal: 24)),
          // 统计信息
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              color: ThemeHelper.surface(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ScaledText(
                  AppLocalizations.of(context)!.successfullySaved,
                  style: ResponsiveHelper.responsiveTextStyle(
                    context,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 16),
                _buildStatRow(AppLocalizations.of(context)!.platform, _uploadResult!.platform),
                _buildStatRow(AppLocalizations.of(context)!.total, '${_uploadResult!.totalCount}'),
                _buildStatRow(AppLocalizations.of(context)!.success, '${_uploadResult!.successCount}',
                    color: Colors.green),
                if (_uploadResult!.errorCount > 0)
                  _buildStatRow(AppLocalizations.of(context)!.error, '${_uploadResult!.errorCount}',
                      color: ThemeHelper.expenseColor(context)),
                if (_uploadResult!.metadata != null && _uploadResult!.metadata!.dateRange != null)
                  _buildStatRow(
                    AppLocalizations.of(context)!.date,
                    '${_uploadResult!.metadata!.dateRange!.start} ${AppLocalizations.of(context)!.to} ${_uploadResult!.metadata!.dateRange!.end}',
                  ),
                if (_uploadResult!.metadata != null && _uploadResult!.metadata!.totalAmount != null)
                  _buildStatRow(
                    AppLocalizations.of(context)!.totalAmount,
                    '¥${_uploadResult!.metadata!.totalAmount!.toStringAsFixed(2)}',
                  ),
              ],
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context)),
          // 错误列表
          if (_uploadResult!.errors.isNotEmpty) ...[
            Container(
              padding: ResponsiveHelper.cardPadding(context),
              decoration: BoxDecoration(
                color: ThemeHelper.expenseColor(context).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: ThemeHelper.expenseColor(context).withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: ThemeHelper.expenseColor(context),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      ScaledText(
                      '${AppLocalizations.of(context)!.error} (${_uploadResult!.errors.length}${AppLocalizations.of(context)!.transactions})',
                      style: ResponsiveHelper.responsiveTextStyle(
                        context,
                        fontWeight: FontWeight.bold,
                        color: ThemeHelper.expenseColor(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ..._uploadResult!.errors.take(5).map((error) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ScaledText(
                        '${AppLocalizations.of(context)!.row} ${error.row}: ${error.reason}',
                        style: ResponsiveHelper.responsiveTextStyle(
                          context,
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                    )),
                ],
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context)),
          ],
          // 预览数据
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              color: ThemeHelper.surface(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ScaledText(
                  '${AppLocalizations.of(context)!.previewData} (${AppLocalizations.of(context)!.total}${_uploadResult!.preview.length}${AppLocalizations.of(context)!.items})',
                  style: ResponsiveHelper.responsiveTextStyle(
                    context,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: ResponsiveHelper.responsiveValue(
                    context,
                    small: 300.0,
                    normal: 400.0,
                    large: 500.0,
                  ),
                  child: ListView.builder(
                    itemCount: _uploadResult!.preview.length,
                    itemBuilder: (context, index) {
                      return _buildPreviewItem(_uploadResult!.preview[index]);
                    },
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, small: 24, normal: 32)),
          // 确认按钮（仅在successCount > 0时显示）
          if (_uploadResult!.successCount > 0)
            ElevatedButton(
              onPressed: _confirmImport,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: ThemeHelper.primary(context),
                overlayColor: Colors.transparent,
                splashFactory: NoSplash.splashFactory,
              ),
              child: ScaledText(
                AppLocalizations.of(context)!.confirmImport,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),
          SizedBox(height: ResponsiveHelper.spacing(context)),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ScaledText(
            label,
            style: ResponsiveHelper.responsiveTextStyle(
              context,
              color: Colors.white70,
            ),
          ),
          ScaledText(
            value,
            style: ResponsiveHelper.responsiveTextStyle(
              context,
              fontWeight: FontWeight.bold,
              color: color ?? Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewItem(BillPreviewItem item) {
    final dateFormat = DateFormat('yyyy-MM-dd');
    DateTime? date;
    try {
      date = DateTime.parse(item.date);
    } catch (e) {
      // 忽略日期解析错误
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ThemeHelper.surfaceDark(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: ScaledText(
                        item.description ?? item.category ?? AppLocalizations.of(context)!.unknown,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ScaledText(
                      '¥${item.amount.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: item.type == 0
                            ? Colors.green
                            : ThemeHelper.expenseColor(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (date != null)
                      ScaledText(
                        dateFormat.format(date),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    if (date != null && item.counterparty != null)
                      ScaledText(
                        ' • ',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    if (item.counterparty != null)
                      Expanded(
                        child: ScaledText(
                          item.counterparty!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
        ],
      ),
    );
  }

  Widget _buildImportResultView() {
    if (_isLoading) {
      return LoadingIndicator(message: AppLocalizations.of(context)!.importingTransactions);
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: ResponsiveHelper.containerMargin(context),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: ThemeHelper.expenseColor(context),
              ),
              const SizedBox(height: 16),
              ScaledText(
                AppLocalizations.of(context)!.importFailed,
                style: ResponsiveHelper.responsiveTitleStyle(context),
              ),
              const SizedBox(height: 8),
              ScaledText(
                _error ?? AppLocalizations.of(context)!.unknownError,
                style: ResponsiveHelper.responsiveTextStyle(
                  context,
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _reset,
                style: ElevatedButton.styleFrom(
                  overlayColor: Colors.transparent,
                  splashFactory: NoSplash.splashFactory,
                ),
                child: ScaledText(AppLocalizations.of(context)!.back),
              ),
            ],
          ),
        ),
      );
    }

    if (_importResult == null) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      padding: ResponsiveHelper.containerMargin(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: ResponsiveHelper.spacing(context, small: 32, normal: 48)),
          // 成功图标
          const Icon(
            Icons.check_circle,
            size: 80,
            color: Colors.green,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, small: 16, normal: 24)),
          ScaledText(
            AppLocalizations.of(context)!.importCompleted,
            style: ResponsiveHelper.responsiveTextStyle(
              context,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, small: 32, normal: 48)),
          // 统计信息
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              color: ThemeHelper.surface(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ScaledText(
                  AppLocalizations.of(context)!.importResult,
                  style: ResponsiveHelper.responsiveTextStyle(
                    context,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 16),
                _buildStatRow(AppLocalizations.of(context)!.totalRecords, '${_importResult!.totalCount}'),
                _buildStatRow(AppLocalizations.of(context)!.successfullyImported, '${_importResult!.successCount}',
                    color: Colors.green),
                if (_importResult!.skipCount > 0)
                  _buildStatRow(AppLocalizations.of(context)!.skippedDuplicate, '${_importResult!.skipCount}',
                      color: Colors.orange),
                if (_importResult!.failCount > 0)
                  _buildStatRow(AppLocalizations.of(context)!.importFailed, '${_importResult!.failCount}',
                      color: ThemeHelper.expenseColor(context)),
              ],
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, small: 24, normal: 32)),
          // 失败原因列表
          if (_importResult!.errors.isNotEmpty) ...[
            Container(
              padding: ResponsiveHelper.cardPadding(context),
              decoration: BoxDecoration(
                color: ThemeHelper.expenseColor(context).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: ThemeHelper.expenseColor(context).withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: ThemeHelper.expenseColor(context),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      ScaledText(
                        '${AppLocalizations.of(context)!.importFailedReason} (${_importResult!.errors.length}${AppLocalizations.of(context)!.items})',
                        style: ResponsiveHelper.responsiveTextStyle(
                          context,
                          fontWeight: FontWeight.bold,
                          color: ThemeHelper.expenseColor(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ..._importResult!.errors.take(10).map((error) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (error.row != null)
                              ScaledText(
                                '${AppLocalizations.of(context)!.row} ${error.row}',
                                style: ResponsiveHelper.responsiveTextStyle(
                                  context,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: ThemeHelper.expenseColor(context),
                                ),
                              ),
                            ScaledText(
                              error.reason,
                              style: ResponsiveHelper.responsiveTextStyle(
                                context,
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            ),
                            if (error.rawData != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: ScaledText(
                                  '${AppLocalizations.of(context)!.rawData}: ${error.rawData}',
                                  style: ResponsiveHelper.responsiveTextStyle(
                                    context,
                                    fontSize: 11,
                                    color: Colors.white54,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      )),
                  if (_importResult!.errors.length > 10)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: ScaledText(
                        (AppLocalizations.of(context)!.showingFirst10 as String).replaceAll('{count}', '${_importResult!.errors.length}'),
                        style: ResponsiveHelper.responsiveTextStyle(
                          context,
                          fontSize: 12,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, small: 24, normal: 32)),
          ],
          // 操作按钮
          ElevatedButton(
            onPressed: () {
              context.pushReplacement('/home');
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: ThemeHelper.primary(context),
              overlayColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
            ),
            child: ScaledText(
                AppLocalizations.of(context)!.viewTransactions,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context)),
          TextButton(
            onPressed: _reset,
            style: TextButton.styleFrom(
              overlayColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
            ),
            child: ScaledText(AppLocalizations.of(context)!.continueImport),
          ),
        ],
      ),
    );
  }
}
