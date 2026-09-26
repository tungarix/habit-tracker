import 'dart:io';

import 'package:aktenak_habit_tracker/core/enums.dart';
import 'package:aktenak_habit_tracker/data/database/database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs the v2 -> v3 migration against a **copy of the real database** and
/// checks that nothing was lost.
///
/// A migration that passes on synthetic rows and eats the user's history is
/// the failure mode worth guarding, so this test points at the actual backup
/// taken before the schema change. It skips silently on machines that do not
/// have that file (CI, a fresh clone).
void main() {
  final backup = File(
    r'C:\Users\user\AppData\Roaming\com.aktenak\aktenak_habit_tracker'
    r'\aktenak.sqlite.faz0-backup-20260810',
  );

  test('migrating the real v2 database preserves every row', () async {
    if (!backup.existsSync()) {
      markTestSkipped('No local v2 backup at ${backup.path}');
      return;
    }

    final temp = await Directory.systemTemp.createTemp('aktenak_migration');
    final work = File('${temp.path}/aktenak.sqlite');
    await backup.copy(work.path);
    addTearDown(() => temp.delete(recursive: true));

    final db = AppDatabase.forTesting(NativeDatabase(work));
    addTearDown(db.close);

    // Opening + any query drives the migration.
    final habits = await db.getAllHabits();
    final entries = await db.getAllEntries();

    // The v2 snapshot: 10 habits, 19 marks, all of them ✓.
    expect(habits, hasLength(10));
    expect(entries, hasLength(19));
    expect(entries.every((e) => e.status == EntryStatus.done), isTrue);

    // Schema is at the current version.
    final version = await db
        .customSelect('PRAGMA user_version')
        .getSingle()
        .then((row) => row.data.values.first);
    expect(version, db.schemaVersion);

    // v4 added the planner tables; they must exist and start empty.
    expect(await db.getAllTasks(), isEmpty);
    expect(await db.getAllSessions(), isEmpty);

    // New habit columns took their defaults.
    expect(habits.every((h) => h.kind == 'bool'), isTrue);
    expect(habits.every((h) => h.target == 1), isTrue);

    // Existing ✓ marks became value = 1, so counts and ticks agree.
    expect(entries.every((e) => e.value == 1), isTrue);

    // Names and dates survived intact.
    expect(
      habits.map((h) => h.name),
      containsAll(<String>['Egzersiz', '10 bin adım', 'Gitar']),
    );
    final dates = entries.map((e) => e.date).toSet();
    expect(dates, contains('2026-06-24'));
    expect(dates, contains('2026-07-30'));
  });

  test('repairs a half-applied upgrade instead of wedging', () async {
    // Reproduces a real failure: the app was killed mid-upgrade, leaving the
    // new columns in place while the version bump rolled back. Every later
    // launch then died on "duplicate column name: kind" and the database was
    // stuck for good. Each migration step must therefore be idempotent.
    final temp = await Directory.systemTemp.createTemp('aktenak_halfway');
    final file = File('${temp.path}/aktenak.sqlite');
    addTearDown(() => temp.delete(recursive: true));

    // Build a healthy current-version database with one habit and one mark.
    final first = AppDatabase.forTesting(NativeDatabase(file));
    final habitId = await first.insertHabit(
      HabitsCompanion.insert(
        name: 'Egzersiz',
        colorValue: 0xFF4CAF50,
        iconCodePoint: 0xe000,
      ),
    );
    await first.setEntryStatus(habitId, '2026-08-11', EntryStatus.done);
    await first.close();

    // Wind it back into the broken shape: version says v2, but the v3 columns
    // are already there and the v4 tables are gone.
    final broken = AppDatabase.forTesting(NativeDatabase(file));
    await broken.customStatement('DROP TABLE tasks');
    await broken.customStatement('DROP TABLE focus_sessions');
    await broken.customStatement('PRAGMA user_version = 2');
    await broken.close();

    // Reopening must finish the job rather than throw.
    final repaired = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(repaired.close);

    final habits = await repaired.getAllHabits();
    final entries = await repaired.getAllEntries();
    final version = await repaired
        .customSelect('PRAGMA user_version')
        .getSingle()
        .then((row) => row.data.values.first);

    expect(version, repaired.schemaVersion);
    expect(habits, hasLength(1));
    expect(habits.single.name, 'Egzersiz');
    expect(entries, hasLength(1));
    expect(await repaired.getAllTasks(), isEmpty);
    expect(await repaired.getAllSessions(), isEmpty);
  });

  test('a fresh database supports count habits end to end', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final id = await db.insertHabit(
      HabitsCompanion.insert(
        name: '10 bin adım',
        colorValue: 0xFF2196F3,
        iconCodePoint: 0xe000,
        kind: const Value('count'),
        target: const Value(10000),
      ),
    );

    // Short of target -> recorded but not done.
    await db.setEntryAmount(id, '2026-08-09', 7500, 10000);
    final partial = await db.getEntry(id, '2026-08-09');
    expect(partial!.value, 7500);
    expect(partial.status, EntryStatus.missed);

    // Reaching the target flips it to ✓.
    await db.setEntryAmount(id, '2026-08-10', 10200, 10000);
    final hit = await db.getEntry(id, '2026-08-10');
    expect(hit!.value, 10200);
    expect(hit.status, EntryStatus.done);

    // Zero clears the cell entirely.
    await db.setEntryAmount(id, '2026-08-10', 0, 10000);
    expect(await db.getEntry(id, '2026-08-10'), isNull);
  });
}
