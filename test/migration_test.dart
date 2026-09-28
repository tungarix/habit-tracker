import 'dart:io';

import 'package:aktenak_habit_tracker/core/enums.dart';
import 'package:aktenak_habit_tracker/data/database/database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs the v2 -> v4 migration against a **synthetic v2-shaped database**
/// and checks that nothing is lost.
///
/// A migration that passes on freshly-inserted current-schema rows and eats
/// real v2 data is the failure mode worth guarding, so this builds a
/// database the normal (v4) way and then performs the same "wind it back"
/// surgery as the half-applied-upgrade test below — dropping the columns
/// and tables v3/v4 added — rather than depending on a real backup file
/// that only ever existed on one machine (which meant this test silently
/// skipped everywhere else, CI included, and never actually ran).
void main() {
  test('migrating a v2-shaped database preserves every row', () async {
    final temp = await Directory.systemTemp.createTemp('aktenak_migration');
    final file = File('${temp.path}/aktenak.sqlite');
    addTearDown(() => temp.delete(recursive: true));

    // Build a healthy current-version database with the v2 snapshot's shape:
    // 3 habits, a handful of ✓ marks.
    final seed = AppDatabase.forTesting(NativeDatabase(file));
    final names = ['Egzersiz', '10 bin adım', 'Gitar'];
    final habitIds = <int>[];
    for (final name in names) {
      habitIds.add(await seed.insertHabit(HabitsCompanion.insert(
        name: name,
        colorValue: 0xFF4CAF50,
        iconCodePoint: 0xe000,
      )));
    }
    final dates = ['2026-06-24', '2026-07-01', '2026-07-30'];
    for (final habitId in habitIds) {
      for (final date in dates) {
        await seed.setEntryStatus(habitId, date, EntryStatus.done);
      }
    }
    await seed.close();

    // Wind it back to v2's shape: drop what v3 (kind/target/value) and v4
    // (tasks/focus_sessions) added, and roll the stamped version back.
    final winder = AppDatabase.forTesting(NativeDatabase(file));
    await winder.customStatement('ALTER TABLE habits DROP COLUMN kind');
    await winder.customStatement('ALTER TABLE habits DROP COLUMN target');
    await winder
        .customStatement('ALTER TABLE habit_entries DROP COLUMN value');
    await winder.customStatement('DROP TABLE tasks');
    await winder.customStatement('DROP TABLE focus_sessions');
    await winder.customStatement('PRAGMA user_version = 2');
    await winder.close();

    // Reopening must drive the v2 -> v3 -> v4 migration.
    final db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);

    final habits = await db.getAllHabits();
    final entries = await db.getAllEntries();

    expect(habits, hasLength(3));
    expect(entries, hasLength(9));
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
    expect(habits.map((h) => h.name), containsAll(names));
    final survivingDates = entries.map((e) => e.date).toSet();
    expect(survivingDates, containsAll(dates));
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
