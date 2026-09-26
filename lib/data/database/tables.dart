import 'package:drift/drift.dart';

import '../../core/enums.dart';

/// A habit the user wants to track.
class Habits extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get description => text().nullable()();

  /// ARGB colour as an int.
  IntColumn get colorValue => integer()();

  /// Material icon codepoint (looked up against a const list on read).
  IntColumn get iconCodePoint => integer()();

  /// [HabitCategory.name]; empty = no category (legacy v1 habits).
  TextColumn get category => text().withDefault(const Constant(''))();

  /// [HabitKind.storageName]: 'bool' (tick) or 'count' (numeric target).
  TextColumn get kind => text().withDefault(const Constant('bool'))();

  /// Daily target for count habits (e.g. 10000 steps). Always 1 for bool.
  IntColumn get target => integer().withDefault(const Constant(1))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Null while the habit is active; set when archived.
  DateTimeColumn get archivedAt => dateTime().nullable()();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// Comma list of Dart weekday numbers (Mon=1..Sun=7). Empty = every day.
  TextColumn get scheduledWeekdays => text().withDefault(const Constant(''))();
}

/// One row per (habit, day) that has an explicit mark. No row = untracked (boş).
class HabitEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get habitId =>
      integer().references(Habits, #id, onDelete: KeyAction.cascade)();

  /// Calendar day as `YYYY-MM-DD`.
  TextColumn get date => text()();

  /// ✓ done / ✗ missed / – skipped (stored as [EntryStatus] index).
  IntColumn get status => intEnum<EntryStatus>()();

  /// Amount recorded for count habits (e.g. 7500 steps). For bool habits this
  /// is 1 when done and 0 otherwise, so one column serves both kinds.
  IntColumn get value => integer().withDefault(const Constant(1))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// One entry per habit per day.
  @override
  List<Set<Column>> get uniqueKeys => [
        {habitId, date},
      ];
}

/// One mood record per day (independent of habits).
class MoodEntries extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Calendar day as `YYYY-MM-DD`; one mood per day.
  TextColumn get date => text().unique()();

  /// 1..5 ([Mood.value]).
  IntColumn get mood => integer()();

  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// A simple task. Deliberately flat: no projects, tags or subtasks — those are
/// in the blueprint's "fridge" until the basics earn their keep.
class Tasks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 200)();

  /// [TaskStatus.storageName]: 'todo' | 'doing' | 'done'.
  TextColumn get status => text().withDefault(const Constant('todo'))();

  /// [TaskPriority.value]: 0 low, 1 normal, 2 high.
  IntColumn get priority => integer().withDefault(const Constant(1))();

  /// Optional due date as `YYYY-MM-DD`.
  TextColumn get dueDay => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get completedAt => dateTime().nullable()();
}

/// One focus (or break) run of the timer.
class FocusSessions extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// [SessionKind.storageName]: 'focus' | 'break'.
  TextColumn get kind => text().withDefault(const Constant('focus'))();

  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();

  /// Elapsed seconds actually recorded (may be less than the planned length
  /// when a session is stopped early).
  IntColumn get durationS => integer().nullable()();

  IntColumn get taskId =>
      integer().nullable().references(Tasks, #id, onDelete: KeyAction.setNull)();

  /// The **tracking day** the session belongs to (`YYYY-MM-DD`, day-start aware).
  /// Stored rather than derived so weekly totals never re-implement the
  /// day-boundary rule.
  TextColumn get day => text()();
}

/// Tiny key-value store for app preferences (e.g. theme mode).
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
