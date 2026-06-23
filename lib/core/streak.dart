import '../data/database/database.dart';
import 'date_utils.dart';

/// Current and longest streak for a habit.
class StreakInfo {
  final int current;
  final int longest;
  const StreakInfo({required this.current, required this.longest});

  static const empty = StreakInfo(current: 0, longest: 0);
}

/// Aggregate stats for a single habit over its whole life.
class HabitStats {
  final int totalScheduled;
  final int totalDone;
  final double completionRate; // 0..1
  final StreakInfo streak;

  const HabitStats({
    required this.totalScheduled,
    required this.totalDone,
    required this.completionRate,
    required this.streak,
  });

  static const empty = HabitStats(
    totalScheduled: 0,
    totalDone: 0,
    completionRate: 0,
    streak: StreakInfo.empty,
  );
}

/// Computes the current and longest streak for [habit].
///
/// Rules (per the blueprint):
/// - Only scheduled days count. Unscheduled days are skipped and never break
///   a streak.
/// - Current streak: counted backwards from today over scheduled days while
///   `done` is true. Today not being done *yet* does not break the streak.
/// - Longest streak: the longest unbroken run of scheduled `done` days across
///   the habit's whole history.
StreakInfo computeStreaks(Habit habit, Set<String> doneDates, DateTime todayDate) {
  final start = dateOnly(habit.createdAt);
  if (start.isAfter(todayDate)) return StreakInfo.empty;

  // Longest: walk forward from creation.
  int longest = 0;
  int run = 0;
  for (var d = start; !d.isAfter(todayDate); d = d.add(const Duration(days: 1))) {
    if (!isScheduledOn(habit.scheduledWeekdays, d)) continue;
    if (doneDates.contains(formatYmd(d))) {
      run++;
      if (run > longest) longest = run;
    } else {
      run = 0;
    }
  }

  // Current: walk backward from today.
  int current = 0;
  bool isToday = true;
  for (var d = todayDate; !d.isBefore(start); d = d.subtract(const Duration(days: 1))) {
    if (isScheduledOn(habit.scheduledWeekdays, d)) {
      final done = doneDates.contains(formatYmd(d));
      if (done) {
        current++;
      } else if (isToday) {
        // Today not ticked yet: grace, don't break.
      } else {
        break;
      }
    }
    isToday = false;
  }

  return StreakInfo(current: current, longest: longest);
}

/// Computes lifetime completion stats for [habit].
HabitStats computeStats(Habit habit, Set<String> doneDates, DateTime todayDate) {
  final start = dateOnly(habit.createdAt);
  int scheduled = 0;
  int done = 0;
  for (var d = start; !d.isAfter(todayDate); d = d.add(const Duration(days: 1))) {
    if (!isScheduledOn(habit.scheduledWeekdays, d)) continue;
    scheduled++;
    if (doneDates.contains(formatYmd(d))) done++;
  }
  final rate = scheduled == 0 ? 0.0 : done / scheduled;
  return HabitStats(
    totalScheduled: scheduled,
    totalDone: done,
    completionRate: rate,
    streak: computeStreaks(habit, doneDates, todayDate),
  );
}
