import 'package:intl/intl.dart';

final DateFormat _ymd = DateFormat('yyyy-MM-dd');

/// Strips the time component so two dates can be compared by calendar day.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Today, with the time stripped.
DateTime today() => dateOnly(DateTime.now());

/// Formats a date as the canonical `YYYY-MM-DD` storage string.
String formatYmd(DateTime d) => _ymd.format(d);

/// Parses a canonical `YYYY-MM-DD` storage string back to a date.
DateTime parseYmd(String s) => _ymd.parseStrict(s);

/// Whether [day] is one of the scheduled weekdays.
///
/// [scheduledWeekdays] is a comma list of Dart weekday numbers (Mon=1..Sun=7).
/// An empty string means "every day".
bool isScheduledOn(String scheduledWeekdays, DateTime day) {
  final days = parseWeekdays(scheduledWeekdays);
  if (days.isEmpty) return true;
  return days.contains(day.weekday);
}

/// Parses the stored weekday string into a sorted list of weekday numbers.
List<int> parseWeekdays(String s) {
  final t = s.trim();
  if (t.isEmpty) return const [];
  final result = t
      .split(',')
      .map((e) => int.tryParse(e.trim()))
      .whereType<int>()
      .where((d) => d >= 1 && d <= 7)
      .toSet()
      .toList()
    ..sort();
  return result;
}

/// Serialises a set of weekday numbers back to the stored string.
String weekdaysToString(Iterable<int> days) {
  final s = days.toSet().toList()..sort();
  return s.join(',');
}

/// Inclusive list of dates from [start] to [end] (both date-only).
List<DateTime> daysBetween(DateTime start, DateTime end) {
  final result = <DateTime>[];
  for (var d = dateOnly(start); !d.isAfter(end); d = d.add(const Duration(days: 1))) {
    result.add(d);
  }
  return result;
}
