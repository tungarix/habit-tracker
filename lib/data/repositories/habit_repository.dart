import 'package:drift/drift.dart';

import '../database/database.dart';

/// Thin wrapper over [AppDatabase] for habit + entry mutations.
///
/// Read-side streams are exposed directly; the heavier "decorate with streak /
/// stats" work happens in the Riverpod providers, which combine the raw
/// habit and entry streams.
class HabitRepository {
  final AppDatabase db;
  HabitRepository(this.db);

  Stream<List<Habit>> watchActiveHabits() => db.watchActiveHabits();
  Stream<List<Habit>> watchArchivedHabits() => db.watchArchivedHabits();
  Stream<List<HabitEntry>> watchAllEntries() => db.watchAllEntries();

  Future<void> toggle(int habitId, String date) => db.toggleEntry(habitId, date);
  Future<void> setDone(int habitId, String date, bool done) =>
      db.setEntry(habitId, date, done);

  Future<int> createHabit({
    required String name,
    String? description,
    required int colorValue,
    required int iconCodePoint,
    required String scheduledWeekdays,
  }) async {
    final sortOrder = await db.nextSortOrder();
    return db.insertHabit(HabitsCompanion.insert(
      name: name,
      description: Value(description),
      colorValue: colorValue,
      iconCodePoint: iconCodePoint,
      scheduledWeekdays: Value(scheduledWeekdays),
      sortOrder: Value(sortOrder),
    ));
  }

  Future<void> updateHabit(Habit habit) => db.updateHabit(habit);
  Future<void> archive(int id) => db.archiveHabit(id, DateTime.now());
  Future<void> unarchive(int id) => db.unarchiveHabit(id);
  Future<void> delete(int id) => db.deleteHabit(id);
}
