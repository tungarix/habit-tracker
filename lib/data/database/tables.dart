import 'package:drift/drift.dart';

import '../../core/enums.dart';

/// A habit the user wants to track.
@TableIndex(name: 'habits_uid_idx', columns: {#uid}, unique: true)
class Habits extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Sync identity (UUID v4), filled by a trigger on insert. Nullable only
  /// because SQLite cannot `ADD COLUMN` a UNIQUE one; the unique index does
  /// the real work. See docs/senkron.md.
  TextColumn get uid => text().nullable()();

  /// Unix seconds of the last change, kept current by triggers (0 = "not
  /// stamped yet", replaced on insert). Plain int: sync compares seconds.
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();
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

  /// See [Habits.updatedAt].
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();

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

  /// See [Habits.updatedAt].
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();
}

/// A simple task. Deliberately flat: no projects, tags or subtasks — those are
/// in the blueprint's "fridge" until the basics earn their keep.
@TableIndex(name: 'tasks_uid_idx', columns: {#uid}, unique: true)
class Tasks extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// See [Habits.uid].
  TextColumn get uid => text().nullable()();

  /// See [Habits.updatedAt].
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();
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
@TableIndex(name: 'focus_sessions_uid_idx', columns: {#uid}, unique: true)
class FocusSessions extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// See [Habits.uid].
  TextColumn get uid => text().nullable()();

  /// See [Habits.updatedAt].
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();

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

/// Delete log ("tombstones") for sync: one row per deleted record, written by
/// `AFTER DELETE` triggers so no delete path can forget it.
///
/// `kind` is habit | task | session | entry | mood; `anahtar` is the uid, or
/// `habitUid|date` for an entry, or the date for a mood. `deletedAt` is unix
/// seconds. The table keeps its Turkish name on purpose: it is part of the
/// shared (desktop + mobile) schema.
@DataClassName('Tombstone')
class Silinenler extends Table {
  @override
  String get tableName => 'silinenler';

  TextColumn get kind => text()();
  TextColumn get anahtar => text()();
  IntColumn get deletedAt => integer()();

  @override
  Set<Column> get primaryKey => {kind, anahtar};
}
