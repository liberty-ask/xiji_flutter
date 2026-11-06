import 'package:flutter/material.dart';
import '../../models/category.dart';
import '../../utils/icon_constants.dart';
import '../../utils/theme_helper.dart';

class CategorySelector extends StatelessWidget {
  final List<Category> categories;
  final Category? selectedCategory;
  final Function(Category) onSelected;

  const CategorySelector({
    super.key,
    required this.categories,
    this.selectedCategory,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6, // 增加到6列，使每个分类框更小
        crossAxisSpacing: 6, // 减小间距
        mainAxisSpacing: 6,
        childAspectRatio: 1.1, // 调整宽高比，使容器更扁平更小
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        final isSelected = selectedCategory?.name == category.name;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onSelected(category),
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8), // 减小圆角
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
                Text(
                  category.name,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? ThemeHelper.primary(context)
                        : Colors.white70,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          ),
        );
      },
    );
  }
}

