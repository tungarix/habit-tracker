import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

import '../../core/constants.dart';
import '../../core/enums.dart';
import '../data_location.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [Habits, HabitEntries, MoodEntries, Tasks, FocusSessions, Settings],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// In-memory constructor for tests.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

  /// Whether [column] already exists on [table].
  ///
  /// Migrations are written defensively against this rather than trusting the
  /// stored version alone: if a process is killed midway, SQLite can keep the
  /// applied DDL while the version bump rolls back. A blind `ADD COLUMN` then
  /// fails with "duplicate column name" on *every* subsequent launch, which
  /// wedges the database permanently. Checking first makes each step
  /// idempotent, so a half-applied upgrade simply finishes next time.
  Future<bool> _hasColumn(String table, String column) async {
    final rows = await customSelect('PRAGMA table_info($table)').get();
    return rows.any((row) => row.data['name'] == column);
  }

  Future<bool> _hasTable(String name) async {
    final rows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?1",
      variables: [Variable<String>(name)],
    ).get();
    return rows.isNotEmpty;
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v1 -> v2: habit category, tri-state entries, moods, settings.
            if (!await _hasColumn('habits', 'category')) {
              await m.addColumn(habits, habits.category);
            }
            if (!await _hasColumn('habit_entries', 'status')) {
              // v1 stored a boolean `done`. Rows with done = 0 carried no
              // information (the UI rendered them like a missing row), so drop
              // them; the survivors all become EntryStatus.done.
              await customStatement('DELETE FROM habit_entries WHERE done = 0');
              await m.alterTable(TableMigration(
                habitEntries,
                columnTransformer: {
                  // Survivors all had done = 1 -> EntryStatus.done (index 0).
                  habitEntries.status: const CustomExpression<int>('0'),
                },
                newColumns: [habitEntries.status],
              ));
            }
            if (!await _hasTable('mood_entries')) {
              await m.createTable(moodEntries);
            }
            if (!await _hasTable('settings')) await m.createTable(settings);
          }
          if (from < 3) {
            // v2 -> v3: countable habits (kind/target) + per-entry amount.
            if (!await _hasColumn('habits', 'kind')) {
              await m.addColumn(habits, habits.kind);
            }
            if (!await _hasColumn('habits', 'target')) {
              await m.addColumn(habits, habits.target);
            }
            if (!await _hasColumn('habit_entries', 'value')) {
              await m.addColumn(habitEntries, habitEntries.value);
              // Existing marks are all bool: ✓ -> 1, ✗/– -> 0.
              await customStatement(
                'UPDATE habit_entries '
                'SET value = CASE WHEN status = 0 THEN 1 ELSE 0 END',
              );
            }
          }
          if (from < 4) {
            // v3 -> v4: tasks and focus sessions join the dashboard.
            if (!await _hasTable('tasks')) await m.createTable(tasks);
            if (!await _hasTable('focus_sessions')) {
              await m.createTable(focusSessions);
            }
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  // ---------------------------------------------------------------------------
  // Habits
  // ---------------------------------------------------------------------------

  Stream<List<Habit>> watchActiveHabits() {
    return (select(habits)
          ..where((h) => h.archivedAt.isNull())
          ..orderBy([
            (h) => OrderingTerm(expression: h.sortOrder),
            (h) => OrderingTerm(expression: h.createdAt),
          ]))
        .watch();
  }

  Stream<List<Habit>> watchArchivedHabits() {
    return (select(habits)
          ..where((h) => h.archivedAt.isNotNull())
          ..orderBy([(h) => OrderingTerm(expression: h.archivedAt, mode: OrderingMode.desc)]))
        .watch();
  }

  Future<List<Habit>> getAllHabits() => select(habits).get();

  Future<Habit?> getHabit(int id) =>
      (select(habits)..where((h) => h.id.equals(id))).getSingleOrNull();

  Future<int> insertHabit(HabitsCompanion companion) => into(habits).insert(companion);

  Future<bool> updateHabit(Habit habit) => update(habits).replace(habit);

  Future<void> archiveHabit(int id, DateTime when) => (update(habits)
        ..where((h) => h.id.equals(id)))
      .write(HabitsCompanion(archivedAt: Value(when)));

  Future<void> unarchiveHabit(int id) => (update(habits)
        ..where((h) => h.id.equals(id)))
      .write(const HabitsCompanion(archivedAt: Value(null)));

  Future<void> deleteHabit(int id) =>
      (delete(habits)..where((h) => h.id.equals(id))).go();

  Future<void> reorderHabits(List<int> orderedIds) async {
    await batch((b) {
      for (var i = 0; i < orderedIds.length; i++) {
        b.update(
          habits,
          HabitsCompanion(sortOrder: Value(i)),
          where: (h) => h.id.equals(orderedIds[i]),
        );
      }
    });
  }

  Future<int> nextSortOrder() async {
    final maxOrder = habits.sortOrder.max();
    final query = selectOnly(habits)..addColumns([maxOrder]);
    final row = await query.getSingleOrNull();
    final current = row?.read(maxOrder);
    return (current ?? -1) + 1;
  }

  // ---------------------------------------------------------------------------
  // Entries
  // ---------------------------------------------------------------------------

  Stream<List<HabitEntry>> watchAllEntries() => select(habitEntries).watch();

  Future<List<HabitEntry>> getAllEntries() => select(habitEntries).get();

  Future<HabitEntry?> getEntry(int habitId, String date) =>
      (select(habitEntries)
            ..where((e) => e.habitId.equals(habitId) & e.date.equals(date)))
          .getSingleOrNull();

  /// Sets the (habit, date) mark. `null` clears the cell back to boş.
  ///
  /// [amount] is the recorded value for count habits; when omitted it follows
  /// the status (✓ = 1, otherwise 0) so bool habits need not think about it.
  ///
  /// Single statement (upsert / delete), no read-before-write, to keep the
  /// tap-to-paint latency minimal.
  Future<void> setEntryStatus(
    int habitId,
    String date,
    EntryStatus? status, {
    int? amount,
  }) async {
    if (status == null) {
      await (delete(habitEntries)
            ..where((e) => e.habitId.equals(habitId) & e.date.equals(date)))
          .go();
      return;
    }
    final value = amount ?? (status == EntryStatus.done ? 1 : 0);
    await into(habitEntries).insert(
      HabitEntriesCompanion.insert(
        habitId: habitId,
        date: date,
        status: status,
        value: Value(value),
      ),
      onConflict: DoUpdate(
        (old) => HabitEntriesCompanion(status: Value(status), value: Value(value)),
        target: [habitEntries.habitId, habitEntries.date],
      ),
    );
  }

  /// Records [amount] for a count habit on [date]; the status follows from
  /// whether the daily [target] was reached. An amount of 0 clears the cell.
  Future<void> setEntryAmount(
    int habitId,
    String date,
    int amount,
    int target,
  ) async {
    if (amount <= 0) {
      await setEntryStatus(habitId, date, null);
      return;
    }
    final status =
        amount >= target ? EntryStatus.done : EntryStatus.missed;
    await setEntryStatus(habitId, date, status, amount: amount);
  }

  /// Advances the (habit, date) cell through boş → ✓ → ✗ → – → boş and
  /// returns the new status. One read + one write.
  Future<EntryStatus?> cycleEntry(int habitId, String date) async {
    final existing = await getEntry(habitId, date);
    final next = nextStatus(existing?.status);
    if (next == null) {
      if (existing != null) {
        await (delete(habitEntries)..where((e) => e.id.equals(existing.id))).go();
      }
    } else if (existing == null) {
      await into(habitEntries).insert(
        HabitEntriesCompanion.insert(
          habitId: habitId,
          date: date,
          status: next,
          value: Value(next == EntryStatus.done ? 1 : 0),
        ),
      );
    } else {
      await (update(habitEntries)..where((e) => e.id.equals(existing.id))).write(
        HabitEntriesCompanion(
          status: Value(next),
          value: Value(next == EntryStatus.done ? 1 : 0),
        ),
      );
    }
    return next;
  }

  // ---------------------------------------------------------------------------
  // Moods
  // ---------------------------------------------------------------------------

  Stream<List<MoodEntry>> watchAllMoods() => select(moodEntries).watch();

  Future<List<MoodEntry>> getAllMoods() => select(moodEntries).get();

  Future<MoodEntry?> getMood(String date) =>
      (select(moodEntries)..where((m) => m.date.equals(date))).getSingleOrNull();

  /// Upserts the mood for [date]; keeps the existing note unless [note] is
  /// given. Single upsert statement.
  Future<void> setMood(String date, int mood, {String? note}) async {
    await into(moodEntries).insert(
      MoodEntriesCompanion.insert(date: date, mood: mood, note: Value(note)),
      onConflict: DoUpdate(
        (old) => MoodEntriesCompanion(
          mood: Value(mood),
          note: note == null ? const Value.absent() : Value(note),
        ),
        target: [moodEntries.date],
      ),
    );
  }

  Future<void> setMoodNote(String date, String? note) async {
    await (update(moodEntries)..where((m) => m.date.equals(date)))
        .write(MoodEntriesCompanion(note: Value(note)));
  }

  Future<void> clearMood(String date) =>
      (delete(moodEntries)..where((m) => m.date.equals(date))).go();

  // ---------------------------------------------------------------------------
  // Tasks
  // ---------------------------------------------------------------------------

  Stream<List<Task>> watchAllTasks() => select(tasks).watch();

  Future<List<Task>> getAllTasks() => select(tasks).get();

  Future<int> insertTask(TasksCompanion companion) =>
      into(tasks).insert(companion);

  Future<bool> updateTask(Task task) => update(tasks).replace(task);

  Future<void> deleteTask(int id) =>
      (delete(tasks)..where((t) => t.id.equals(id))).go();

  /// Moves a task to [status], stamping [Tasks.completedAt] when it lands on
  /// 'done' and clearing it when it leaves.
  Future<void> setTaskStatus(int id, String status, DateTime now) {
    return (update(tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        status: Value(status),
        completedAt: Value(status == 'done' ? now : null),
      ),
    );
  }

  /// Removes every completed task; returns how many were deleted.
  Future<int> clearDoneTasks() =>
      (delete(tasks)..where((t) => t.status.equals('done'))).go();

  // ---------------------------------------------------------------------------
  // Focus sessions
  // ---------------------------------------------------------------------------

  Stream<List<FocusSession>> watchAllSessions() => select(focusSessions).watch();

  Future<List<FocusSession>> getAllSessions() => select(focusSessions).get();

  /// Records a finished session. Sessions are only written once complete, so a
  /// timer abandoned mid-run never leaves a dangling row.
  Future<int> insertSession({
    required String kind,
    required DateTime startedAt,
    required DateTime endedAt,
    required int durationS,
    required String day,
    int? taskId,
  }) {
    return into(focusSessions).insert(
      FocusSessionsCompanion.insert(
        kind: Value(kind),
        startedAt: startedAt,
        endedAt: Value(endedAt),
        durationS: Value(durationS),
        day: day,
        taskId: Value(taskId),
      ),
    );
  }

  Future<void> deleteSession(int id) =>
      (delete(focusSessions)..where((s) => s.id.equals(id))).go();

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------

  Future<String?> getSetting(String key) async {
    final row = await (select(settings)..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> setSetting(String key, String value) =>
      into(settings).insertOnConflictUpdate(
        SettingsCompanion.insert(key: key, value: value),
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await appDataDirectory();
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, AppConstants.dbFileName));
    return NativeDatabase.createInBackground(file);
  });
}
