import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Habits, HabitEntries])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// In-memory constructor for tests.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
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

  Stream<List<HabitEntry>> watchEntriesForHabit(int habitId) =>
      (select(habitEntries)..where((e) => e.habitId.equals(habitId))).watch();

  Future<HabitEntry?> getEntry(int habitId, String date) =>
      (select(habitEntries)
            ..where((e) => e.habitId.equals(habitId) & e.date.equals(date)))
          .getSingleOrNull();

  /// Inserts or updates the (habit, date) entry to [done].
  Future<void> setEntry(int habitId, String date, bool done) async {
    final existing = await getEntry(habitId, date);
    if (existing == null) {
      await into(habitEntries).insert(
        HabitEntriesCompanion.insert(habitId: habitId, date: date, done: Value(done)),
      );
    } else {
      await (update(habitEntries)..where((e) => e.id.equals(existing.id)))
          .write(HabitEntriesCompanion(done: Value(done)));
    }
  }

  /// Flips the done state of the (habit, date) entry.
  Future<void> toggleEntry(int habitId, String date) async {
    final existing = await getEntry(habitId, date);
    await setEntry(habitId, date, !(existing?.done ?? false));
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, AppConstants.dbFileName));
    return NativeDatabase.createInBackground(file);
  });
}
