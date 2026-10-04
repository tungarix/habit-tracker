import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/date_utils.dart';
import '../../core/enums.dart';
import '../../core/stats.dart';
import '../../data/database/database.dart';
import '../../data/models/habit_today_view.dart';
import '../../data/providers.dart';
import '../../shared/habit_actions.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/status_mark.dart';
import '../habits/habit_edit_dialog.dart';
import '../tasks/widgets/week_tasks_card.dart';
import 'widgets/focus_card.dart';
import 'widgets/heat_strip.dart';
import 'widgets/mood_strip.dart';

/// The screen the app opens to: today's marking, momentum, and what's next —
/// all without a click. Density is deliberate; the hierarchy does the work.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  // Layout thresholds. Below the first the app is effectively a phone.
  static const _twoColumn = 760.0;
  static const _threeColumn = 1180.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habits = ref.watch(activeHabitsProvider).value;

    if (habits == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(builder: (context, c) {
      final columns = c.maxWidth >= _threeColumn
          ? 3
          : c.maxWidth >= _twoColumn
              ? 2
              : 1;

      final today = _TodayCard(hasHabits: habits.isNotEmpty);
      final momentum = _MomentumCard(habits: habits);
      const focus = FocusCard();
      const tasks = WeekTasksCard();
      const mood = _MoodCard();

      return ListView(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 24),
        children: [
          const _HeaderBar(),
          const SizedBox(height: 14),
          switch (columns) {
            // No IntrinsicHeight here: the heat strips measure themselves with
            // a LayoutBuilder, which cannot answer intrinsic-size queries.
            // Columns simply size to their own content.
            3 => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 30, child: Column(children: [today, mood])),
                  const SizedBox(width: 12),
                  Expanded(flex: 40, child: momentum),
                  const SizedBox(width: 12),
                  const Expanded(
                    flex: 30,
                    child: Column(children: [focus, tasks]),
                  ),
                ],
              ),
            2 => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Column(children: [today, momentum, mood])),
                  const SizedBox(width: 12),
                  const Expanded(child: Column(children: [focus, tasks])),
                ],
              ),
            _ => Column(children: [today, momentum, focus, tasks, mood]),
          },
        ],
      );
    });
  }
}

/// Date, the day's headline number, and the week's trend.
class _HeaderBar extends ConsumerWidget {
  const _HeaderBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final day = ref.watch(todayProvider);
    final progress = ref.watch(todayProgressProvider);
    final week = ref.watch(weekCompletionProvider);
    final tasks = ref.watch(taskSummaryProvider);

    final label = DateFormat('d MMMM EEEE', 'tr').format(day);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              Text(
                label[0].toUpperCase() + label.substring(1),
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              ),
              _HeaderStat(
                value: '${progress.done}/${progress.total}',
                label: 'alışkanlık',
                color: progress.total > 0 && progress.done == progress.total
                    ? colors.done
                    : colors.text,
              ),
              _HeaderStat(
                value: '%${(week * 100).round()}',
                label: '7 günlük',
                color: colors.text,
              ),
              if (tasks.open > 0)
                _HeaderStat(
                  value: '${tasks.open}',
                  label: tasks.overdue > 0
                      ? 'görev · ${tasks.overdue} geciken'
                      : 'açık görev',
                  color: tasks.overdue > 0 ? colors.missed : colors.text,
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOut,
              tween: Tween(begin: 0, end: progress.ratio),
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 6,
                color: colors.done,
                backgroundColor: colors.idle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _HeaderStat({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(value,
            style: kTabularNums.copyWith(
                fontSize: 19, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 12, color: colors.textDim)),
      ],
    );
  }
}

