import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/providers.dart';
import 'features/backup/backup_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/habits/habit_edit_dialog.dart';
import 'features/habits/habits_screen.dart';
import 'features/home/grid_screen.dart';
import 'features/stats/stats_screen.dart';
import 'features/tasks/tasks_screen.dart';
import 'shared/theme.dart';

class AktenakApp extends ConsumerWidget {
  const AktenakApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'Aktenak',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      locale: const Locale('tr'),
      supportedLocales: const [Locale('tr'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const HomeShell(),
    );
  }
}

/// Three-tab shell: Bugün + Aylık (grid) + İstatistik. Everything else
/// (add / manage habits, backup) lives behind compact action icons.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

/// Tasks lives in the shell as a tab, so it renders without its own Scaffold.
Widget _embeddedTasks({Key? key}) => TasksScreen(key: key, embedded: true);

const _tabs = ['Panel', 'Aylık', 'Görevler', 'İstatistik'];

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  void _push(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Icon(Icons.check_box_rounded, color: colors.done, size: 24),
            const SizedBox(width: 8),
            const Text('Aktenak',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(width: 16),
            // Tabs scroll on narrow windows instead of overflowing.
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (i, label) in _tabs.indexed) ...[
                      if (i > 0) const SizedBox(width: 6),
                      _TabButton(
                        label: label,
                        selected: _index == i,
                        onTap: () => setState(() => _index = i),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: isDark ? 'Açık tema' : 'Karanlık tema',
            icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
          ),
          IconButton(
            tooltip: 'Alışkanlık ekle',
            icon: const Icon(Icons.add),
            onPressed: () => HabitEditDialog.show(context),
          ),
          IconButton(
            tooltip: 'Alışkanlıkları yönet',
            icon: const Icon(Icons.tune),
            onPressed: () => _push(const HabitsScreen()),
          ),
          IconButton(
            tooltip: 'Yedek & ayarlar',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _push(const BackupScreen()),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: _LazyIndexedStack(
            index: _index,
            builders: const [
              DashboardScreen.new,
              GridScreen.new,
              _embeddedTasks,
              StatsScreen.new,
            ],
          ),
        ),
      ),
    );
  }
}

/// IndexedStack that builds each tab on first visit only. Unvisited tabs cost
/// nothing (no widgets, no provider subscriptions); visited tabs keep their
/// state (scroll offsets, selected month) like a normal IndexedStack.
class _LazyIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget Function({Key? key})> builders;
  const _LazyIndexedStack({required this.index, required this.builders});

  @override
  State<_LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<_LazyIndexedStack> {
  late final List<bool> _visited =
      List<bool>.filled(widget.builders.length, false);

  @override
  Widget build(BuildContext context) {
    _visited[widget.index] = true;
    return IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.builders.length; i++)
          _visited[i] ? widget.builders[i]() : const SizedBox.shrink(),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TabButton({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: selected ? colors.surfaceAlt : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? colors.done : colors.textDim,
            ),
          ),
        ),
      ),
    );
  }
}
