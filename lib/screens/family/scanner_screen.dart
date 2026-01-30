import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/theme_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/common/custom_snackbar.dart';
import '../../widgets/common/scaled_text.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleBarcode(BarcodeCapture barcodeCapture) {
    final barcodes = barcodeCapture.barcodes;
    if (barcodes.isEmpty) return;

    final barcode = barcodes.first;
    if (barcode.rawValue == null) return;

    final code = barcode.rawValue!;
    
    // 解析二维码内容，格式：family:familyId
    if (code.startsWith('family:')) {
      final familyId = code.substring(7); // 去掉 'family:' 前缀
      if (familyId.isNotEmpty) {
        // 停止扫描
        _controller.stop();
        // 跳转到申请页面
        if (mounted) {
          context.push('/apply-family?familyId=$familyId');
        }
      }
    } else {
      // 如果不是家庭邀请码格式，显示错误提示
      if (mounted) {
        CustomSnackBar.showError(context, AppLocalizations.of(context)!.invalidFamilyInviteCode);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ScaledText(AppLocalizations.of(context)!.scanQrCode),
        backgroundColor: Colors.black,
      ),
      body: Stack(
        children: [
          // 扫描区域
          MobileScanner(
            controller: _controller,
            onDetect: _handleBarcode,
          ),
          // 扫描框和提示
          Column(
            children: [
              Expanded(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.5),
                  child: Center(
                    child: Container(
                      width: ResponsiveHelper.responsiveValue(
                        context,
                        small: 250.0,
                        normal: 300.0,
                        large: 350.0,
                      ),
                      height: ResponsiveHelper.responsiveValue(
                        context,
                        small: 250.0,
                        normal: 300.0,
                        large: 350.0,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: ThemeHelper.primary(context),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Stack(
                        children: [
                          // 四个角的装饰
                          Positioned(
                            top: 0,
                            left: 0,
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                border: Border(
                                  top: BorderSide(
                                    color: ThemeHelper.primary(context),
                                    width: 4,
                                  ),
                                  left: BorderSide(
                                    color: ThemeHelper.primary(context),
                                    width: 4,
                                  ),
                                ),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                border: Border(
                                  top: BorderSide(
                                    color: ThemeHelper.primary(context),
                                    width: 4,
                                  ),
                                  right: BorderSide(
                                    color: ThemeHelper.primary(context),
                                    width: 4,
                                  ),
                                ),
                                borderRadius: const BorderRadius.only(
                                  topRight: Radius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            left: 0,
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: ThemeHelper.primary(context),
                                    width: 4,
                                  ),
                                  left: BorderSide(
                                    color: ThemeHelper.primary(context),
                                    width: 4,
                                  ),
                                ),
                                borderRadius: const BorderRadius.only(
                                  bottomLeft: Radius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: ThemeHelper.primary(context),
                                    width: 4,
                                  ),
                                  right: BorderSide(
                                    color: ThemeHelper.primary(context),
                                    width: 4,
                                  ),
                                ),
                                borderRadius: const BorderRadius.only(
                                  bottomRight: Radius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // 底部提示
              Container(
                padding: const EdgeInsets.all(24),
                color: Colors.black.withValues(alpha: 0.7),
                child: Column(
                  children: [
                    ScaledText(
                      AppLocalizations.of(context)!.alignQrCodeInFrame,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context)),
                    ScaledText(
                      AppLocalizations.of(context)!.ensureQrCodeClear,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