/// Today's habits — the one thing that must be doable without a click.
class _TodayCard extends ConsumerWidget {
  final bool hasHabits;
  const _TodayCard({required this.hasHabits});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final views = ref.watch(todayViewsProvider).value ?? const <HabitTodayView>[];
    final scheduled = views.where((v) => v.scheduledToday).toList();
    final rest = views.where((v) => !v.scheduledToday).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CardTitle(icon: Icons.today_outlined, text: 'Bugün'),
            const SizedBox(height: 10),
            if (!hasHabits)
              _EmptyInvite(
                message: 'Henüz alışkanlık yok.',
                actionLabel: 'İlk alışkanlığını ekle',
                onTap: () => HabitEditDialog.show(context),
              )
            else ...[
              for (final v in scheduled) _TodayRow(view: v),
              if (rest.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Bugün planlı değil',
                    style: TextStyle(fontSize: 11, color: colors.textDim)),
                const SizedBox(height: 4),
                for (final v in rest) _TodayRow(view: v, dimmed: true),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _TodayRow extends ConsumerWidget {
  final HabitTodayView view;
  final bool dimmed;
  const _TodayRow({required this.view, this.dimmed = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final habit = view.habit;
    final day = ref.watch(todayProvider);
    final isCount =
        habit.kind == HabitKind.count.storageName && habit.target > 1;
    final value =
        ref.watch(valuesByHabitProvider)[habit.id]?[formatYmd(day)] ?? 0;

    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Semantics(
        button: true,
        label: '${habit.name}, ${view.status?.name ?? 'işaretlenmedi'}',
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () =>
                markHabit(context, ref, habit, day, currentValue: value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Color(habit.colorValue),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(habit.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w600)),
                        if (isCount)
                          Text('$value / ${habit.target}',
                              style: kTabularNums.copyWith(
                                  fontSize: 11, color: colors.textDim)),
                      ],
                    ),
                  ),
                  if (view.streak.current > 0) ...[
                    Text('${view.streak.current}',
                        style: kTabularNums.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: colors.done)),
                    const SizedBox(width: 2),
                    Text('🔥', style: TextStyle(fontSize: 10)),
                    const SizedBox(width: 8),
                  ],
                  StatusMark(status: view.status, size: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Per-habit momentum: streak, 30-day heat strip, 7-day completion.
class _MomentumCard extends ConsumerWidget {
  final List<Habit> habits;
  const _MomentumCard({required this.habits});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final day = ref.watch(todayProvider);
    final dayStartHour = ref.watch(dayStartHourProvider);
    final statuses = ref.watch(statusesByHabitProvider).value ??
        const <int, Map<String, EntryStatus>>{};
    final values = ref.watch(valuesByHabitProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _CardTitle(
                      icon: Icons.grid_on_outlined, text: 'Son 30 gün'),
                ),
                Text('7g',
                    style: TextStyle(fontSize: 10.5, color: colors.textDim)),
              ],
            ),
            const SizedBox(height: 12),
            if (habits.isEmpty)
              _EmptyInvite(
                message: 'Izgara boş.',
                actionLabel: 'Alışkanlık ekle',
                onTap: () => HabitEditDialog.show(context),
              )
            else
              for (final h in habits) ...[
                _MomentumRow(
                  habit: h,
                  statuses: statuses[h.id] ?? const {},
                  values: values[h.id] ?? const {},
                  day: day,
                  dayStartHour: dayStartHour,
                ),
                if (h != habits.last) const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

class _MomentumRow extends StatelessWidget {
  final Habit habit;
  final Map<String, EntryStatus> statuses;
  final Map<String, int> values;
  final DateTime day;
  final int dayStartHour;

  const _MomentumRow({
    required this.habit,
    required this.statuses,
    required this.values,
    required this.day,
    required this.dayStartHour,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final color = Color(habit.colorValue);
    final points = habitHeatPoints(
      habit,
      statuses,
      values,
      day,
      30,
      dayStartHour: dayStartHour,
    );
    final week = habitHeatmap(
      habit,
      statuses,
      day,
      7,
      dayStartHour: dayStartHour,
    );
    final weekDone = week.where((c) => c == HeatCell.done).length;
    final weekActive = week.where((c) => c != HeatCell.inactive).length;
    final pct = weekActive == 0 ? 0 : (weekDone / weekActive * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(habit.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: color)),
            ),
            const SizedBox(width: 8),
            Text('%$pct',
                style: kTabularNums.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: pct >= 70
                        ? colors.done
                        : pct >= 40
                            ? colors.text
                            : colors.textDim)),
          ],
        ),
        const SizedBox(height: 4),
        HeatStrip(points: points, endDay: day, color: color),
      ],
    );
  }
}

/// Mood: one-tap for today, 30-day line underneath.
class _MoodCard extends ConsumerWidget {
  const _MoodCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(todayProvider);
    final entry = ref.watch(todayMoodProvider);
    final selected = Mood.fromValue(entry?.mood);
    final moodByDate = ref.watch(moodByDateProvider);
    final colors = AppColors.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _CardTitle(
                    icon: Icons.mood_outlined,
                    text: selected?.label ?? 'Bugün nasılsın?',
                  ),
                ),
                if (selected != null)
                  IconButton(
                    tooltip: 'Not',
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    icon: Icon(
                      (entry?.note?.isNotEmpty ?? false)
                          ? Icons.sticky_note_2_outlined
                          : Icons.edit_note,
                      color: colors.textDim,
                    ),
                    onPressed: () => _editNote(
                        context, ref, formatYmd(day), entry?.note),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            MoodPicker(
              selected: selected,
              onTap: (mood) {
                final repo = ref.read(habitRepositoryProvider);
                final dateStr = formatYmd(day);
                mood == selected
                    ? repo.clearMood(dateStr)
                    : repo.setMood(dateStr, mood.value);
              },
            ),
            if (entry?.note?.isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              Text(entry!.note!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontStyle: FontStyle.italic,
                      color: colors.textDim)),
            ],
            const SizedBox(height: 6),
            MoodStrip(moodByDate: moodByDate, endDay: day),
          ],
        ),
      ),
    );
  }

  Future<void> _editNote(
    BuildContext context,
    WidgetRef ref,
    String dateStr,
    String? current,
  ) async {
    final controller = TextEditingController(text: current ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bugüne kısa not'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 200,
          decoration: const InputDecoration(hintText: 'Örn. yoğun bir gündü'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Kaydet')),
        ],
      ),
    );
    if (result != null) {
      final trimmed = result.trim();
      await ref
          .read(habitRepositoryProvider)
          .setMoodNote(dateStr, trimmed.isEmpty ? null : trimmed);
    }
    controller.dispose();
  }
}

class _CardTitle extends StatelessWidget {
  final IconData icon;
  final String text;
  const _CardTitle({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      children: [
        Icon(icon, size: 17, color: colors.textDim),
        const SizedBox(width: 8),
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w700, color: colors.text)),
        ),
      ],
    );
  }
}

/// An empty state is an invitation, not a notice.
class _EmptyInvite extends StatelessWidget {
  final String message;
  final String actionLabel;
  final VoidCallback onTap;
  const _EmptyInvite({
    required this.message,
    required this.actionLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: TextStyle(fontSize: 12, color: colors.textDim)),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: onTap,
            icon: const Icon(Icons.add, size: 18),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}
