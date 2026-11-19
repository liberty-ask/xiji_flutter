import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiji_flutter/models/theme_extensions.dart';
import 'package:xiji_flutter/utils/budget_progress.dart';
import 'package:xiji_flutter/widgets/common/budget_progress_bar.dart';

void main() {
  group('BudgetProgress.ratio：进度比例', () {
    test('按原始金额计算，不受取整影响', () {
      expect(BudgetProgress.ratio(1600, 2000), closeTo(0.8, 1e-9));
      expect(BudgetProgress.ratio(796, 1000), closeTo(0.796, 1e-9));
      expect(BudgetProgress.ratio(999, 1000), closeTo(0.999, 1e-9));
    });

    test('超支比例 clamp 到 1', () {
      expect(BudgetProgress.ratio(2400, 2000), 1.0);
    });

    test('预算为 0 或缺失返回 0', () {
      expect(BudgetProgress.ratio(1600, 0), 0);
      expect(BudgetProgress.ratio(1600, null), 0);
      expect(BudgetProgress.ratio(null, 2000), 0);
    });
  });

  group('预算进度条颜色分档（首页与预算页共用 BudgetProgressBar）', () {
    Future<({double value, Color barColor, Color normalColor, Color overColor})>
        pumpBar(WidgetTester tester, num? used, num? total) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        ),
        home: Scaffold(body: BudgetProgressBar(used: used, total: total)),
      ));
      final context = tester.element(find.byType(BudgetProgressBar));
      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      final valueColor =
          (indicator.valueColor! as AlwaysStoppedAnimation<Color>).value;
      final theme = Theme.of(context);
      return (
        value: indicator.value!,
        barColor: valueColor,
        normalColor: theme.colorScheme.primary,
        overColor: theme.appColors.expenseColor,
      );
    }

    testWidgets('79.6%：绿（不被四舍五入成 80% 误判）', (tester) async {
      final r = await pumpBar(tester, 796, 1000);
      expect(r.barColor, r.normalColor);
    });

    testWidgets('79.9%：绿', (tester) async {
      final r = await pumpBar(tester, 799, 1000);
      expect(r.barColor, r.normalColor);
    });

    testWidgets('80.0%：橙（达到即变色）', (tester) async {
      final r = await pumpBar(tester, 1600, 2000);
      expect(r.barColor, Colors.orange);
    });

    testWidgets('99.9%：橙', (tester) async {
      final r = await pumpBar(tester, 999, 1000);
      expect(r.barColor, Colors.orange);
    });

    testWidgets('100.0%：红（达到即变色）', (tester) async {
      final r = await pumpBar(tester, 2000, 2000);
      expect(r.barColor, r.overColor);
    });

    testWidgets('120%：红且进度条封顶', (tester) async {
      final r = await pumpBar(tester, 2400, 2000);
      expect(r.barColor, r.overColor);
      expect(r.value, 1.0);
    });

    testWidgets('预算为 0：进度 0 且保持正常色', (tester) async {
      final r = await pumpBar(tester, 1600, 0);
      expect(r.value, 0);
      expect(r.barColor, r.normalColor);
    });
  });
}
