/// App-wide constants.
///
/// This file is part of `core/` and must stay free of Flutter imports — the
/// habit colour/icon palettes live in `shared/habit_style.dart` instead.
library;

class AppConstants {
  static const String appName = 'Aktenak';
  static const String backupFormat = 'aktenak-habit-tracker';
  static const int backupVersion = 4;

  /// Database file name (stored in the platform application-support dir).
  static const String dbFileName = 'aktenak.sqlite';

  /// Hour at which a new tracking day begins (see [dayOf]). Marks made after
  /// midnight but before this hour still count as the previous day.
  static const int defaultDayStartHour = 4;

  /// Settings key for the user's day-start hour.
  static const String dayStartHourKey = 'dayStartHour';

  /// Settings key for the theme mode.
  static const String themeModeKey = 'themeMode';

  /// Settings key for the evening-reminder hour (0-23); absent = disabled.
  static const String reminderHourKey = 'reminderHour';

  /// Default hour offered when the reminder is first turned on.
  static const int defaultReminderHour = 20;

  /// Settings key for the date (`YYYY-MM-DD`) the evening reminder last
  /// fired on — persisted so a restart the same evening doesn't re-notify.
  static const String lastReminderDateKey = 'lastReminderDate';
}

/// Short labels for the days of the week (Mon..Sun -> index 0..6).
const List<String> kWeekdayShort = [
  'Pzt',
  'Sal',
  'Çar',
  'Per',
  'Cum',
  'Cmt',
  'Paz',
];
