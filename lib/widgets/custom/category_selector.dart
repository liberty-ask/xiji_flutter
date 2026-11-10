import 'package:flutter/material.dart';
import '../../data/local/builtin_categories.dart';
import '../../models/category.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/category_l10n.dart';
import '../../utils/icon_constants.dart';
import '../../utils/theme_helper.dart';

/// 分类选择器软提示排序（方案 4.4）：
/// score = 近 90 天同方向使用次数 * 10
///       + 提示倾向匹配（命中 3 / both 2 / 其他 0）
///       - sortOrder * 0.001
/// 始终返回全部分类，不做任何方向硬过滤。
List<Category> sortedCategoriesForDirection(
  List<Category> categories,
  int direction,
  Map<String, int> usageCounts,
) {
  int score(Category c) {
    final usage = usageCounts['${c.id}|$direction'] ?? 0;
    final hint = BuiltinCategories.byId(c.id)?.hint;
    final bonus = switch (hint) {
      CategoryHint.both => 2,
      CategoryHint.expense => direction == 1 ? 3 : 0,
      CategoryHint.income => direction == 0 ? 3 : 0,
      _ => 0,
    };
    // 放大 1000 倍消掉 sortOrder 的小数权重，避免浮点比较
    return usage * 10000 + bonus * 1000 - c.sortOrder;
  }

  final list = [...categories];
  list.sort((a, b) {
    final diff = score(b).compareTo(score(a));
    if (diff != 0) return diff;
    final order = a.sortOrder.compareTo(b.sortOrder);
    if (order != 0) return order;
    return a.id.compareTo(b.id);
  });
  return list;
}

class CategorySelector extends StatefulWidget {
  final List<Category> categories;
  final Category? selectedCategory;

  /// 当前交易方向：0 收入 / 1 支出 / 2 不计收支（仅用于软排序）
  final int direction;

  /// 近 90 天使用频次，key 为 `分类ID|方向`；缺省时按提示倾向排序
  final Map<String, int> usageCounts;
  final Function(Category) onSelected;

  /// 每页行数：null = 不分页、全量铺开（导入预览弹层沿用原行为）；
  /// 非空 = 按「行数 × 列数」分页，带页码点。
  final int? rowsPerPage;

  /// 固定列数：null 时不分页场景固定 6 列，分页场景按语言自适应
  /// （英文 4 列 + 两行标签，其余 6 列 + 单行标签）
  final int? columns;

  /// 不分页场景是否也启用「按语言自适应列数 + 两行标签」：
  /// false（默认）= 6 列 + 单行（导入预览弹层），true = 与主网格一致
  final bool adaptiveLabels;

  const CategorySelector({
    super.key,
    required this.categories,
    this.selectedCategory,
    this.direction = 1,
    this.usageCounts = const {},
    required this.onSelected,
    this.rowsPerPage,
    this.columns,
    this.adaptiveLabels = false,
  });

  @override
  State<CategorySelector> createState() => _CategorySelectorState();
}

class _CategorySelectorState extends State<CategorySelector> {
  static const double _spacing = 6;

  final PageController _pageController = PageController();
  int _page = 0;

  @override
  void didUpdateWidget(covariant CategorySelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 键盘弹起/收起会切换每页行数，分页结构变化后回到第一页
    if (oldWidget.rowsPerPage != widget.rowsPerPage) {
      _page = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(0);
        }
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sorted = sortedCategoriesForDirection(
        widget.categories, widget.direction, widget.usageCounts);

    if (widget.rowsPerPage == null) {
      return _buildAll(context, l10n, sorted);
    }
    return _buildPaged(context, l10n, sorted);
  }

  /// 标签布局：英文 4 列 + 两行标签（长名不截断），其余 6 列 + 单行
  ({int columns, int maxLines}) _labelLayout(BuildContext context) {
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    final columns = widget.columns ?? (isEnglish ? 4 : 6);
    return (columns: columns, maxLines: columns <= 4 ? 2 : 1);
  }

