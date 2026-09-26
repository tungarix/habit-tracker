import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date_utils.dart';
import '../../core/enums.dart';
import '../../core/stats.dart';
import '../../core/streak.dart';
import '../../data/database/database.dart';
import '../../data/providers.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/habit_avatar.dart';

/// Statistics: overview cards, per-habit cards (streak, completion, 30-day
/// trend) and a simple mood ↔ completion correlation view.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final habits = ref.watch(activeHabitsProvider).value ?? const <Habit>[];
    final statusesByHabit = ref.watch(statusesByHabitProvider).value ??
        const <int, Map<String, EntryStatus>>{};
    final moodByDate = ref.watch(moodByDateProvider);
    final overview = ref.watch(overviewProvider);
    final t = ref.watch(todayProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
      children: [
        Text('İstatistik',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text('Serilerin, oranların ve mood ilişkin',
            style: TextStyle(color: colors.textDim)),
        const SizedBox(height: 18),

        _OverviewCards(overview: overview),
        const SizedBox(height: 20),

        if (habits.isNotEmpty) ...[
          const _SectionTitle('Alışkanlıklar'),
          const SizedBox(height: 8),
          for (final h in habits)
            _HabitStatsCard(
              habit: h,
              statuses: statusesByHabit[h.id] ?? const <String, EntryStatus>{},
              todayDate: t,
            ),
          const SizedBox(height: 12),
        ],

        const _SectionTitle('Mood ↔ Tamamlama'),
        const SizedBox(height: 8),
        _MoodCorrelationCard(
          habits: habits,
          statusesByHabit: statusesByHabit,
          moodByDate: moodByDate,
          todayDate: t,
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w700));
  }
}

