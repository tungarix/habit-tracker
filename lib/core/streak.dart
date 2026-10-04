import '../data/database/database.dart';
import 'constants.dart';
import 'date_utils.dart';
import 'enums.dart';

/// Current and longest streak for a habit.
class StreakInfo {
  final int current;
  final int longest;
  const StreakInfo({required this.current, required this.longest});

  static const empty = StreakInfo(current: 0, longest: 0);
}

/// Aggregate stats for a single habit over its whole life.
class HabitStats {
  /// Scheduled days since creation, not counting skipped (–) days.
  final int totalScheduled;
  final int totalDone;
  final int totalSkipped;
  final double completionRate; // totalDone / totalScheduled, 0..1
  final StreakInfo streak;

  const HabitStats({
    required this.totalScheduled,
    required this.totalDone,
    required this.totalSkipped,
    required this.completionRate,
    required this.streak,
  });

  static const empty = HabitStats(
    totalScheduled: 0,
    totalDone: 0,
    totalSkipped: 0,
    completionRate: 0,
    streak: StreakInfo.empty,
  );
}

/// Computes the current and longest streak for [habit].
///
/// [statuses] maps `YYYY-MM-DD` to the day's explicit mark; a missing key is
/// an untracked (boş) day.
///
/// Rules:
/// - Only scheduled days count. Unscheduled days are ignored entirely.
/// - Skipped (–) days are neutral: they neither extend nor break a streak.
/// - An explicit missed (✗) breaks the streak — today included.
/// - An untracked past scheduled day breaks the streak; today being untracked
///   *yet* does not (grace).
///
/// The habit's first day is the *tracking* day it was created on ([dayOf] with
/// [dayStartHour]), not the calendar day: a habit added at 01:30 started on the
/// day that is still ending, and a mark made that night must count.
StreakInfo computeStreaks(
  Habit habit,
  Map<String, EntryStatus> statuses,
  DateTime todayDate, {
  int dayStartHour = AppConstants.defaultDayStartHour,
}) {
  final start = dayOf(habit.createdAt, dayStartHour: dayStartHour);
  if (start.isAfter(todayDate)) return StreakInfo.empty;

  // Longest: walk forward from creation.
  int longest = 0;
  int run = 0;
  for (var d = start; !d.isAfter(todayDate); d = nextDay(d)) {
    if (!isScheduledOn(habit.scheduledWeekdays, d)) continue;
    final status = statuses[formatYmd(d)];
    if (status == EntryStatus.skipped) continue;
    if (status == EntryStatus.done) {
      run++;
      if (run > longest) longest = run;
    } else if (d == todayDate && status == null) {
      // Today untracked: grace, the run is still alive (but not extended).
    } else {
      run = 0;
    }
  }

  // Current: walk backward from today.
  int current = 0;
  bool isToday = true;
  for (var d = todayDate; !d.isBefore(start); d = previousDay(d)) {
    if (isScheduledOn(habit.scheduledWeekdays, d)) {
      final status = statuses[formatYmd(d)];
      if (status == EntryStatus.done) {
        current++;
      } else if (status == EntryStatus.skipped) {
        // Neutral: keep walking.
      } else if (status == null && isToday) {
        // Today not marked yet: grace, don't break.
      } else {
        break;
      }
    }
    isToday = false;
  }

  return StreakInfo(current: current, longest: longest);
}

/// Computes lifetime completion stats for [habit].
///
/// Skipped days are left out of the denominator: a deliberately skipped day
/// should not drag the completion rate down. [dayStartHour] decides which
/// tracking day the habit was created on, as in [computeStreaks].
HabitStats computeStats(
  Habit habit,
  Map<String, EntryStatus> statuses,
  DateTime todayDate, {
  int dayStartHour = AppConstants.defaultDayStartHour,
}) {
  final start = dayOf(habit.createdAt, dayStartHour: dayStartHour);
  int scheduled = 0;
  int done = 0;
  int skipped = 0;
  for (var d = start; !d.isAfter(todayDate); d = nextDay(d)) {
    if (!isScheduledOn(habit.scheduledWeekdays, d)) continue;
    switch (statuses[formatYmd(d)]) {
      case EntryStatus.skipped:
        skipped++;
      case EntryStatus.done:
        scheduled++;
        done++;
      case EntryStatus.missed || null:
        scheduled++;
    }
  }
  final rate = scheduled == 0 ? 0.0 : done / scheduled;
  return HabitStats(
    totalScheduled: scheduled,
    totalDone: done,
    totalSkipped: skipped,
    completionRate: rate,
    streak: computeStreaks(
      habit,
      statuses,
      todayDate,
      dayStartHour: dayStartHour,
    ),
  );
}
