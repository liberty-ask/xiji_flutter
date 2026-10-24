import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../data/local/category_rule_loader.dart';
import '../../data/local/db_provider.dart';
import '../../data/local/voice_transaction_parser.dart';
import '../../services/api/transaction_service.dart';
import '../home/add_transaction_screen.dart';
import '../settings/backup_guidance.dart';
import '../../widgets/common/custom_snackbar.dart';
import '../../utils/theme_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/error_helper.dart';
import '../../widgets/common/scaled_text.dart';
import '../../l10n/app_localizations.dart';

/// 半圆形裁剪器
class HalfCircleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, size.height);
    path.quadraticBezierTo(size.width / 2, 0, size.width, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) {
    return false;
  }
}

class VoiceTransactionScreen extends StatefulWidget {
  const VoiceTransactionScreen({super.key});

  @override
  State<VoiceTransactionScreen> createState() => _VoiceTransactionScreenState();
}

class _VoiceTransactionScreenState extends State<VoiceTransactionScreen>
    with SingleTickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _isListening = false;
  bool _isSpeechAvailable = false;
  bool _isSubmitting = false;
  bool _showActionButtons = false;
  bool _showEditScreen = false;
  String _recognizedText = '';
  // 最近一次识别层错误（release 也用于用户提示）
  String? _lastSpeechError;
  String _editingText = '';
  late TextEditingController _textEditingController;
  // 记录手指是否在取消或编辑按钮区域
  bool _isInCancelButtonArea = false;
  bool _isInEditButtonArea = false;

  // 脉冲动画控制器
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    // 初始化脉冲动画
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );

    // 初始化文本编辑控制器
    _textEditingController = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeSpeech();
      _requestMicrophonePermission();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _speech.stop();
    _speech.cancel();
    _textEditingController.dispose();
    super.dispose();
  }

  /// 初始化语音识别服务（不请求权限，仅检查服务是否可用）
  Future<void> _initializeSpeech() async {
    try {
      // 不请求权限，只检查服务是否可用（如果有权限的话）
      _isSpeechAvailable = await _speech.initialize(
        onError: (error) {
          _lastSpeechError = error.errorMsg;
          if (kDebugMode) {
            debugPrint('语音识别错误: ${error.errorMsg}');
          }
        },
        onStatus: (status) {
          if (kDebugMode) {
            debugPrint('语音识别状态: $status');
          }
        },
      );
      if (kDebugMode) {
        debugPrint('语音识别服务初始化结果: $_isSpeechAvailable');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('初始化语音识别失败: $e');
      }
      _isSpeechAvailable = false;
      // 不显示错误提示，等用户点击时再处理
    }
  }

  /// 请求麦克风权限
  Future<void> _requestMicrophonePermission() async {
    try {
      if (kIsWeb) {
        // Web平台请求麦克风权限
        final status = await Permission.microphone.status;
        if (!status.isGranted) {
          final requestStatus = await Permission.microphone.request();
          if (kDebugMode) {
            debugPrint('Web平台麦克风权限请求结果: $requestStatus');
          }
        } else {
          if (kDebugMode) {
            debugPrint('Web平台已拥有麦克风权限');
          }
        }
      } else {
        // 移动端请求麦克风权限
        final status = await Permission.microphone.status;
        if (!status.isGranted) {
          final requestStatus = await Permission.microphone.request();
          if (kDebugMode) {
            debugPrint('移动端麦克风权限请求结果: $requestStatus');
          }
        } else {
          if (kDebugMode) {
            debugPrint('移动端已拥有麦克风权限');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('请求麦克风权限失败: $e');
      }
    }
  }

  /// 开始语音识别
  Future<void> _startVoiceInput() async {
    if (kDebugMode) {
      debugPrint('开始语音识别: _isListening=$_isListening');
    }
    
    // 如果正在监听，不应该再次开始
    if (_isListening) {
      if (kDebugMode) {
        debugPrint('已经在监听中，忽略重复开始请求');
      }
      return;
    }
    
    // 立即更新UI，给用户反馈（即使后续可能失败）
    if (mounted) {
      setState(() {
        _isListening = true;
      });
      _pulseController.repeat();
    }

    // 检查权限状态（仅检查，不再请求）
    final status = await Permission.microphone.status;
    if (!status.isGranted) {
      if (!mounted) return;
      // 重置UI状态
      setState(() {
        _isListening = false;
      });
      _pulseController.stop();
      _pulseController.reset();
      CustomSnackBar.showError(context, AppLocalizations.of(context)!.needMicrophonePermission);
      return;
    }

    // 在权限授予后，重新初始化语音识别服务
    try {
      // 先尝试初始化（如果之前失败）
      if (!_isSpeechAvailable) {
        _isSpeechAvailable = await _speech.initialize(
          onError: (error) {
            if (kDebugMode) {
              debugPrint('语音识别错误: ${error.errorMsg}');
            }
          },
          onStatus: (status) {
            if (kDebugMode) {
              debugPrint('语音识别状态: $status');
            }
          },
        );
        if (kDebugMode) {
          debugPrint('重新初始化语音识别服务: $_isSpeechAvailable');
        }
      }
      
      // 检查语音识别服务是否可用
      if (!_isSpeechAvailable) {
        if (mounted) {
          // 重置UI状态（因为前面已经设置为true了）
          setState(() {
            _isListening = false;
          });
          _pulseController.stop();
          _pulseController.reset();
          
          if (kIsWeb) {
            CustomSnackBar.showError(context, AppLocalizations.of(context)!.browserDoesNotSupportSpeechRecognition);
          } else {
            // 提供更详细的错误信息和解决方案
            _showSpeechServiceUnavailableDialog(context, null);
          }
        }
        return;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('检查语音识别服务失败: $e');
      }
      if (mounted) {
        setState(() {
          _isListening = false;
        });
        _pulseController.stop();
        _pulseController.reset();
        
        if (kIsWeb) {
          CustomSnackBar.showError(context, AppLocalizations.of(context)!.needMicrophonePermission);
        } else {
          CustomSnackBar.showError(
            context, 
            AppLocalizations.of(context)!.speechRecognitionServiceInitializationFailed(e)
          );
        }
      }
      return;
    }

    try {
      // 新一轮识别开始，清空上一句识别结果与错误状态
      _recognizedText = '';
      _lastSpeechError = null;
      await _speech.listen(
        onResult: (result) {
          if (kDebugMode) {
            debugPrint('语音识别原始结果: "${result.recognizedWords}", finalResult: ${result.finalResult}');
          }
          
          // 更新实时识别结果
          setState(() {
            _recognizedText = result.recognizedWords;
          });
          
          // 移除自动处理finalResult的逻辑，改为手动控制录音停止和提交
          // 无论是否是最终结果，只更新UI显示，不自动停止录音
          // 录音停止和结果提交由用户手势（松开手指）控制
        },
        localeId: 'zh_CN',
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.search,
          cancelOnError: true,
          partialResults: true,
        ),
      );
    } catch (e) {
      setState(() {
        _isListening = false;
      });
      _pulseController.stop();
      _pulseController.reset();
      
      // 检查是否是"已经启动"的错误
      final errorMsg = e.toString().toLowerCase();
      if (errorMsg.contains('already started') || 
          errorMsg.contains('already listening') ||
          errorMsg.contains('recognition has already started') ||
          errorMsg.contains('invalidstateerror')) {
        // 尝试强制重置状态
        try {
          _speech.stop();
          await Future.delayed(const Duration(milliseconds: 200));
          _speech.cancel();
          await Future.delayed(const Duration(milliseconds: 300));
        } catch (resetError) {
          if (kDebugMode) {
            debugPrint('强制重置失败: $resetError');
          }
        }
        // 在async操作后重新检查mounted状态
        if (mounted) {
          CustomSnackBar.showError(context, AppLocalizations.of(context)!.speechRecognitionServiceInUse);
        }
      } else if (errorMsg.contains('network') || errorMsg.contains('网络')) {
        if (mounted) {
          // 系统识别引擎（云识别模式）断网即抛网络错误——语音转文字
          // 需要网络，但手动记账/解析/入库全离线可用，文案指明出路
          CustomSnackBar.showError(context,
              AppLocalizations.of(context)!.speechRecognitionNetworkRequired);
        }
      } else {
        if (mounted) {
          CustomSnackBar.showError(context, '${AppLocalizations.of(context)!.speechRecognitionFailed}: ${e.toString()}');
        }
      }
    }
  }

  /// 停止语音识别会话：等待 stop() 完成并给最终结果留出送达余量。
  /// 部分系统识别服务不推流式中间结果，只在 stop 后一次性回传全文，
  /// 此前「stop 不等待 + 50ms 后 cancel」会截胡丢弃最终结果。
  Future<void> _stopSpeechSession() async {
    try {
      await _speech.stop().timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('停止识别失败，降级cancel: $e');
      }
      _speech.cancel().catchError((error) {
        if (kDebugMode) {
          debugPrint('cancel方法调用失败: $error');
        }
      });
    }
  }

  /// 空识别结果提示：优先透出识别层的真实错误（release 也可见），
  /// 替代一刀切的「没有检测到内容」。
  String _emptyVoiceMessage() {
    final l10n = AppLocalizations.of(context)!;
    final err = _lastSpeechError;
    if (err == null) {
      return l10n.noVoiceContentRecognized;
    }
    final e = err.toLowerCase();
    if (e.contains('network') || e.contains('网络')) {
      return l10n.networkConnectionError;
    }
    if (e.contains('no_speech') || e.contains('timeout')) {
      return l10n.noVoiceContentRecognized;
    }
    return '${l10n.speechRecognitionFailed}: $err';
  }

  /// 停止语音识别
  Future<void> _stopVoiceInput() async {
    if (kDebugMode) {
      debugPrint('停止语音输入: _isListening=$_isListening, _recognizedText=$_recognizedText');
    }
    
    // 1. 立即更新UI状态，给用户即时反馈
    if (mounted) {
      setState(() {
        _isListening = false;
        _showActionButtons = false;
      });
      _pulseController.stop();
      _pulseController.reset();
    }
    
    // 2. 等待识别会话真正结束，最终结果随 stop 送达（不再 50ms 截胡）
    await _stopSpeechSession();
    
    // 3. 处理最终识别结果
    if (mounted && !_showEditScreen) {
      if (_recognizedText.isEmpty) {
        CustomSnackBar.showError(context, _emptyVoiceMessage());
      } else {
        // 有识别结果，自动提交
        _submitVoiceText(_recognizedText);
      }
    }
  }

  /// 提交语音文本：本地解析（全程离线），按置信度分流：
  /// - 有把握（金额/类型/分类齐备）：直接入库，Snackbar 带修改入口
  /// - 无把握（无金额/多金额冲突/类型未明示/分类未命中）：落预填表单由用户确认
  Future<void> _submitVoiceText(String text) async {
    if (text.isEmpty) {
      CustomSnackBar.showError(context, AppLocalizations.of(context)!.recognitionTextEmpty);
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final engine = await CategoryRuleLoader.loadDefaultEngine();
      final parser = VoiceTransactionParser(engine, Db.categories);
      final result = await parser.parse(text);

      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });

      if (result.isConfident) {
        await _saveDirectly(text, result);
      } else {
        _openPrefilledForm(text, result);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
        CustomSnackBar.showError(
          context,
          ErrorHelper.extractErrorMessage(
            e,
            defaultMessage: AppLocalizations.of(context)!.transactionFailed,
          ),
        );
      }
    }
  }

  /// 有把握：一句话一步记账，直接入库 + 结果 Snackbar 带修改入口
  Future<void> _saveDirectly(String text, VoiceParseResult result) async {
    final date = result.date ?? DateTime.now();
    final saved = await TransactionService().addTransaction(
      type: result.type!,
      category: result.categoryName!,
      amount: result.amount!,
      date: DateFormat('yyyy-MM-dd').format(date),
      note: text,
    );

    if (!mounted) return;
    // 清空识别结果，防止快速松手时重复提交上一句
    _recognizedText = '';

    // 首次记账后的云备份引导（仅一次，见 BackupGuidance）；
    // 弹在结果 Snackbar 之前，保留 Snackbar 的修改入口
    await BackupGuidance.maybeShowAfterFirstSave(context);
    if (!mounted) return;

    final l10n = AppLocalizations.of(context)!;
    final typeLabel = result.type == 0 ? l10n.income : l10n.expense;
    final amountText = result.amount! % 1 == 0
        ? result.amount!.toStringAsFixed(0)
        : result.amount!.toString();
    CustomSnackBar.showSuccessWithAction(
      context,
      l10n.voiceRecordedAs(typeLabel, amountText, result.categoryName!),
      l10n.edit,
      () {
        // 修改入口：打开编辑模式表单（预填刚入库的交易）
        context.push('/add-transaction', extra: TransactionPrefill(
          transactionId: saved['id'] as String,
          type: result.type,
          amount: result.amount,
          categoryName: result.categoryName,
          date: date,
          note: text,
          voiceMatchText: text,
        ));
      },
    );
  }

  /// 无把握：打开预填表单，识别文本带出、金额/类型预填，用户确认后入库
  void _openPrefilledForm(String text, VoiceParseResult result) {
    context.push('/add-transaction', extra: TransactionPrefill(
      type: result.type,
      amount: result.amount,
      date: result.date,
      note: text,
      voiceMatchText: text,
    ));
  }

  /// 构建语音输入按钮
  Widget _buildVoiceInputButton() {
    final buttonSize = ResponsiveHelper.spacing(
      context,
      small: 100,
      normal: 130,
      large: 160,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanDown: (_) {
        if (kDebugMode) {
          debugPrint('按钮按下: _isListening=$_isListening');
        }
        // 按下时开始录音并显示操作按钮
        if (!_isListening) {
          _startVoiceInput();
          setState(() {
            _showActionButtons = true;
            // 重置按钮区域状态
            _isInCancelButtonArea = false;
            _isInEditButtonArea = false;
          });
        }
      },
      onPanUpdate: (details) {
        if (_isListening && _showActionButtons) {
          // 获取屏幕尺寸
          final screenSize = MediaQuery.of(context).size;
          
          // 检查手指是否在取消按钮区域 - 放大检测区域
          final cancelButtonRect = Rect.fromLTWH(
            screenSize.width * 0.25 - 80,
            screenSize.height - 270,
            160,
            50,
          );
          
          // 检查手指是否在编辑文字按钮区域 - 放大检测区域
          final editButtonRect = Rect.fromLTWH(
            screenSize.width * 0.75 - 80,
            screenSize.height - 270,
            160,
            50,
          );
          
          // 只记录手指所在区域，不立即执行操作
          setState(() {
            _isInCancelButtonArea = cancelButtonRect.contains(details.globalPosition);
            _isInEditButtonArea = editButtonRect.contains(details.globalPosition);
          });
        }
      },
      onPanEnd: (_) {
        if (kDebugMode) {
          debugPrint('按钮松开: _isListening=$_isListening, _isInCancelButtonArea=$_isInCancelButtonArea, _isInEditButtonArea=$_isInEditButtonArea, _recognizedText=$_recognizedText');
        }
        
        // 松开手指时，根据最后所在区域执行操作
        if (_isListening) {
          setState(() {
            _showActionButtons = false;
          });
          
          if (_isInCancelButtonArea) {
            // 手指最后在取消按钮区域，执行取消操作
            _cancelRecording();
          } else if (_isInEditButtonArea) {
            // 手指最后在编辑文字按钮区域，检查是否有识别内容
            if (_recognizedText.isNotEmpty) {
              // 有识别内容，执行编辑操作
              _enterEditMode();
            } else {
              // 没有识别内容，执行正常停止录音操作，会触发未识别提示
              _stopVoiceInput();
            }
          } else {
            // 手指不在任何按钮区域，执行正常停止录音操作
            _stopVoiceInput();
          }
          
          // 重置按钮区域状态
          setState(() {
            _isInCancelButtonArea = false;
            _isInEditButtonArea = false;
          });
        }
      },
      onPanCancel: () {
        if (kDebugMode) {
          debugPrint('Pan取消: _isListening=$_isListening');
        }
        // 极少情况下会触发，确保停止录音并隐藏操作按钮
        if (_isListening) {
          setState(() {
            _showActionButtons = false;
            _isInCancelButtonArea = false;
            _isInEditButtonArea = false;
          });
          _stopVoiceInput();
        }
      },
      child: Container(
        alignment: Alignment.bottomCenter,
        padding: const EdgeInsets.only(bottom: 30),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          width: buttonSize,
          height: buttonSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isListening
                ? ThemeHelper.expenseColor(context)
                : ThemeHelper.primary(context),
            boxShadow: _isListening
                ? [
                    BoxShadow(
                      color: ThemeHelper.expenseColor(context).withValues(alpha: 0.5),
                      blurRadius: 20,
                      spreadRadius: 8,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: ThemeHelper.primary(context).withValues(alpha: 0.4),
                      blurRadius: 15,
                      spreadRadius: 5,
                    ),
                  ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 录音时的脉冲动画
              if (_isListening)
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Container(
                      width: buttonSize * (1 + _pulseAnimation.value * 0.5),
                      height: buttonSize * (1 + _pulseAnimation.value * 0.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 1 - _pulseAnimation.value * 0.8),
                          width: 3,
                        ),
                      ),
                    );
                  },
                ),
              // 话筒图标和文字
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isSubmitting)
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  else
                    Icon(
                      _isListening ? Icons.mic : Icons.mic_none,
                      size: ResponsiveHelper.spacing(
                        context,
                        small: 40,
                        normal: 52,
                        large: 64,
                      ),
                      color: Colors.white,
                    ),
                  SizedBox(
                    height: ResponsiveHelper.spacing(
                      context,
                      small: 8,
                      normal: 12,
                      large: 16,
                    ),
                  ),
                  ScaledText(
                    _isSubmitting
                        ? AppLocalizations.of(context)!.processing
                        : _isListening
                            ? AppLocalizations.of(context)!.releaseToStop
                            : AppLocalizations.of(context)!.pressAndHoldToSpeak,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ResponsiveHelper.responsiveTextStyle(
                      context,
                      fontSize: ResponsiveHelper.spacing(
                        context,
                        small: 14,
                        normal: 16,
                        large: 18,
                      ),
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 取消录音
  Future<void> _cancelRecording() async {
    // 1. 立即更新UI状态
    setState(() {
      _isListening = false;
      _showActionButtons = false;
      _recognizedText = '';
    });
    _pulseController.stop();
    _pulseController.reset();
    
    // 2. 取消即丢弃结果，直接 cancel 释放会话（无需 stop + 延迟 cancel）
    _speech.cancel().catchError((error) {
      if (kDebugMode) {
        debugPrint('cancelRecording cancel方法调用失败: $error');
      }
    });
    
    if (kDebugMode) {
      debugPrint('录音已取消，停止命令已发送');
    }
  }

  /// 进入编辑模式
  Future<void> _enterEditMode() async {
    // 1. 立即更新UI状态
    setState(() {
      _isListening = false;
      _showActionButtons = false;
      _showEditScreen = true;
    });
    _pulseController.stop();
    _pulseController.reset();
    
    // 2. 等待会话结束，确保最终结果送达后再带入编辑框
    await _stopSpeechSession();
    if (!mounted) return;
    
    if (kDebugMode) {
      debugPrint('进入编辑模式，识别结果: $_recognizedText');
    }
    
    // 3. 带入最终识别文本
    setState(() {
      _editingText = _recognizedText;
    });
    _textEditingController.text = _recognizedText;
    _textEditingController.selection = TextSelection.fromPosition(
      TextPosition(offset: _recognizedText.length),
    );
  }

  /// 取消编辑，返回录音页面
  void _cancelEdit() {
    setState(() {
      _showEditScreen = false;
      _recognizedText = '';
      _editingText = '';
    });
    // 清空文本控制器内容
    _textEditingController.clear();
  }

  /// 提交编辑后的文本
  void _submitEditedText() {
    if (_editingText.isNotEmpty) {
      _submitVoiceText(_editingText);
      _cancelEdit();
    } else {
      CustomSnackBar.showError(context, AppLocalizations.of(context)!.textCannotBeEmpty);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ScaledText(AppLocalizations.of(context)!.voiceTransaction),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => context.go('/home'),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // 主页面内容
            _showEditScreen
                ? Container(
                    color: ThemeHelper.surface(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(height: ResponsiveHelper.spacing(context, small: 20, normal: 30, large: 40)),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.horizontalPadding(context)),
                          child: ScaledText(
                            AppLocalizations.of(context)!.editRecognizedText,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        SizedBox(height: ResponsiveHelper.spacing(context, small: 16, normal: 20, large: 24)),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.horizontalPadding(context)),
                          child: TextField(
                            controller: _textEditingController,
                            onChanged: (value) {
                              setState(() {
                                _editingText = value;
                              });
                            },
                            maxLines: 4,
                            style: const TextStyle(color: Colors.white, fontSize: 16),
                            decoration: InputDecoration(
                              hintText: AppLocalizations.of(context)!.pleaseEnterOrEditText,
                              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: ThemeHelper.primary(context)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: ThemeHelper.primary(context), width: 2),
                              ),
                              filled: true,
                              fillColor: ThemeHelper.surface(context).withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                        SizedBox(height: ResponsiveHelper.spacing(context, small: 20, normal: 24, large: 30)),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.horizontalPadding(context)),
                          child: Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _cancelEdit,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: ThemeHelper.surface(context).withValues(alpha: 0.5),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: ScaledText(AppLocalizations.of(context)!.cancel),
                                ),
                              ),
                              SizedBox(width: ResponsiveHelper.spacing(context, small: 12, normal: 16, large: 20)),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _submitEditedText,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: ThemeHelper.primary(context),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: ScaledText(AppLocalizations.of(context)!.send),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : Container(
                    color: ThemeHelper.surface(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 移除了实时识别结果显示，改为只在滑动到编辑区域时显示
                        // 使用提示
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.horizontalPadding(context), vertical: 20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: ThemeHelper.surface(context).withValues(alpha: 0.3),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 14,
                                  color: Colors.white.withValues(alpha: 0.5),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: ScaledText(
                                    AppLocalizations.of(context)!.pressAndHoldToSpeakSlideToCancel,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white.withValues(alpha: 0.5),
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
            
            // 底部半圆形语音按钮 - 始终固定在底部
            if (!_showEditScreen)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildVoiceInputButton(),
              ),
            
            // 微信风格的遮罩层
            if (_showActionButtons && !_showEditScreen) ...[
              // 半透明遮罩
              Container(
                color: Colors.black.withValues(alpha: 0.5),
              ),
              
              // 移除了识别结果气泡，不再显示任何识别内容
              
              // 操作按钮区域 - 位于语音按钮上方，保持合适距离
              Positioned(
                bottom: 200,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    // 取消按钮 - 放大样式，带滑动缩放动画
                    GestureDetector(
                      onTap: _cancelRecording,
                      child: AnimatedScale(
                        scale: _isInCancelButtonArea ? 1.2 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: _isInCancelButtonArea ? [
                              BoxShadow(
                                color: Colors.red.withValues(alpha: 0.5),
                                blurRadius: 10,
                                spreadRadius: 5,
                              ),
                            ] : [],
                          ),
                          child: ScaledText(
                            AppLocalizations.of(context)!.cancel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    
                    // 编辑文字按钮 - 放大样式，带滑动缩放动画
                    GestureDetector(
                      onTap: _enterEditMode,
                      child: AnimatedScale(
                        scale: _isInEditButtonArea ? 1.2 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: _isInEditButtonArea ? [
                              BoxShadow(
                                color: Colors.blue.withValues(alpha: 0.5),
                                blurRadius: 10,
                                spreadRadius: 5,
                              ),
                            ] : [],
                          ),
                          child: ScaledText(
                            AppLocalizations.of(context)!.editRecognizedText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 显示语音服务不可用对话框
  void _showSpeechServiceUnavailableDialog(
    BuildContext context,
    Map<String, dynamic>? diagnostics,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ThemeHelper.surface(context),
        title: ScaledText(
          AppLocalizations.of(context)!.voiceRecognitionServiceUnavailable,
          style: const TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ScaledText(
                '${AppLocalizations.of(context)!.pleaseCheckTheFollowing}\n\n'
                '1. ${AppLocalizations.of(context)!.microphonePermission}\n'
                '2. ${AppLocalizations.of(context)!.speechRecognitionService}\n'
                '${AppLocalizations.of(context)!.xiaomiHuaweiCheckGoogleApp}\n'
                '${AppLocalizations.of(context)!.orInstallGoogleVoiceService}\n'
                '3. ${AppLocalizations.of(context)!.tryRestartingApp}\n'
                '4. ${AppLocalizations.of(context)!.checkSystemSettings}',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              if (kDebugMode && diagnostics != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ScaledText(
                        AppLocalizations.of(context)!.diagnosticInformation,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...diagnostics.entries.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: ScaledText(
                          '${e.key}: ${e.value}',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                          ),
                        ),
                      )),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          // 手动记账引导：语音不可用时无需离开记账流程
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.push('/add-transaction');
            },
            child: ScaledText(
              AppLocalizations.of(context)!.manualEntry,
              style: TextStyle(color: ThemeHelper.primary(context)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: ScaledText(
              AppLocalizations.of(context)!.gotIt,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}