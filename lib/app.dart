import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'features/backup/backup_screen.dart';
import 'features/habits/habits_screen.dart';
import 'features/stats/stats_screen.dart';
import 'features/today/today_screen.dart';

class AktenakApp extends StatelessWidget {
  const AktenakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aktenak',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const HomeShell(),
    );
  }
}

/// Top-level navigation. NavigationRail on wide (desktop) layouts, a bottom
/// NavigationBar on narrow ones.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _pages = [
    TodayScreen(),
    HabitsScreen(),
    StatsScreen(),
    BackupScreen(),
  ];

  static const _destinations = [
    _Dest(Icons.today_outlined, Icons.today, 'Bugün'),
    _Dest(Icons.list_alt_outlined, Icons.list_alt, 'Alışkanlıklar'),
    _Dest(Icons.bar_chart_outlined, Icons.bar_chart, 'İstatistik'),
    _Dest(Icons.backup_outlined, Icons.backup, 'Yedek'),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 640;
    final body = IndexedStack(index: _index, children: _pages);

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _Dest {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _Dest(this.icon, this.selectedIcon, this.label);
}