class _OverviewCards extends StatelessWidget {
  final OverviewStats overview;
  const _OverviewCards({required this.overview});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final cards = [
      _StatCard(label: 'Toplam ✓', value: '${overview.totalMarks}', color: colors.text),
      _StatCard(
          label: 'Mevcut seri',
          value: '${overview.bestCurrent}',
          suffix: 'gün',
          color: colors.done),
      _StatCard(
          label: 'En uzun seri',
          value: '${overview.bestLongest}',
          suffix: 'gün',
          color: colors.gold),
      _StatCard(label: 'Bu ay', value: '${overview.thisMonth}', color: colors.text),
    ];
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 560) {
        return Column(children: [
          Row(children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 12),
            Expanded(child: cards[1]),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: cards[2]),
            const SizedBox(width: 12),
            Expanded(child: cards[3]),
          ]),
        ]);
      }
      return Row(children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: cards[i]),
        ]
      ]);
    });
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? suffix;
  final Color color;
  const _StatCard(
      {required this.label, required this.value, this.suffix, required this.color});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: colors.textDim, fontSize: 13)),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 30, fontWeight: FontWeight.bold, color: color)),
                ),
                if (suffix != null) ...[
                  const SizedBox(width: 5),
                  Text(suffix!,
                      style: TextStyle(color: colors.textDim, fontSize: 14)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One habit's card: streak numbers, completion rate and a 30-day strip.
class _HabitStatsCard extends StatelessWidget {
  final Habit habit;
  final Map<String, EntryStatus> statuses;
  final DateTime todayDate;
  const _HabitStatsCard({
    required this.habit,
    required this.statuses,
    required this.todayDate,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final stats = computeStats(habit, statuses, todayDate);
    final category = HabitCategory.tryParse(habit.category);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                HabitAvatar(habit: habit, size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(habit.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                if (category != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(category.label,
                        style: TextStyle(fontSize: 11, color: colors.textDim)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _miniStat(colors, 'Mevcut seri',
                    '${stats.streak.current} gün', colors.done),
                _miniStat(colors, 'En uzun',
                    '${stats.streak.longest} gün', colors.gold),
                _miniStat(colors, 'Tamamlama',
                    '%${(stats.completionRate * 100).round()}', colors.text),
              ],
            ),
            const SizedBox(height: 12),
            Text('Son 30 gün',
                style: TextStyle(fontSize: 11, color: colors.textDim)),
            const SizedBox(height: 6),
            _TrendStrip(habit: habit, statuses: statuses, todayDate: todayDate),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(AppColors colors, String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: colors.textDim)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

/// 30 small squares, oldest to newest: ✓ green, ✗/empty-past red-tinted,
/// – grey, off-days and pre-creation faint.
class _TrendStrip extends StatelessWidget {
  final Habit habit;
  final Map<String, EntryStatus> statuses;
  final DateTime todayDate;
  const _TrendStrip({
    required this.habit,
    required this.statuses,
    required this.todayDate,
  });

  static const _days = 30;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    // Which cell is which state is a logic question, answered by core/.
    final cells = habitHeatmap(habit, statuses, todayDate, _days);
    final days = lastDays(todayDate, _days);

    return LayoutBuilder(builder: (context, c) {
      final width = ((c.maxWidth - (_days - 1) * 2) / _days).clamp(4.0, 12.0);
      return Row(
        children: [
          for (var i = 0; i < _days; i++) ...[
            Tooltip(
              message: formatYmd(days[i]),
              waitDuration: const Duration(milliseconds: 400),
              child: Container(
                width: width,
                height: 14,
                decoration: BoxDecoration(
                  color: _fillFor(colors, cells[i]),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            if (i < _days - 1) const SizedBox(width: 2),
          ],
        ],
      );
    });
  }

  static Color _fillFor(AppColors colors, HeatCell cell) => switch (cell) {
        HeatCell.done => colors.done,
        HeatCell.skipped => colors.skipped,
        // A past scheduled day left untracked reads as a miss, just softer.
        HeatCell.missed => colors.missed,
        HeatCell.inactive => colors.idle,
      };
}

/// Average daily completion rate grouped by that day's mood: one bar per mood.
class _MoodCorrelationCard extends StatelessWidget {
  final List<Habit> habits;
  final Map<int, Map<String, EntryStatus>> statusesByHabit;
  final Map<String, MoodEntry> moodByDate;
  final DateTime todayDate;
  const _MoodCorrelationCard({
    required this.habits,
    required this.statusesByHabit,
    required this.moodByDate,
    required this.todayDate,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    // All arithmetic lives in core/stats.dart; this widget only draws it.
    final correlation = moodCompletionCorrelation(
      habits,
      statusesByHabit,
      moodByDate,
      todayDate,
    );
    final totalDays = correlation.sampleDays;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: totalDays < 3
            ? SizedBox(
                height: 120,
                child: Center(
                  child: Text(
                    'Yeterli veri yok — birkaç gün mood işaretle,\n'
                    'mood ile tamamlama ilişkisi burada belirecek.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.textDim, fontSize: 13),
                  ),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'O günkü mood\'a göre ortalama tamamlama oranı '
                    '($totalDays gün)',
                    style: TextStyle(fontSize: 12, color: colors.textDim),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 150,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final mood in Mood.values) ...[
                          Expanded(
                            child: _moodBar(
                              colors,
                              mood,
                              correlation.averageByMood[mood.value],
                              correlation.daysByMood[mood.value] ?? 0,
                            ),
                          ),
                          if (mood != Mood.values.last) const SizedBox(width: 10),
                        ],
                      ],
                    ),
                  ),
                  if (correlation.r != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _correlationLabel(correlation.r!),
                      style: TextStyle(fontSize: 12, color: colors.textDim),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _moodBar(AppColors colors, Mood mood, double? avgRate, int count) {
    final has = avgRate != null;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          has ? '%${(avgRate * 100).round()}' : '—',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: has ? colors.text : colors.textDim),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: has ? avgRate.clamp(0.03, 1.0) : 0.03,
              child: Container(
                decoration: BoxDecoration(
                  color: has ? colors.done : colors.idle,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(5)),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(mood.emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 2),
        Text(
          count > 0 ? '$count gün' : '',
          style: TextStyle(fontSize: 10, color: colors.textDim),
        ),
      ],
    );
  }

  static String _correlationLabel(double r) {
    final strength = r.abs() >= 0.6
        ? 'güçlü'
        : r.abs() >= 0.3
            ? 'orta'
            : 'zayıf';
    final direction = r >= 0 ? 'pozitif' : 'negatif';
    return 'Korelasyon: r = ${r.toStringAsFixed(2)} ($strength $direction ilişki)';
  }
}
