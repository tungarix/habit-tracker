import 'dart:math' as math;

import '../data/database/database.dart';
import 'date_utils.dart';
import 'enums.dart';

/// Cross-habit derived metrics for the dashboard.
///
/// Nothing here is stored in the database — every number is computed at read
/// time from the raw entries. The dataset is tiny and derived columns only
/// create synchronisation bugs.
///
/// Per-habit lifetime metrics (streaks, completion rate) live in `streak.dart`.

/// Completion rate for a single [day] across [habits]: done / scheduled.
///
/// Skipped (–) days are excluded from the denominator, habits created after
/// [day] are ignored, and `null` is returned when nothing was scheduled at all
/// (so an off-day never reads as "0% completed").
double? dayCompletionRate(
  List<Habit> habits,
  Map<int, Map<String, EntryStatus>> statusesByHabit,
  DateTime day,
) {
  final dateStr = formatYmd(day);
  int scheduled = 0;
  int done = 0;
  for (final h in habits) {
    if (dateOnly(h.createdAt).isAfter(day)) continue;
    if (!isScheduledOn(h.scheduledWeekdays, day)) continue;
    final status = (statusesByHabit[h.id] ?? const {})[dateStr];
    if (status == EntryStatus.skipped) continue;
    scheduled++;
    if (status == EntryStatus.done) done++;
  }
  if (scheduled == 0) return null;
  return done / scheduled;
}

/// Per-day completion for the [count] days ending at [endDay], oldest first.
/// Entries are `null` on days with nothing scheduled.
List<double?> dailyCompletionSeries(
  List<Habit> habits,
  Map<int, Map<String, EntryStatus>> statusesByHabit,
  DateTime endDay,
  int count,
) {
  return [
    for (final day in lastDays(endDay, count))
      dayCompletionRate(habits, statusesByHabit, day),
  ];
}

/// Average completion over the [count] days ending at [endDay].
/// Days with nothing scheduled do not drag the average down.
double lastNDaysCompletion(
  List<Habit> habits,
  Map<int, Map<String, EntryStatus>> statusesByHabit,
  DateTime endDay,
  int count,
) {
  final series = dailyCompletionSeries(habits, statusesByHabit, endDay, count)
      .whereType<double>()
      .toList();
  if (series.isEmpty) return 0;
  return series.reduce((a, b) => a + b) / series.length;
}

/// One cell of a habit's heatmap strip.
enum HeatCell {
  /// ✓ done.
  done,

  /// ✗ explicitly missed, or a past scheduled day left untracked.
  missed,

  /// – deliberately skipped.
  skipped,

  /// Off-day, before the habit existed, or today (not yet a miss).
  inactive,
}

/// Heatmap strip for one habit: [count] days ending at [endDay], oldest first.
List<HeatCell> habitHeatmap(
  Habit habit,
  Map<String, EntryStatus> statuses,
  DateTime endDay,
  int count,
) {
  final created = dateOnly(habit.createdAt);
  return [
    for (final day in lastDays(endDay, count))
      switch (statuses[formatYmd(day)]) {
        EntryStatus.done => HeatCell.done,
        EntryStatus.skipped => HeatCell.skipped,
        EntryStatus.missed => HeatCell.missed,
        null => (day.isBefore(created) ||
                !isScheduledOn(habit.scheduledWeekdays, day) ||
                day == endDay)
            ? HeatCell.inactive
            : HeatCell.missed,
      },
  ];
}

/// A heatmap cell plus how "full" it is, so a count habit can show partial
/// progress (7 500 of 10 000 steps) instead of a flat tick.
class HeatPoint {
  final HeatCell cell;

  /// 0..1. Always 1 for a completed bool habit.
  final double intensity;

  const HeatPoint(this.cell, this.intensity);
}

/// Heatmap strip carrying intensity. [values] maps `YYYY-MM-DD` to the amount
/// recorded that day (see `habit_entries.value`).
List<HeatPoint> habitHeatPoints(
  Habit habit,
  Map<String, EntryStatus> statuses,
  Map<String, int> values,
  DateTime endDay,
  int count,
) {
  final cells = habitHeatmap(habit, statuses, endDay, count);
  final days = lastDays(endDay, count);
  final isCount = habit.kind == 'count' && habit.target > 1;

  return [
    for (var i = 0; i < cells.length; i++)
      HeatPoint(
        cells[i],
        switch (cells[i]) {
          HeatCell.done => isCount
              ? ((values[formatYmd(days[i])] ?? habit.target) / habit.target)
                  .clamp(0.0, 1.0)
              : 1.0,
          // A count habit that fell short still shows how far it got.
          HeatCell.missed when isCount =>
            ((values[formatYmd(days[i])] ?? 0) / habit.target).clamp(0.0, 1.0),
          _ => 0.0,
        },
      ),
  ];
}

/// Pearson correlation coefficient, or `null` when it is undefined
/// (fewer than 3 samples, or one of the series is constant).
double? pearson(List<double> xs, List<double> ys) {
  final n = xs.length;
  if (n < 3 || ys.length != n) return null;
  final mx = xs.reduce((a, b) => a + b) / n;
  final my = ys.reduce((a, b) => a + b) / n;
  double cov = 0, vx = 0, vy = 0;
  for (var i = 0; i < n; i++) {
    final dx = xs[i] - mx;
    final dy = ys[i] - my;
    cov += dx * dy;
    vx += dx * dx;
    vy += dy * dy;
  }
  if (vx == 0 || vy == 0) return null;
  return cov / math.sqrt(vx * vy);
}

/// How habit completion relates to the mood recorded on the same day.
class MoodCorrelation {
  /// mood score (1..5) -> average completion rate on days with that mood.
  final Map<int, double> averageByMood;

  /// mood score (1..5) -> how many days contributed.
  final Map<int, int> daysByMood;

  /// Total days that had both a mood and something scheduled.
  final int sampleDays;

  /// Pearson r between mood score and completion rate; null when undefined.
  final double? r;

  const MoodCorrelation({
    required this.averageByMood,
    required this.daysByMood,
    required this.sampleDays,
    required this.r,
  });

  static const empty = MoodCorrelation(
    averageByMood: {},
    daysByMood: {},
    sampleDays: 0,
    r: null,
  );
}

/// Pairs each day that has a mood record with that day's completion rate.
MoodCorrelation moodCompletionCorrelation(
  List<Habit> habits,
  Map<int, Map<String, EntryStatus>> statusesByHabit,
  Map<String, MoodEntry> moodByDate,
  DateTime endDay,
) {
  final sums = <int, double>{};
  final counts = <int, int>{};
  final moodSamples = <double>[];
  final rateSamples = <double>[];

  for (final entry in moodByDate.values) {
    final day = parseYmd(entry.date);
    if (day.isAfter(endDay)) continue;
    final rate = dayCompletionRate(habits, statusesByHabit, day);
    if (rate == null) continue;
    sums[entry.mood] = (sums[entry.mood] ?? 0) + rate;
    counts[entry.mood] = (counts[entry.mood] ?? 0) + 1;
    moodSamples.add(entry.mood.toDouble());
    rateSamples.add(rate);
  }

  return MoodCorrelation(
    averageByMood: {
      for (final e in counts.entries) e.key: sums[e.key]! / e.value,
    },
    daysByMood: counts,
    sampleDays: moodSamples.length,
    r: pearson(moodSamples, rateSamples),
  );
}
