import 'package:drift/drift.dart';

import '../../core/enums.dart';
import '../database/database.dart';

/// Thin wrapper over [AppDatabase] for habit, entry and mood mutations.
///
/// Read-side streams are exposed directly; the heavier "decorate with streak /
/// stats" work happens in the Riverpod providers, which combine the raw
/// habit, entry and mood streams.
class HabitRepository {
  final AppDatabase db;
  HabitRepository(this.db);

  Stream<List<Habit>> watchActiveHabits() => db.watchActiveHabits();
  Stream<List<Habit>> watchArchivedHabits() => db.watchArchivedHabits();
  Stream<List<HabitEntry>> watchAllEntries() => db.watchAllEntries();
  Stream<List<MoodEntry>> watchAllMoods() => db.watchAllMoods();

  /// boş → ✓ → ✗ → – → boş; returns the new status.
  Future<EntryStatus?> cycle(int habitId, String date) =>
      db.cycleEntry(habitId, date);

  Future<void> setStatus(int habitId, String date, EntryStatus? status) =>
      db.setEntryStatus(habitId, date, status);

  /// Records an amount for a count habit; status follows from [target].
  Future<void> setAmount(int habitId, String date, int amount, int target) =>
      db.setEntryAmount(habitId, date, amount, target);

  Future<void> setMood(String date, int mood, {String? note}) =>
      db.setMood(date, mood, note: note);
  Future<void> setMoodNote(String date, String? note) => db.setMoodNote(date, note);
  Future<void> clearMood(String date) => db.clearMood(date);

  Future<String?> getSetting(String key) => db.getSetting(key);
  Future<void> setSetting(String key, String value) => db.setSetting(key, value);

  Future<int> createHabit({
    required String name,
    String? description,
    required int colorValue,
    required int iconCodePoint,
    required String category,
    required String scheduledWeekdays,
    String kind = 'bool',
    int target = 1,
  }) async {
    final sortOrder = await db.nextSortOrder();
    return db.insertHabit(HabitsCompanion.insert(
      name: name,
      description: Value(description),
      colorValue: colorValue,
      iconCodePoint: iconCodePoint,
      category: Value(category),
      scheduledWeekdays: Value(scheduledWeekdays),
      sortOrder: Value(sortOrder),
      kind: Value(kind),
      target: Value(target),
    ));
  }

  Future<void> updateHabit(Habit habit) => db.updateHabit(habit);
  Future<void> reorderHabits(List<int> orderedIds) => db.reorderHabits(orderedIds);
  Future<void> archive(int id) => db.archiveHabit(id, DateTime.now());
  Future<void> unarchive(int id) => db.unarchiveHabit(id);
  Future<void> delete(int id) => db.deleteHabit(id);
}
