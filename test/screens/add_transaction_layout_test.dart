import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
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
  String? note,
  double fontSizeScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    FontSizeInherited(
      fontSizeScale: fontSizeScale,
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
          home: AddTransactionScreen(
            prefill: note == null ? null : TransactionPrefill(note: note),
          ),
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

/// 页面只有一个滚动容器（正文），分类网格自身不可滚动
double _maxScrollExtent(WidgetTester tester) {
  final scrollable = tester.state<ScrollableState>(
    find
        .descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  return scrollable.position.maxScrollExtent;
}

/// 分类格必须是接近正方形的（宽/高 ∈ [0.9, 1.1]），不能靠拉高填充
void _expectSquareCells(WidgetTester tester) {
  final cells = find.descendant(
    of: find.byType(CategorySelector),
    matching: find.byType(InkWell),
  );
  expect(cells, findsWidgets);

  final grid = tester.widget<GridView>(find.byType(GridView));
  final delegate =
      grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
  expect(delegate.childAspectRatio, 1.0, reason: '格子按 1:1 编制');

  final rect = tester.getRect(cells.first);
  final ratio = rect.width / rect.height;
  expect(ratio, inInclusiveRange(0.9, 1.1),
      reason: '分类格应接近正方形，实际宽高比 $ratio');
}

/// 常规尺寸下正文不能顶到顶到保存按钮，至少留 8dp 余量
void _expectSlackAboveBottomBar(WidgetTester tester, Size size) {
  final noteRect = tester.getRect(find.byKey(const Key('noteChip')));
  // 测试环境无安全区，底栏恒为 12 + 48 + 12
  const barHeight = 72.0;
  expect(noteRect.bottom, lessThanOrEqualTo(size.height - barHeight - 8),
      reason: '内容与底栏之间要留呼吸间距，不能零容差贴住');
}

void main() {
  group('记一笔页面自适应布局', () {
    testWidgets('411×892 常规：一屏可见、不滚动、格子接近正方形', (tester) async {
      const size = Size(411, 892);
      await _pumpScreen(tester, size,
          note: '这是二十三个字的备注用来验证一行能显示多少内容');

      expect(tester.takeException(), isNull);
      _expectSaveButtonVisible(tester, size);
      _expectSlackAboveBottomBar(tester, size);
      _expectSquareCells(tester);
      expect(_maxScrollExtent(tester), 0, reason: '常规尺寸不应出现滚动');

      final l10n = AppLocalizations.of(
        tester.element(find.byType(AddTransactionScreen)),
      )!;
      expect(find.byType(PageView), findsNothing);

      // 收支切换是带文字的分段控件，明确可点
      expect(find.text(l10n.expense), findsOneWidget);
      expect(find.text(l10n.income), findsOneWidget);

      // 日期独立一行且完整显示，不省略
      final dateText =
          find.text(DateFormat('yyyy-MM-dd').format(DateTime.now()));
      expect(dateText, findsOneWidget);
      expect(
        tester.renderObject<RenderParagraph>(dateText).didExceedMaxLines,
        isFalse,
        reason: '日期不允许省略号',
      );

      // 备注独立一行，至少能看 20 个字
      final noteText = find.text('这是二十三个字的备注用来验证一行能显示多少内容');
      expect(noteText, findsOneWidget);
      expect(
        tester.getSize(noteText).width,
        greaterThanOrEqualTo(20 * 14),
        reason: '备注可见宽度需容纳 20 个汉字',
      );

      // 已选分类回显
      await tester.tap(find.text('餐饮'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.selectedCategory('餐饮')), findsOneWidget);

      // 切换收支会清空已选分类
      await tester.tap(find.text(l10n.income));
      await tester.pumpAndSettle();
      expect(find.text(l10n.selectedCategory('餐饮')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('360×640 小屏：整页滚动、分类完整展开、按钮可见', (tester) async {
      const size = Size(360, 640);
      await _pumpScreen(tester, size);

      expect(tester.takeException(), isNull);
      _expectSaveButtonVisible(tester, size);
      _expectSquareCells(tester);
      expect(_maxScrollExtent(tester), greaterThan(0),
          reason: '小屏放不下时整页滚动，不做嵌套滚动');
      expect(find.byType(PageView), findsNothing);
    });

    testWidgets('320×568 极小屏：不溢出、可滚动', (tester) async {
      const size = Size(320, 568);
      await _pumpScreen(tester, size);

      expect(tester.takeException(), isNull);
      _expectSaveButtonVisible(tester, size);
      _expectSquareCells(tester);
      expect(_maxScrollExtent(tester), greaterThan(0));
    });

    testWidgets('480×1000 大屏：不滚动、格子不被拉成大方块', (tester) async {
      const size = Size(480, 1000);
      await _pumpScreen(tester, size);

      expect(tester.takeException(), isNull);
      _expectSaveButtonVisible(tester, size);
      _expectSlackAboveBottomBar(tester, size);
      _expectSquareCells(tester);
      expect(_maxScrollExtent(tester), 0);

      // 列数随宽度增加：480 宽时比 411 的 6 列更多，格子仍接近正方形
      final selector = find.byType(CategorySelector);
      expect(tester.getSize(selector).width, greaterThan(400));
      final grid = tester.widget<GridView>(find.byType(GridView));
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, greaterThanOrEqualTo(6));
    });

    testWidgets('892×411 横屏：正文限宽居中、不溢出、整页滚动', (tester) async {
      const size = Size(892, 411);
      await _pumpScreen(tester, size);

      expect(tester.takeException(), isNull);
      _expectSaveButtonVisible(tester, size);
      _expectSquareCells(tester);
      expect(_maxScrollExtent(tester), greaterThan(0), reason: '横屏改为整页滚动');

      // 正文限宽 560 并水平居中
      final rect = tester.getRect(find.byType(CategorySelector));
      expect(rect.width, lessThanOrEqualTo(560 + 0.5));
      final leftGap = rect.left;
      final rightGap = size.width - rect.right;
      expect((leftGap - rightGap).abs(), lessThanOrEqualTo(1.0),
          reason: '大屏正文应水平居中');
    });

    testWidgets('字号 1.4 倍：常规与小屏都不溢出', (tester) async {
      for (final size in [const Size(411, 892), const Size(360, 640)]) {
        await _pumpScreen(tester, size, fontSizeScale: 1.4);
        expect(tester.takeException(), isNull, reason: '$size 放大字号后不溢出');
        _expectSaveButtonVisible(tester, size);
      }
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
      expect(find.byType(CategorySelector), findsNothing);
      final chip = find.byKey(const Key('categoryChip'));
      expect(chip, findsOneWidget);
      expect(tester.getSize(chip).height, 44);
      expect(
        find.descendant(of: chip, matching: find.text(l10n.category)),
        findsOneWidget,
      );
      _expectSaveButtonVisible(tester, size, bottomInset: 296);

      // 点开弹层：复用不分页的全量网格（宽度自适应，不靠高度拉伸）
      await tester.tap(chip);
      await tester.pumpAndSettle();
      final sheetSelector =
          tester.widget<CategorySelector>(find.byType(CategorySelector));
      expect(sheetSelector.adaptiveLabels, isTrue);

      await tester.tap(find.text('餐饮'));
      await tester.pumpAndSettle();

      // 选中即关闭弹层并回填 chip
      expect(find.byType(CategorySelector), findsNothing);
      expect(find.text(l10n.selectedCategory('餐饮')), findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('categoryChip'))).height, 44);
      expect(tester.takeException(), isNull);
    });

    testWidgets('英文界面 360×640 不溢出（两行标签）', (tester) async {
      const size = Size(360, 640);
      await _pumpScreen(tester, size, locale: const Locale('en'));

      expect(tester.takeException(), isNull);
      _expectSaveButtonVisible(tester, size);
      _expectSquareCells(tester);

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
