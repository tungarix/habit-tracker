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
}

/// Short labels for the days of the week (Mon..Sun -> index 0..6).
const List<String> kWeekdayShort = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
