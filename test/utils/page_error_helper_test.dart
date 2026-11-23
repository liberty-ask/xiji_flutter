import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiji_flutter/l10n/app_localizations.dart';
import 'package:xiji_flutter/services/api/api_client.dart';
import 'package:xiji_flutter/utils/page_error_helper.dart';

void main() {
  Future<String> resolve(
    WidgetTester tester,
    Object? error, {
    String network = 'NET_OK',
    String fallback = 'FALLBACK_OK',
  }) async {
    late String message;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            message = PageErrorHelper.resolveLoadMessage(
              context,
              error,
              networkMessage: network,
              fallbackMessage: fallback,
            );
            return const SizedBox();
          },
        ),
      ),
    );
    return message;
  }

  test('网络失败判定：ApiException 无状态码为网络类', () {
    expect(
        PageErrorHelper.isNetworkFailure(
            const ApiException('Connection error')),
        isTrue);
    expect(
        PageErrorHelper.isNetworkFailure(
            const ApiException('Forbidden', statusCode: 403)),
        isFalse);
    expect(PageErrorHelper.isNetworkFailure(Exception('Connection error')),
        isTrue);
  });

  testWidgets('网络失败：返回场景网络文案，不含原始异常文本', (tester) async {
    final message =
        await resolve(tester, const ApiException('Connection error'));
    expect(message, 'NET_OK');
    expect(message.contains('Exception'), isFalse);
    expect(message.contains('Connection error'), isFalse);
  });

  testWidgets('业务错误且服务端有明确 message：展示该 message', (tester) async {
    final message = await resolve(
      tester,
      const ApiException('该家庭已解散', statusCode: 400),
    );
    expect(message, '该家庭已解散');
  });

  testWidgets('服务端通用错误：回退场景业务文案', (tester) async {
    final message = await resolve(
      tester,
      const ApiException('Server Error', statusCode: 500),
    );
    expect(message, 'FALLBACK_OK');
  });
}
