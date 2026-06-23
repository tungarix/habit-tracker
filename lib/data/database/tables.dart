import 'package:drift/drift.dart';

/// A habit the user wants to track.
class Habits extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get description => text().nullable()();

  /// ARGB colour as an int.
  IntColumn get colorValue => integer()();

  /// Material icon codepoint (looked up against a const list on read).
  IntColumn get iconCodePoint => integer()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Null while the habit is active; set when archived.
  DateTimeColumn get archivedAt => dateTime().nullable()();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// Comma list of Dart weekday numbers (Mon=1..Sun=7). Empty = every day.
  TextColumn get scheduledWeekdays => text().withDefault(const Constant(''))();
}

/// One row per (habit, day). Presence + `done` records the tick.
class HabitEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get habitId =>
      integer().references(Habits, #id, onDelete: KeyAction.cascade)();

  /// Calendar day as `YYYY-MM-DD`.
  TextColumn get date => text()();

  BoolColumn get done => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// One entry per habit per day.
  @override
  List<Set<Column>> get uniqueKeys => [
        {habitId, date},
      ];
}
