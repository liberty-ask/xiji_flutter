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

/// 分类网格：一次铺开全部分类，不分页、无页码点。
///
/// 两种形态：
/// - 默认（[adaptiveLabels] = false）：6 列 + 1.1 比例 + 单行标签（导入预览弹层沿用）
/// - 自适应（[adaptiveLabels] = true）：按可用宽度算列数，格子接近正方形
class CategorySelector extends StatelessWidget {
  final List<Category> categories;
  final Category? selectedCategory;

  /// 当前交易方向：0 收入 / 1 支出 / 2 不计收支（仅用于软排序）
  final int direction;

  /// 近 90 天使用频次，key 为 `分类ID|方向`；缺省时按提示倾向排序
  final Map<String, int> usageCounts;
  final Function(Category) onSelected;

  /// 固定列数：null 时按宽度自适应（[adaptiveLabels] 为 true）或默认 6 列
  final int? columns;

  /// 是否启用自适应网格：列数随宽度增加、格子接近正方形、英文长名允许两行
  final bool adaptiveLabels;

  static const double spacing = 6;

  /// 目标格宽：中文标签短，英文标签长，给更宽的格子好折两行
  static const double _targetCellWidthZh = 56;
  static const double _targetCellWidthEn = 74;

  const CategorySelector({
    super.key,
    required this.categories,
    this.selectedCategory,
    this.direction = 1,
    this.usageCounts = const {},
    required this.onSelected,
    this.columns,
    this.adaptiveLabels = false,
  });

  /// 给定可用宽度与列数时每格的宽度（含间距修正），测试与布局共用同一套算法
  static double cellWidthFor(double availableWidth, int columns) {
    if (columns <= 0) return 0;
    return (availableWidth - (columns - 1) * spacing) / columns;
  }

  /// 按可用宽度推算列数：让格子宽度贴近目标值，宽屏自然增加列数，
  /// 避免格子被拉成巨大方块
  static int columnsFor(double availableWidth, {required bool isEnglish}) {
    final target = isEnglish ? _targetCellWidthEn : _targetCellWidthZh;
    final raw = ((availableWidth + spacing) / (target + spacing)).round();
    return raw.clamp(4, 10);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sorted =
        sortedCategoriesForDirection(categories, direction, usageCounts);
    if (sorted.isEmpty) {
      return const SizedBox.shrink();
    }

    if (!adaptiveLabels) {
      return _buildGrid(
        context,
        l10n,
        sorted,
        columns: columns ?? 6,
        aspectRatio: 1.1,
        maxLines: 1,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 宽度不可用时按手机常见宽度兜底，避免出现无限宽
        final width =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 360.0;
        final isEnglish =
            Localizations.localeOf(context).languageCode == 'en';
        final resolved =
            columns ?? columnsFor(width, isEnglish: isEnglish);
        return _buildGrid(
          context,
          l10n,
          sorted,
          columns: resolved,
          // 正方形格子：宽度决定高度，多出来的垂直空间留给区块间距
          aspectRatio: 1.0,
          maxLines: isEnglish ? 2 : 1,
          cellWidth: cellWidthFor(width, resolved),
        );
      },
    );
  }

  Widget _buildGrid(
    BuildContext context,
    AppLocalizations l10n,
    List<Category> sorted, {
    required int columns,
    required double aspectRatio,
    required int maxLines,
    double? cellWidth,
  }) {
    final iconSize = cellWidth == null
        ? 14.0
        : (cellWidth * 0.28).clamp(12.0, 20.0);
    final fontSize = cellWidth == null
        ? 11.0
        : (cellWidth * 0.2).clamp(10.0, 13.0);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
        childAspectRatio: aspectRatio,
      ),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final category = sorted[index];
        return _buildCell(
          context,
          l10n,
          category,
          maxLines: maxLines,
          iconSize: iconSize,
          fontSize: fontSize,
          isSelected: selectedCategory?.id == category.id,
        );
      },
    );
  }

  Widget _buildCell(
    BuildContext context,
    AppLocalizations l10n,
    Category category, {
    required int maxLines,
    required double iconSize,
    required double fontSize,
    required bool isSelected,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onSelected(category),
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
                size: iconSize,
              ),
              SizedBox(height: iconSize >= 14 ? 5 : 3),
              Flexible(
                child: Text(
                  CategoryL10n.ofModel(l10n, category),
                  style: TextStyle(
                    fontSize: fontSize,
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