  /// 全量铺开：
  /// - 默认（导入预览弹层的分类弹层）：6 列、单行标签、不分页
  /// - [CategorySelector.adaptiveLabels] 为 true：与主网格一致的自适应布局
  Widget _buildAll(
    BuildContext context,
    AppLocalizations l10n,
    List<Category> sorted,
  ) {
    if (!widget.adaptiveLabels) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: widget.columns ?? 6,
          crossAxisSpacing: _spacing,
          mainAxisSpacing: _spacing,
          childAspectRatio: 1.1,
        ),
        itemCount: sorted.length,
        itemBuilder: (context, index) {
          final category = sorted[index];
          return _buildCell(
            context,
            l10n,
            category,
            maxLines: 1,
            isSelected: widget.selectedCategory?.id == category.id,
          );
        },
      );
    }

    final layout = _labelLayout(context);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: layout.columns,
        crossAxisSpacing: _spacing,
        mainAxisSpacing: _spacing,
        mainAxisExtent: _cellHeight(layout.maxLines),
      ),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final category = sorted[index];
        return _buildCell(
          context,
          l10n,
          category,
          maxLines: layout.maxLines,
          isSelected: widget.selectedCategory?.id == category.id,
        );
      },
    );
  }

  /// 单行标签 41dp、双行标签 44dp，与设计草稿一致
  static double _cellHeight(int maxLines) => maxLines == 2 ? 44.0 : 41.0;

  /// 分页铺开（记一笔页面）：固定行数、按语言自适应列数、带页码点
  Widget _buildPaged(
    BuildContext context,
    AppLocalizations l10n,
    List<Category> sorted,
  ) {
    if (sorted.isEmpty) {
      return const SizedBox.shrink();
    }

    final layout = _labelLayout(context);
    final columns = layout.columns;
    final maxLines = layout.maxLines;
    final rows = widget.rowsPerPage!;
    final itemsPerPage = columns * rows;
    final pageCount = (sorted.length / itemsPerPage).ceil();

    if (_page > pageCount - 1) {
      _page = pageCount - 1;
    }

    final cellHeight = _cellHeight(maxLines);
    final gridHeight = rows * cellHeight + (rows - 1) * _spacing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: gridHeight,
          child: PageView.builder(
            controller: _pageController,
            itemCount: pageCount,
            physics: pageCount > 1
                ? const PageScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            onPageChanged: (index) => setState(() => _page = index),
            itemBuilder: (context, page) {
              final start = page * itemsPerPage;
              final end =
                  (start + itemsPerPage).clamp(0, sorted.length);
              final items = sorted.sublist(start, end);

              return GridView.builder(
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: _spacing,
                  mainAxisSpacing: _spacing,
                  mainAxisExtent: cellHeight,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final category = items[index];
                  return _buildCell(
                    context,
                    l10n,
                    category,
                    maxLines: maxLines,
                    isSelected: widget.selectedCategory?.id == category.id,
                  );
                },
              );
            },
          ),
        ),
        if (pageCount > 1) ...[
          const SizedBox(height: 10),
          Semantics(
            label: '${_page + 1}/$pageCount',
            child: SizedBox(
              height: 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(pageCount, (index) {
                  final active = index == _page;
                  return Container(
                    width: active ? 14 : 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: active
                          ? ThemeHelper.primary(context)
                          : Colors.white.withValues(alpha: 0.2),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCell(
    BuildContext context,
    AppLocalizations l10n,
    Category category, {
    required int maxLines,
    required bool isSelected,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onSelected(category),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: isSelected
                ? ThemeHelper.primary(context).withValues(alpha: 0.2)
                : ThemeHelper.surface(context),
            border: Border.all(
              color: isSelected
                  ? ThemeHelper.primary(context)
                  : Colors.white.withValues(alpha: 0.1),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                IconConstants.getIconFromString(category.icon),
                color: isSelected
                    ? ThemeHelper.primary(context)
                    : Colors.white70,
                size: 10, // 缩小一半，从20到10
              ),
              const SizedBox(height: 3),
              Flexible(
                child: Text(
                  CategoryL10n.ofModel(l10n, category),
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? ThemeHelper.primary(context)
                        : Colors.white70,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
