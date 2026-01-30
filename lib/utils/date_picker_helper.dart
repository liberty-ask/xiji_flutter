import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import '../l10n/app_localizations.dart';
import '../utils/theme_helper.dart';
import '../widgets/common/scaled_text.dart';


// 自定义滚动物理效果，限制Web端每次滚动一个项目
class _WebFixedExtentScrollPhysics extends FixedExtentScrollPhysics {
  const _WebFixedExtentScrollPhysics({super.parent});

  @override
  _WebFixedExtentScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _WebFixedExtentScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    // 限制Web端每次滚动最多一个项目的高度
    // 这样可以防止鼠标滚轮一次滚动多个项目
    if (kIsWeb) {
      const itemExtent = 50.0; // 与ListWheelScrollView的itemExtent一致
      // 限制每次滚动的最大距离为一个项目的高度
      if (offset.abs() > itemExtent * 0.8) {
        // 如果滚动距离超过0.8个项目，限制为1个项目
        return offset > 0 ? itemExtent : -itemExtent;
      }
    }
    return super.applyPhysicsToUserOffset(position, offset);
  }
}

// Web端可拖拽的年份选择器
class _DraggableYearWheel extends StatefulWidget {
  final FixedExtentScrollController scrollController;
  final List<int> years;
  final int selectedYear;
  final ValueChanged<int> onYearChanged;

  const _DraggableYearWheel({
    required this.scrollController,
    required this.years,
    required this.selectedYear,
    required this.onYearChanged,
  });

  @override
  State<_DraggableYearWheel> createState() => _DraggableYearWheelState();
}

class _DraggableYearWheelState extends State<_DraggableYearWheel> {
  double? _dragStartY;
  int? _dragStartIndex;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (details) {
        _dragStartY = details.localPosition.dy;
        _dragStartIndex = widget.scrollController.selectedItem;
      },
      onPanUpdate: (details) {
        if (_dragStartY != null && _dragStartIndex != null) {
          final deltaY = _dragStartY! - details.localPosition.dy;
          // 计算应该移动的项目数（每50px一个项目）
          final itemDelta = (deltaY / 50).round();
          final targetIndex = (_dragStartIndex! + itemDelta)
              .clamp(0, widget.years.length - 1);
          
          if (targetIndex != widget.scrollController.selectedItem) {
            widget.scrollController.animateToItem(
              targetIndex,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
            );
          }
        }
      },
      onPanEnd: (details) {
        _dragStartY = null;
        _dragStartIndex = null;
      },
      onPanCancel: () {
        _dragStartY = null;
        _dragStartIndex = null;
      },
      child: ListWheelScrollView.useDelegate(
        itemExtent: 50,
        // Web端使用更大的diameterRatio来减少滚动敏感度，使滚动更平滑
        diameterRatio: 3.5,
        // 使用自定义滚动物理效果，限制Web端每次滚动距离
        physics: const _WebFixedExtentScrollPhysics(),
        controller: widget.scrollController,
        onSelectedItemChanged: (index) {
          widget.onYearChanged(widget.years[index]);
        },
        childDelegate: ListWheelChildBuilderDelegate(
          builder: (context, index) {
            final year = widget.years[index];
            final isSelected = year == widget.selectedYear;
            return Center(
              child: ScaledText(
                '$year${AppLocalizations.of(context)!.yearLabel}',
                style: TextStyle(
                  fontSize: isSelected ? 18 : 16,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected
                      ? ThemeHelper.primary(context)
                      : Colors.white.withValues(alpha: 0.7),
                ),
              ),
            );
          },
          childCount: widget.years.length,
        ),
      ),
    );
  }
}

