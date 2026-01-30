import 'package:flutter/material.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';

class BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context)!;
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: onTap,
      type: BottomNavigationBarType.fixed,
      backgroundColor: ThemeHelper.surface(context),
      selectedItemColor: ThemeHelper.primary(context),
      unselectedItemColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
      selectedFontSize: 10,
      unselectedFontSize: 10,
      items: [
        BottomNavigationBarItem(
          icon: Icon(Icons.home),
          label: appLocalizations.home,
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.calendar_month),
          label: appLocalizations.calendar,
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.add_circle),
          label: '',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.pie_chart),
          label: appLocalizations.statistics,
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person),
          label: appLocalizations.profile,
        ),
      ],
    );
  }
}

