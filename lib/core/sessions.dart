import '../data/database/database.dart';
import 'date_utils.dart';
import 'enums.dart';

/// Focus-session aggregation. Sessions already carry the tracking day they
/// belong to, so nothing here re-implements the day-boundary rule.

/// Total focus seconds recorded on [day].
int focusSecondsOn(List<FocusSession> sessions, DateTime day) {
  final dayStr = formatYmd(day);
  var total = 0;
  for (final s in sessions) {
    if (s.day != dayStr) continue;
    if (SessionKind.fromStorage(s.kind) != SessionKind.focus) continue;
    total += s.durationS ?? 0;
  }
  return total;
}

/// Focus seconds per day for the [count] days ending at [endDay], oldest first.
List<int> focusSecondsSeries(
  List<FocusSession> sessions,
  DateTime endDay,
  int count,
) {
  final byDay = <String, int>{};
  for (final s in sessions) {
    if (SessionKind.fromStorage(s.kind) != SessionKind.focus) continue;
    byDay[s.day] = (byDay[s.day] ?? 0) + (s.durationS ?? 0);
  }
  return [
    for (final day in lastDays(endDay, count)) byDay[formatYmd(day)] ?? 0,
  ];
}

/// Rolling totals shown on the dashboard.
class FocusSummary {
  final int todaySeconds;
  final int last7Seconds;
  final int todaySessions;
  final int last7Sessions;

  /// Longest run of consecutive days (ending today) with any focus time.
  final int dayStreak;

  const FocusSummary({
    required this.todaySeconds,
    required this.last7Seconds,
    required this.todaySessions,
    required this.last7Sessions,
    required this.dayStreak,
  });

  static const empty = FocusSummary(
    todaySeconds: 0,
    last7Seconds: 0,
    todaySessions: 0,
    last7Sessions: 0,
    dayStreak: 0,
  );
}

FocusSummary summariseFocus(List<FocusSession> sessions, DateTime todayDay) {
  final todayStr = formatYmd(todayDay);
  final weekDays = lastDays(todayDay, 7).map(formatYmd).toSet();

  int todaySeconds = 0, last7Seconds = 0, todaySessions = 0, last7Sessions = 0;
  for (final s in sessions) {
    if (SessionKind.fromStorage(s.kind) != SessionKind.focus) continue;
    final seconds = s.durationS ?? 0;
    if (s.day == todayStr) {
      todaySeconds += seconds;
      todaySessions++;
    }
    if (weekDays.contains(s.day)) {
      last7Seconds += seconds;
      last7Sessions++;
    }
  }

  // Day streak: walk back from today while each day has focus time. Today
  // being empty so far does not break it (same grace as habit streaks).
  final daysWithFocus = <String>{
    for (final s in sessions)
      if (SessionKind.fromStorage(s.kind) == SessionKind.focus &&
          (s.durationS ?? 0) > 0)
        s.day,
  };
  var streak = 0;
  for (var i = 0;; i++) {
    final day = DateTime(todayDay.year, todayDay.month, todayDay.day - i);
    if (daysWithFocus.contains(formatYmd(day))) {
      streak++;
    } else if (i == 0) {
      continue; // today not started yet
    } else {
      break;
    }
    if (i > 3650) break; // hard stop
  }

  return FocusSummary(
    todaySeconds: todaySeconds,
    last7Seconds: last7Seconds,
    todaySessions: todaySessions,
    last7Sessions: last7Sessions,
    dayStreak: streak,
  );
}

/// Formats a duration the way the dashboard shows it: `1s 25dk`, `25dk`, `40sn`.
String formatDuration(int seconds) {
  if (seconds < 60) return '${seconds}sn';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}dk';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '${hours}s' : '${hours}s ${rest}dk';
}

/// `25:00` style countdown label.
String formatClock(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final m = (safe ~/ 60).toString().padLeft(2, '0');
  final s = (safe % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