class DatePickerHelper {
  // 显示年月日选择器
  static Future<Map<String, int>?> showYearMonthDayPicker(
    BuildContext context, {
    required int initialYear,
    required int initialMonth,
    required int initialDay,
    int? startYear,
  }) async {
    final now = DateTime.now();
    final start = startYear ?? 2010;
    final endYear = now.year + 1;
    final years = List.generate(endYear - start + 1, (index) => start + index);

    int selectedYear = initialYear;
    int selectedMonth = initialMonth;
    int selectedDay = initialDay;

    // 获取当月的天数
    int getDaysInMonth(int year, int month) {
      return DateTime(year, month + 1, 0).day;
    }

    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // 确保日期有效
          final daysInMonth = getDaysInMonth(selectedYear, selectedMonth);
          if (selectedDay > daysInMonth) {
            selectedDay = daysInMonth;
          }

          return Dialog(
            backgroundColor: ThemeHelper.surface(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.9,
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 标题栏（固定）
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ScaledText(
                          AppLocalizations.of(context)!.selectDate,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            final today = DateTime.now();
                            setDialogState(() {
                              selectedYear = today.year;
                              selectedMonth = today.month;
                              selectedDay = today.day;
                            });
                          },
                          child: ScaledText(
                            AppLocalizations.of(context)!.today,
                            style: TextStyle(
                              fontSize: 12,
                              color: ThemeHelper.primary(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 年、月、日选择器
                  Container(
                    height: 120,
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: ThemeHelper.surfaceLight(context),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      children: [
                        // 年选择器
                        Expanded(
                          child: CupertinoPicker(
                            itemExtent: 40,
                            onSelectedItemChanged: (index) {
                              setDialogState(() {
                                selectedYear = years[index];
                                // 确保日期有效
                                final daysInMonth = getDaysInMonth(selectedYear, selectedMonth);
                                if (selectedDay > daysInMonth) {
                                  selectedDay = daysInMonth;
                                }
                              });
                            },
                            scrollController: FixedExtentScrollController(
                              initialItem: years.indexOf(selectedYear).clamp(0, years.length - 1),
                            ),
                            children: years.map((year) => Center(
                              child: ScaledText(
                                '$year${AppLocalizations.of(context)!.yearLabel}',
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                              ),
                            )).toList(),
                          ),
                        ),
                        // 月选择器
                        Expanded(
                          child: CupertinoPicker(
                            itemExtent: 40,
                            onSelectedItemChanged: (index) {
                              setDialogState(() {
                                selectedMonth = index + 1;
                                // 确保日期有效
                                final daysInMonth = getDaysInMonth(selectedYear, selectedMonth);
                                if (selectedDay > daysInMonth) {
                                  selectedDay = daysInMonth;
                                }
                              });
                            },
                            scrollController: FixedExtentScrollController(initialItem: selectedMonth - 1),
                            children: List.generate(12, (index) => Center(
                              child: ScaledText(
                                '${index + 1}${AppLocalizations.of(context)!.monthLabel}',
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                              ),
                            )),
                          ),
                        ),
                        // 日选择器
                        Expanded(
                          child: CupertinoPicker(
                            itemExtent: 40,
                            onSelectedItemChanged: (index) {
                              setDialogState(() {
                                selectedDay = index + 1;
                              });
                            },
                            scrollController: FixedExtentScrollController(initialItem: selectedDay - 1),
                            children: List.generate(getDaysInMonth(selectedYear, selectedMonth), (index) => Center(
                              child: ScaledText(
                                '${index + 1}${AppLocalizations.of(context)!.dayLabel}',
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                              ),
                            )),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 按钮栏（固定）
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: ScaledText(
                            AppLocalizations.of(context)!.cancel,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context, {
                              'year': selectedYear,
                              'month': selectedMonth,
                              'day': selectedDay,
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ThemeHelper.primary(context),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: ScaledText(AppLocalizations.of(context)!.confirm),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    return result;
  }

  // 显示年月选择器
  static Future<Map<String, int>?> showYearMonthPicker(
    BuildContext context, {
    required int initialYear,
    required int initialMonth,
    int? startYear,
  }) async {
    final now = DateTime.now();
    final start = startYear ?? 2010;
    final endYear = now.year + 1;
    final years = List.generate(endYear - start + 1, (index) => start + index);

    int selectedYear = initialYear;
    int selectedMonth = initialMonth;

    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: ThemeHelper.surface(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.9,
              maxHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 标题栏（固定）
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ScaledText(
                        AppLocalizations.of(context)!.selectDate,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          final today = DateTime.now();
                          setDialogState(() {
                            selectedYear = today.year;
                            selectedMonth = today.month;
                          });
                        },
                        child: ScaledText(
                          AppLocalizations.of(context)!.today,
                          style: TextStyle(
                            fontSize: 12,
                            color: ThemeHelper.primary(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // 年份和月份选择器
                Container(
                  height: 120,
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: ThemeHelper.surfaceLight(context),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    children: [
                      // 年选择器
                      Expanded(
                        child: CupertinoPicker(
                          itemExtent: 40,
                          onSelectedItemChanged: (index) {
                            setDialogState(() {
                              selectedYear = years[index];
                            });
                          },
                          scrollController: FixedExtentScrollController(
                            initialItem: years.indexOf(selectedYear).clamp(0, years.length - 1),
                          ),
                          children: years.map((year) => Center(
                            child: ScaledText(
                              '$year${AppLocalizations.of(context)!.yearLabel}',
                              style: const TextStyle(color: Colors.white, fontSize: 16),
                            ),
                          )).toList(),
                        ),
                      ),
                      // 月选择器
                      Expanded(
                        child: CupertinoPicker(
                          itemExtent: 40,
                          onSelectedItemChanged: (index) {
                            setDialogState(() {
                              selectedMonth = index + 1;
                            });
                          },
                          scrollController: FixedExtentScrollController(initialItem: selectedMonth - 1),
                          children: List.generate(12, (index) => Center(
                            child: ScaledText(
                              '${index + 1}${AppLocalizations.of(context)!.monthLabel}',
                              style: const TextStyle(color: Colors.white, fontSize: 16),
                            ),
                          )),
                        ),
                      ),
                    ],
                  ),
                ),
                // 按钮栏（固定）
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: ScaledText(
                          AppLocalizations.of(context)!.cancel,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context, {
                            'year': selectedYear,
                            'month': selectedMonth,
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ThemeHelper.primary(context),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: ScaledText(AppLocalizations.of(context)!.confirm),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return result;
  }

  // 显示年份选择器（仅选择年份）
  static Future<int?> showYearPicker(
    BuildContext context, {
    required int initialYear,
    int? startYear,
  }) async {
    final now = DateTime.now();
    final start = startYear ?? 2010;
    final endYear = now.year + 1;
    final years = List.generate(endYear - start + 1, (index) => start + index);

    int selectedYear = initialYear;

    final result = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // 创建ScrollController用于精确控制滚动
          final scrollController = FixedExtentScrollController(
            initialItem: years.indexOf(selectedYear).clamp(0, years.length - 1),
          );
          
          return Dialog(
            backgroundColor: ThemeHelper.surface(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.7,
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题栏（固定）
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ScaledText(
                        AppLocalizations.of(context)!.selectDate,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          final today = DateTime.now();
                          setDialogState(() {
                            selectedYear = today.year;
                          });
                        },
                        child: ScaledText(
                          AppLocalizations.of(context)!.today,
                          style: TextStyle(
                            fontSize: 12,
                            color: ThemeHelper.primary(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // 年份选择器
                Container(
                  height: 120,
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: ThemeHelper.surfaceLight(context),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: CupertinoPicker(
                    itemExtent: 40,
                    onSelectedItemChanged: (index) {
                      setDialogState(() {
                        selectedYear = years[index];
                      });
                    },
                    scrollController: scrollController,
                    children: years.map((year) => Center(
                      child: ScaledText(
                        '$year${AppLocalizations.of(context)!.yearLabel}',
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    )).toList(),
                  ),
                ),
                // 按钮栏（固定）
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: ScaledText(
                          AppLocalizations.of(context)!.cancel,
                          style: TextStyle(
                            color: Colors.white60,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context, selectedYear);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ThemeHelper.primary(context),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: ScaledText(AppLocalizations.of(context)!.confirm),
                      ),
                    ],
                  ),
                ),
                ],
              ),
            ),
          );
        },
      ),
    );

    return result;
  }
}

