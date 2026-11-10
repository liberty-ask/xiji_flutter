import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:xiji_flutter/data/local/builtin_categories.dart';
import 'package:xiji_flutter/l10n/app_localizations.dart';
import 'package:xiji_flutter/models/category.dart';
import 'package:xiji_flutter/providers/category_provider.dart';
import 'package:xiji_flutter/providers/transaction_provider.dart';
import 'package:xiji_flutter/screens/home/add_transaction_screen.dart';
import 'package:xiji_flutter/widgets/common/font_size_inherited.dart';
import 'package:xiji_flutter/widgets/custom/category_selector.dart';

/// 分类数据走内存假实现，避免 widget 测试触碰本地库
class _FakeCategoryProvider extends CategoryProvider {
  _FakeCategoryProvider(this._items);

  final List<Category> _items;

  @override
  List<Category> get categories => _items;

  @override
  Map<String, int> get usageCounts => const {};

  @override
  bool get isLoading => false;

  @override
  String? get error => null;

  @override
  Future<void> loadCategories() async {}
}

List<Category> _builtinCategories() => BuiltinCategories.all
    .map((b) => Category(
          id: b.id,
          name: b.name,
          icon: b.icon,
          nameKey: b.nameKey,
          sortOrder: b.sortOrder,
        ))
    .toList();

Future<void> _pumpScreen(
  WidgetTester tester,
  Size size, {
  Locale locale = const Locale('zh', 'CN'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    FontSizeInherited(
      fontSizeScale: 1.0,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<CategoryProvider>.value(
            value: _FakeCategoryProvider(_builtinCategories()),
          ),
          ChangeNotifierProvider<TransactionProvider>(
            create: (_) => TransactionProvider(),
          ),
        ],
        child: MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          home: const AddTransactionScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 单独渲染 CategorySelector（验证默认行为，不经页面）
Future<void> _pumpSelector(
  WidgetTester tester, {
  required Locale locale,
  bool adaptiveLabels = false,
}) async {
  tester.view.physicalSize = const Size(411, 892);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    FontSizeInherited(
      fontSizeScale: 1.0,
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        home: Scaffold(
          body: CategorySelector(
            categories: _builtinCategories(),
            adaptiveLabels: adaptiveLabels,
            onSelected: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 保存按钮必须整块落在可视区内，不需要滚动
void _expectSaveButtonVisible(WidgetTester tester, Size size,
    {double bottomInset = 0}) {
  final l10n = AppLocalizations.of(
    tester.element(find.byType(AddTransactionScreen)),
  )!;
  final saveFinder = find.widgetWithText(ElevatedButton, l10n.confirmAdd);
  expect(saveFinder, findsOneWidget);

  final rect = tester.getRect(saveFinder);
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.bottom, lessThanOrEqualTo(size.height - bottomInset + 0.5));
  expect(rect.height, greaterThan(0));
}

void main() {
  group('记一笔页面布局', () {
    testWidgets('411×892 不溢出且保存按钮可见', (tester) async {
      const size = Size(411, 892);
      await _pumpScreen(tester, size);

      final overflow = tester.takeException();
      expect(overflow, isNull);
      _expectSaveButtonVisible(tester, size);

      // 常规态分类区 3 行/页
      final selector =
          tester.widget<CategorySelector>(find.byType(CategorySelector));
      expect(selector.rowsPerPage, 3);
      expect(selector.columns, isNull, reason: '中文界面走 6 列自适应');

      final l10n = AppLocalizations.of(
        tester.element(find.byType(AddTransactionScreen)),
      )!;

      // 已选分类回显
      await tester.tap(find.text('餐饮'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.selectedCategory('餐饮')), findsOneWidget);

      // 类型切换入口带 Tooltip；切换后清空已选分类
      expect(find.byTooltip(l10n.income), findsOneWidget);
      await tester.tap(find.byTooltip(l10n.income));
      await tester.pumpAndSettle();
      expect(find.text(l10n.selectedCategory('餐饮')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('360×640 不溢出且保存按钮可见', (tester) async {
      const size = Size(360, 640);
      await _pumpScreen(tester, size);

      expect(tester.takeException(), isNull);
      _expectSaveButtonVisible(tester, size);
    });

    testWidgets('键盘弹起时分类收成 chip，点开选择器选中后回填', (tester) async {
      const size = Size(411, 892);
      await _pumpScreen(tester, size);

      final l10n = AppLocalizations.of(
        tester.element(find.byType(AddTransactionScreen)),
      )!;

      // 模拟 296dp 系统键盘
      tester.view.viewInsets = const FakeViewPadding(bottom: 296);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // 键盘态整块网格换成单个 chip（44dp，远小于 3 行网格）
      expect(find.byType(CategorySelector), findsNothing);
      final chip = find.byKey(const Key('categoryChip'));
      expect(chip, findsOneWidget);
      expect(tester.getSize(chip).height, 44);
      expect(find.text(l10n.category), findsOneWidget);
      _expectSaveButtonVisible(tester, size, bottomInset: 296);

      // 点开弹层：复用不分页的 6 列全量网格
      await tester.tap(chip);
      await tester.pumpAndSettle();
      final sheetSelector =
          tester.widget<CategorySelector>(find.byType(CategorySelector));
      expect(sheetSelector.rowsPerPage, isNull);

      await tester.tap(find.text('餐饮'));
      await tester.pumpAndSettle();

      // 选中即关闭弹层并回填 chip
      expect(find.byType(CategorySelector), findsNothing);
      expect(find.text(l10n.selectedCategory('餐饮')), findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('categoryChip'))).height, 44);
      expect(tester.takeException(), isNull);
    });

    testWidgets('英文界面 360×640 不溢出（4 列两行标签）', (tester) async {
      const size = Size(360, 640);
      await _pumpScreen(tester, size, locale: const Locale('en'));

      expect(tester.takeException(), isNull);
      _expectSaveButtonVisible(tester, size);

      // 长英文分类名允许折两行，不再被单行截断
      final daily = find.descendant(
        of: find.byType(CategorySelector),
        matching: find.text('Daily Necessities'),
      );
      expect(daily, findsOneWidget);
      expect(tester.widget<Text>(daily).maxLines, 2);
    });

    testWidgets('弹层里英文长名折两行，高度不超 60% 屏高', (tester) async {
      const size = Size(411, 892);
      await _pumpScreen(tester, size, locale: const Locale('en'));

      tester.view.viewInsets = const FakeViewPadding(bottom: 296);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('categoryChip')));
      await tester.pumpAndSettle();

      // 弹层受 60% 屏高约束，内容超出时内部滚动
      expect(
        tester.getSize(find.byType(BottomSheet)).height,
        lessThanOrEqualTo(size.height * 0.6 + 0.5),
      );

      for (final name in ['Daily Necessities', 'Lifestyle Services']) {
        final item = find.descendant(
          of: find.byType(CategorySelector),
          matching: find.text(name),
        );
        expect(item, findsOneWidget, reason: '$name 应出现在弹层首屏');
        expect(tester.widget<Text>(item).maxLines, 2, reason: '$name 允许折两行');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('导入预览默认仍是 6 列单行（不传参）', (tester) async {
      await _pumpSelector(tester, locale: const Locale('en'));

      final grid = tester.widget<GridView>(find.byType(GridView));
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 6);
      expect(delegate.childAspectRatio, 1.1);

      final daily = find.descendant(
        of: find.byType(CategorySelector),
        matching: find.text('Daily Necessities'),
      );
      expect(tester.widget<Text>(daily).maxLines, 1);
      expect(tester.takeException(), isNull);
    });
  });
}
