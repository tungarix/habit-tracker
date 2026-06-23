import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/streak.dart';
import '../../data/database/database.dart';
import '../../data/providers.dart';
import '../../shared/widgets/habit_avatar.dart';
import 'widgets/heatmap.dart';
import 'widgets/trend_chart.dart';

/// Per-habit statistics: streaks, completion rate, heatmap and trend.
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  int? _selectedId;

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeHabitsProvider).value ?? const <Habit>[];
    final archived = ref.watch(archivedHabitsProvider).value ?? const <Habit>[];
    final all = [...active, ...archived];

    // Default to the first habit, and keep selection valid as data changes.
    final selected = _resolveSelected(all);

    return Scaffold(
      body: SafeArea(
        child: all.isEmpty
            ? const Center(child: Text('İstatistik için önce bir alışkanlık ekle.'))
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                children: [
                  Text('İstatistik', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 16),
                  _HabitSelector(
                    habits: all,
                    selectedId: selected?.id,
                    onChanged: (id) => setState(() => _selectedId = id),
                  ),
                  const SizedBox(height: 20),
                  if (selected != null) _StatsBody(habit: selected),
                ],
              ),
      ),
    );
  }

  Habit? _resolveSelected(List<Habit> all) {
    if (all.isEmpty) return null;
    for (final h in all) {
      if (h.id == _selectedId) return h;
    }
    return all.first;
  }
}

class _HabitSelector extends StatelessWidget {
  final List<Habit> habits;
  final int? selectedId;
  final ValueChanged<int> onChanged;
  const _HabitSelector({
    required this.habits,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      initialValue: selectedId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Alışkanlık',
        border: OutlineInputBorder(),
      ),
      items: [
        for (final h in habits)
          DropdownMenuItem(
            value: h.id,
            child: Row(
              children: [
                HabitAvatar(habit: h, size: 28),
                const SizedBox(width: 10),
                Flexible(child: Text(h.name, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _StatsBody extends ConsumerWidget {
  final Habit habit;
  const _StatsBody({required this.habit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(habitStatsProvider(habit.id));
    final doneDates = ref.watch(habitDoneDatesProvider(habit.id));
    final stats = statsAsync.value ?? HabitStats.empty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Mevcut seri',
                value: '${stats.streak.current}',
                suffix: 'gün',
                icon: Icons.local_fire_department,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'En uzun seri',
                value: '${stats.streak.longest}',
                suffix: 'gün',
                icon: Icons.emoji_events,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Tamamlanma',
                value: '%${(stats.completionRate * 100).round()}',
                icon: Icons.percent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Toplam',
                value: '${stats.totalDone}/${stats.totalScheduled}',
                icon: Icons.check_circle_outline,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _SectionTitle('Takvim'),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: HabitHeatmap(habit: habit, doneDates: doneDates),
          ),
        ),
        const SizedBox(height: 24),
        _SectionTitle('Haftalık trend'),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
            child: TrendChart(habit: habit, doneDates: doneDates),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.titleMedium);
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? suffix;
  final IconData icon;
  const _StatCard({
    required this.label,
    required this.value,
    this.suffix,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(label,
                      style: TextStyle(color: scheme.outline, fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                if (suffix != null) ...[
                  const SizedBox(width: 4),
                  Text(suffix!, style: TextStyle(color: scheme.outline)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
