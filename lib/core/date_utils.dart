import 'package:intl/intl.dart';

import 'constants.dart';

final DateFormat _ymd = DateFormat('yyyy-MM-dd');

/// Strips the time component so two dates can be compared by calendar day.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// **The single entry point for "which tracking day is this instant?"**
///
/// A tracking day runs from [dayStartHour] to [dayStartHour] the next morning,
/// not midnight to midnight. Marking a habit at 01:35 therefore still counts
/// for the previous day — which is how people actually use a tracker at night.
///
/// Every date calculation in the app must go through this function. Writing
/// this rule in two places is how tracker data silently rots.
///
/// Dates are always the user's **local** calendar day; never converted to UTC,
/// which would shift streaks by the timezone offset.
DateTime dayOf(
  DateTime instant, {
  int dayStartHour = AppConstants.defaultDayStartHour,
}) {
  if (instant.hour < dayStartHour) {
    // DateTime normalises day 0 to the last day of the previous month.
    return DateTime(instant.year, instant.month, instant.day - 1);
  }
  return DateTime(instant.year, instant.month, instant.day);
}

/// The current tracking day. Prefer `todayProvider` inside the UI so the
/// user's configured [AppConstants.dayStartHourKey] is honoured.
DateTime today({int dayStartHour = AppConstants.defaultDayStartHour}) =>
    dayOf(DateTime.now(), dayStartHour: dayStartHour);

/// The instant at which the tracking day containing [instant] rolls over.
/// Used to schedule a refresh so an app left open overnight stays correct.
DateTime nextDayBoundary(
  DateTime instant, {
  int dayStartHour = AppConstants.defaultDayStartHour,
}) {
  final day = dayOf(instant, dayStartHour: dayStartHour);
  return DateTime(day.year, day.month, day.day + 1, dayStartHour);
}

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

/// Number of days in the month containing [month].
int daysInMonth(DateTime month) => DateTime(month.year, month.month + 1, 0).day;

/// First day of the month containing [d].
DateTime firstOfMonth(DateTime d) => DateTime(d.year, d.month, 1);

/// Inclusive list of dates from [start] to [end] (both date-only).
List<DateTime> daysBetween(DateTime start, DateTime end) {
  final result = <DateTime>[];
  for (var d = dateOnly(start); !d.isAfter(end); d = d.add(const Duration(days: 1))) {
    result.add(d);
  }
  return result;
}

/// The [count] tracking days ending at [endDay], oldest first.
List<DateTime> lastDays(DateTime endDay, int count) => [
      for (var i = count - 1; i >= 0; i--)
        DateTime(endDay.year, endDay.month, endDay.day - i),
    ];
