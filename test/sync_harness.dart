import 'dart:convert';

import 'package:aktenak_habit_tracker/core/constants.dart';
import 'package:aktenak_habit_tracker/core/enums.dart';
import 'package:aktenak_habit_tracker/data/database/database.dart';
import 'package:aktenak_habit_tracker/data/sync/sync_export.dart';
import 'package:aktenak_habit_tracker/data/sync/sync_format.dart';
import 'package:aktenak_habit_tracker/data/sync/sync_import.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// Test harness for sync: one [Dev] is one device (its own in-memory database).
///
/// Triggers stamp rows with the real clock, which makes "who edited last"
/// untestable without sleeping. Helpers here write rows and then pin the
/// stamps to chosen moments ([at]); the rules under test only ever look at
/// the stamps.

/// A fixed point in 2026; `at(n)` is n seconds after it.
const int t0 = 1780000000;
int at(int n) => t0 + n;
DateTime when(int n) => DateTime.fromMillisecondsSinceEpoch(at(n) * 1000);

class Dev {
  Dev(this.name) : db = AppDatabase.forTesting(NativeDatabase.memory());
  final String name;
  final AppDatabase db;

  Future<void> sql(String s, [List<Object?> args = const []]) =>
      db.customStatement(s, args);

  // -- writes (each pins the stamp to [stamp] seconds-after-t0) -----------------

  Future<int> habit(
    String name, {
    int stamp = 0,
    int created = 0,
    String kind = 'bool',
    int target = 1,
    String? uid,
  }) async {
    final id = await db.insertHabit(HabitsCompanion.insert(
      name: name,
      colorValue: 0xFF4CAF50,
      iconCodePoint: 0xe000,
      kind: Value(kind),
      target: Value(target),
      createdAt: Value(when(created)),
      updatedAt: Value(at(stamp)),
      uid: uid == null ? const Value.absent() : Value(uid),
    ));
    return id;
  }

  Future<int> idOf(String habitName) async => (await db.getAllHabits())
      .firstWhere((h) => h.name == habitName)
      .id;

  Future<String> uidOfHabit(String habitName) async => (await db.getAllHabits())
      .firstWhere((h) => h.name == habitName)
      .uid!;

  Future<void> editHabit(String habitName, int stamp, {String? rename, bool? archive}) async {
    await sql(
      'UPDATE habits SET name = ?, archived_at = ?, updated_at = ? WHERE name = ?',
      [
        rename ?? habitName,
        archive == null ? null : (archive ? at(stamp) : null),
        at(stamp),
        habitName,
      ],
    );
  }

  Future<void> cell(String habitName, String date, EntryStatus status, int stamp,
      {int? amount}) async {
    final id = await idOf(habitName);
    await db.setEntryStatus(id, date, status, amount: amount);
    await sql('UPDATE habit_entries SET updated_at = ? WHERE habit_id = ? AND date = ?',
        [at(stamp), id, date]);
  }

  Future<void> clearCell(String habitName, String date, int stamp) async {
    final id = await idOf(habitName);
    final uid = await uidOfHabit(habitName);
    await db.setEntryStatus(id, date, null);
    await sql(
        "UPDATE silinenler SET deleted_at = ? WHERE kind = 'entry' AND anahtar = ?",
        [at(stamp), '$uid|$date']);
  }

  Future<void> mood(String date, int value, int stamp, {String? note}) async {
    await db.setMood(date, value, note: note);
    await sql('UPDATE mood_entries SET updated_at = ? WHERE date = ?', [at(stamp), date]);
  }

  Future<void> clearMood(String date, int stamp) async {
    await db.clearMood(date);
    await sql("UPDATE silinenler SET deleted_at = ? WHERE kind = 'mood' AND anahtar = ?",
        [at(stamp), date]);
  }

  Future<int> task(String title, {int stamp = 0, int created = 0}) async =>
      db.insertTask(TasksCompanion.insert(
        title: title,
        createdAt: Value(when(created)),
        updatedAt: Value(at(stamp)),
      ));

  Future<void> editTask(String title, int stamp, {String? status, String? rename}) =>
      sql('UPDATE tasks SET title = ?, status = COALESCE(?, status), updated_at = ? '
          'WHERE title = ?', [rename ?? title, status, at(stamp), title]);

  Future<void> deleteTask(String title, int stamp) async {
    final t = (await db.getAllTasks()).firstWhere((t) => t.title == title);
    await db.deleteTask(t.id);
    await sql("UPDATE silinenler SET deleted_at = ? WHERE kind = 'task' AND anahtar = ?",
        [at(stamp), t.uid]);
  }

  Future<void> deleteHabit(String habitName, int stamp) async {
    final uid = await uidOfHabit(habitName);
    await db.deleteHabit(await idOf(habitName));
    await sql("UPDATE silinenler SET deleted_at = ? WHERE kind = 'habit' AND anahtar = ?",
        [at(stamp), uid]);
  }

  Future<int> session(
    int startedAfter,
    int seconds, {
    String? taskTitle,
    int stamp = 0,
    String day = '2026-05-01',
    String kind = 'focus',
  }) async {
    int? taskId;
    if (taskTitle != null) {
      taskId = (await db.getAllTasks()).firstWhere((t) => t.title == taskTitle).id;
    }
    return db.into(db.focusSessions).insert(FocusSessionsCompanion.insert(
          kind: Value(kind),
          startedAt: when(startedAfter),
          endedAt: Value(when(startedAfter + seconds)),
          durationS: Value(seconds),
          day: day,
          taskId: Value(taskId),
          updatedAt: Value(at(stamp)),
        ));
  }

  Future<void> deleteSession(int startedAfter, int stamp) async {
    final s = (await db.getAllSessions())
        .firstWhere((s) => s.startedAt == when(startedAfter));
    await db.deleteSession(s.id);
    await sql(
        "UPDATE silinenler SET deleted_at = ? WHERE kind = 'session' AND anahtar = ?",
        [at(stamp), s.uid]);
  }

  Future<void> setDayStart(int hour, int stamp) async {
    await db.setSetting(AppConstants.dayStartHourKey, '$hour');
    await db.setSetting(AppConstants.dayStartHourStampKey, '${at(stamp)}');
  }

  Future<int?> dayStart() async =>
      int.tryParse(await db.getSetting(AppConstants.dayStartHourKey) ?? '');

  // -- reads --------------------------------------------------------------------

  /// Everything that syncs, normalised so two devices can be compared.
  Future<String> state() async {
    final doc = jsonDecode(await exportSync(db)) as Map<String, dynamic>;
    doc.remove('created_at');
    doc.remove('device');
    String key(Map m) => jsonEncode(
        [m['uid'], m['habit_uid'], m['date'], m['kind'], m['key']]);
    for (final k in ['habits', 'entries', 'moods', 'tasks', 'sessions', 'deleted']) {
      (doc[k] as List).sort((a, b) => key(a as Map).compareTo(key(b as Map)));
    }
    return jsonEncode(doc);
  }

  Future<int> count(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle()).read<int>('n');

  Future<void> close() => db.close();
}

/// Moves [from]'s state to [to] through a file, like the user would.
Future<SyncReport> sync(Dev from, Dev to) async =>
    importSyncText(to.db, await exportSync(from.db, deviceName: from.name));

/// A <-> B until neither side changes (bounded), returns the rounds used.
Future<int> settle(Dev a, Dev b) async {
  for (var round = 1; round <= 4; round++) {
    final r1 = await sync(a, b);
    final r2 = await sync(b, a);
    if (!r1.changed && !r2.changed) return round;
  }
  throw StateError('sync did not settle in 4 rounds');
}
