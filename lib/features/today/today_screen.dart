import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/date_utils.dart';
import '../../data/models/habit_today_view.dart';
import '../../data/providers.dart';
import '../../shared/widgets/habit_avatar.dart';
import '../../shared/widgets/streak_badge.dart';

/// Main screen: today's habits with one-tap done / not-done.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewsAsync = ref.watch(todayViewsProvider);
    final dateLabel = DateFormat('EEEE, d MMMM', 'tr').format(DateTime.now());

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bugün', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 2),
                  Text(
                    _capitalize(dateLabel),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: viewsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Hata: $e')),
                data: (views) => _TodayList(views: views),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _TodayList extends ConsumerWidget {
  final List<HabitTodayView> views;
  const _TodayList({required this.views});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (views.isEmpty) {
      return const _EmptyState();
    }

    final scheduled = views.where((v) => v.scheduledToday).toList();
    final notScheduled = views.where((v) => !v.scheduledToday).toList();

    final doneCount = scheduled.where((v) => v.doneToday).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      children: [
        if (scheduled.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: _ProgressBar(done: doneCount, total: scheduled.length),
          ),
        for (final v in scheduled) _HabitTile(view: v),
        if (notScheduled.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 16, 8, 8),
            child: Text('Bugün planlı değil', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          for (final v in notScheduled) _HabitTile(view: v, dimmed: true),
        ],
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final int done;
  final int total;
  const _ProgressBar({required this.done, required this.total});

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : done / total;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$done / $total tamamlandı',
                style: Theme.of(context).textTheme.bodyMedium),
            Text('%${(pct * 100).round()}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scheme.primary,
                    )),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 8,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

class _HabitTile extends ConsumerWidget {
  final HabitTodayView view;
  final bool dimmed;
  const _HabitTile({required this.view, this.dimmed = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habit = view.habit;
    final color = Color(habit.colorValue);
    final dateStr = formatYmd(today());

    return Opacity(
      opacity: dimmed ? 0.6 : 1,
      child: Card(
        child: InkWell(
          onTap: () => ref.read(habitRepositoryProvider).toggle(habit.id, dateStr),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                HabitAvatar(habit: habit),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(habit.name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      if (habit.description != null && habit.description!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            habit.description!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Theme.of(context).colorScheme.outline),
                          ),
                        ),
                    ],
                  ),
                ),
                StreakBadge(streak: view.streak.current),
                const SizedBox(width: 12),
                _CheckCircle(done: view.doneToday, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckCircle extends StatelessWidget {
  final bool done;
  final Color color;
  const _CheckCircle({required this.done, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? color : Colors.transparent,
        border: Border.all(color: done ? color : Theme.of(context).colorScheme.outline, width: 2),
      ),
      child: done
          ? const Icon(Icons.check, color: Colors.white, size: 20)
          : const SizedBox.shrink(),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.task_alt, size: 64, color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(height: 16),
          const Text('Henüz alışkanlık yok', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('“Alışkanlıklar” sekmesinden ilkini ekle.',
              style: TextStyle(color: Theme.of(context).colorScheme.outline)),
        ],
      ),
    );
  }
}
