import 'dart:io';

import 'package:aktenak_habit_tracker/core/constants.dart';
import 'package:aktenak_habit_tracker/core/enums.dart';
import 'package:aktenak_habit_tracker/data/database/database.dart';
import 'package:aktenak_habit_tracker/data/sync/sync_export.dart';
import 'package:aktenak_habit_tracker/data/sync/sync_import.dart';
// Only used to count rows of a database *before* the app migrates it.
// ignore: depend_on_referenced_packages
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Schema v5: sync identity (uid), change stamps, delete log.
///
/// Three things are checked: an upgrade loses nothing and ends up with the
/// same schema as a fresh install, the triggers behave, and - when
/// `HABIT_CANLI_KOPYA` points at a folder holding *copies* of the real
/// `aktenak.sqlite*` files - the real v1/v2/v4 user databases upgrade cleanly.
/// (Never point it at the live folder itself; the test migrates in place.)
final _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

const _allTables = [
  'habits',
  'habit_entries',
  'mood_entries',
  'tasks',
  'focus_sessions',
];

/// Columns, indexes and triggers of a database, normalised for comparison.
/// Column order is ignored: `ADD COLUMN` appends, a fresh `CREATE TABLE`
/// follows the declaration, and that difference is harmless.
Future<Map<String, Object>> schemaOf(AppDatabase db) async {
  final out = <String, Object>{};
  final tables = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name",
      )
      .get();
  for (final t in tables.map((r) => r.read<String>('name'))) {
    final cols = await db.customSelect('PRAGMA table_info($t)').get();
    out['table $t'] = (cols
            .map((c) =>
                '${c.data['name']}|${(c.data['type'] as String).toUpperCase()}|'
                '${c.data['notnull']}|${c.data['dflt_value']}|${c.data['pk']}')
            .toList()
          ..sort())
        .join(';');
    final idx = await db.customSelect('PRAGMA index_list($t)').get();
    for (final i in idx) {
      final name = i.data['name'] as String;
      if (name.startsWith('sqlite_autoindex')) continue;
      final cols = await db.customSelect('PRAGMA index_info($name)').get();
      out['index $name'] = 'unique=${i.data['unique']} on $t '
          '(${cols.map((c) => c.data['name']).join(',')})';
    }
  }
  final triggers = await db
      .customSelect("SELECT name, sql FROM sqlite_master WHERE type = 'trigger'")
      .get();
  for (final r in triggers) {
    out['trigger ${r.read<String>('name')}'] =
        r.read<String>('sql').replaceAll(RegExp(r'\s+'), ' ');
  }
  return out;
}

Future<Map<String, Object>> freshSchema() async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  return schemaOf(db);
}

Future<int> userVersion(AppDatabase db) => db
    .customSelect('PRAGMA user_version')
    .getSingle()
    .then((r) => r.data.values.first as int);

Future<List<String>> uids(AppDatabase db, String table) => db
    .customSelect('SELECT uid FROM $table')
    .get()
    .then((rows) => [for (final r in rows) r.read<String>('uid')]);

void expectSchemaEquals(Map<String, Object> a, Map<String, Object> b) {
  expect(a.keys.toSet(), b.keys.toSet(), reason: 'object names differ');
  for (final k in a.keys) {
    expect(a[k], b[k], reason: k);
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('fresh database has uid indexes, triggers and the delete log', () async {
    final schema = await freshSchema();
    expect(schema.keys, containsAll([
      'index habits_uid_idx',
      'index tasks_uid_idx',
      'index focus_sessions_uid_idx',
      'table silinenler',
      'trigger habits_uid_ai',
      'trigger habit_entries_tomb_ad',
      'trigger settings_daystart_au',
    ]));
    expect(schema['index habits_uid_idx'], startsWith('unique=1'));
  });

  /// Builds a v5 database, then rewinds it to the shape [version] had:
  /// everything v5 added is dropped, then (for older versions) what v3/v4
  /// added. Returns the file; the caller reopens it to run the upgrade.
  Future<File> rewound(int version, {bool withData = true}) async {
    final temp = await Directory.systemTemp.createTemp('aktenak_v5');
    addTearDown(() => temp.delete(recursive: true));
    final file = File('${temp.path}/aktenak.sqlite');

    final seed = AppDatabase.forTesting(NativeDatabase(file));
    if (withData) {
      final h1 = await seed.insertHabit(HabitsCompanion.insert(
        name: 'Egzersiz',
        colorValue: 0xFF4CAF50,
        iconCodePoint: 0xe000,
      ));
      final h2 = await seed.insertHabit(HabitsCompanion.insert(
        name: 'Gitar',
        colorValue: 0xFF2196F3,
        iconCodePoint: 0xe001,
      ));
      for (final h in [h1, h2]) {
        await seed.setEntryStatus(h, '2026-07-01', EntryStatus.done);
        await seed.setEntryStatus(h, '2026-07-02', EntryStatus.missed);
      }
      await seed.setMood('2026-07-01', 4, note: 'iyi');
      if (version >= 4) {
        final t = await seed.insertTask(TasksCompanion.insert(title: 'Rapor'));
        await seed.insertSession(
          kind: 'focus',
          startedAt: DateTime(2026, 7, 1, 10),
          endedAt: DateTime(2026, 7, 1, 10, 25),
          durationS: 1500,
          day: '2026-07-01',
          taskId: t,
        );
      }
      await seed.setSetting(AppConstants.dayStartHourKey, '3');
    }
    await seed.close();

    final w = AppDatabase.forTesting(NativeDatabase(file));
    final names = (await w
            .customSelect("SELECT name FROM sqlite_master WHERE type='trigger'")
            .get())
        .map((r) => r.read<String>('name'));
    for (final n in names) {
      await w.customStatement('DROP TRIGGER $n');
    }
    for (final t in ['habits', 'tasks', 'focus_sessions']) {
      await w.customStatement('DROP INDEX ${t}_uid_idx');
      await w.customStatement('ALTER TABLE $t DROP COLUMN uid');
    }
    for (final t in _allTables) {
      await w.customStatement('ALTER TABLE $t DROP COLUMN updated_at');
    }
    await w.customStatement('DROP TABLE silinenler');
    await w.customStatement(
      "DELETE FROM settings WHERE key = '${AppConstants.dayStartHourStampKey}'",
    );
    if (version < 4) {
      await w.customStatement('DROP TABLE tasks');
      await w.customStatement('DROP TABLE focus_sessions');
    }
    if (version < 3) {
      await w.customStatement('ALTER TABLE habits DROP COLUMN kind');
      await w.customStatement('ALTER TABLE habits DROP COLUMN target');
      await w.customStatement('ALTER TABLE habit_entries DROP COLUMN value');
    }
    await w.customStatement('PRAGMA user_version = $version');
    await w.close();
    return file;
  }

  for (final version in [2, 3, 4]) {
    test('v$version -> v5: nothing lost, schema equals a fresh install', () async {
      final file = await rewound(version);
      final db = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(db.close);

      expect(await db.getAllHabits(), hasLength(2));
      expect(await db.getAllEntries(), hasLength(4));
      expect(await db.getAllMoods(), hasLength(1));
      if (version >= 4) {
        expect(await db.getAllTasks(), hasLength(1));
        expect(await db.getAllSessions(), hasLength(1));
      }
      expect(await userVersion(db), 5);

      for (final t in ['habits', 'tasks', 'focus_sessions']) {
        final ids = await uids(db, t);
        expect(ids.toSet(), hasLength(ids.length), reason: '$t uid unique');
        expect(ids.every(_uuidV4.hasMatch), isTrue, reason: '$t uid is v4');
      }
      for (final t in _allTables) {
        final zero = await db
            .customSelect('SELECT COUNT(*) AS n FROM $t WHERE updated_at <= 0')
            .getSingle();
        expect(zero.read<int>('n'), 0, reason: '$t updated_at filled');
      }
      // updated_at came from createdAt, not from "now".
      final h = (await db.getAllHabits()).first;
      expect(h.updatedAt, h.createdAt.millisecondsSinceEpoch ~/ 1000);
      // A day-start hour chosen before sync existed got a stamp.
      expect(await db.getSetting(AppConstants.dayStartHourKey), '3');
      expect(await db.getSetting(AppConstants.dayStartHourStampKey), isNotNull);
      // The backfill itself must not have written tombstones.
      expect(await db.select(db.silinenler).get(), isEmpty);

      expectSchemaEquals(await schemaOf(db), await freshSchema());
    });
  }

  test('v5 step is idempotent: a half-applied upgrade finishes', () async {
    final file = await rewound(4);
    // Pretend the previous attempt got as far as the habits.uid column.
    final half = raw.sqlite3.open(file.path); // raw: opening via drift migrates
    half.execute('ALTER TABLE habits ADD COLUMN uid TEXT');
    half.execute("UPDATE habits SET uid = 'half-' || id WHERE id = 1");
    half.close();

    final db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);
    final ids = await uids(db, 'habits');
    expect(ids, contains('half-1')); // existing uid is kept
    expect(ids.where((u) => _uuidV4.hasMatch(u)), hasLength(1));
    expectSchemaEquals(await schemaOf(db), await freshSchema());
  });

  group('triggers', () {
    late AppDatabase db;
    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });
    tearDown(() => db.close());

    Future<int> newHabit([String name = 'Kitap']) => db.insertHabit(
          HabitsCompanion.insert(
            name: name,
            colorValue: 1,
            iconCodePoint: 2,
          ),
        );

    Future<List<Tombstone>> tombs() => db.select(db.silinenler).get();

    test('insert gives a uid and a stamp; an explicit stamp is kept', () async {
      final id = await newHabit();
      final h = (await db.getHabit(id))!;
      expect(_uuidV4.hasMatch(h.uid!), isTrue);
      expect(h.updatedAt, greaterThan(1700000000));

      final id2 = await db.insertHabit(HabitsCompanion.insert(
        name: 'Elle',
        colorValue: 1,
        iconCodePoint: 2,
        uid: const Value('abc'),
        updatedAt: const Value(1234567),
      ));
      final h2 = (await db.getHabit(id2))!;
      expect([h2.uid, h2.updatedAt], ['abc', 1234567]);
    });

    test('an edit stamps; sync-style writes (explicit stamp, uid) do not',
        () async {
      final id = await newHabit();
      await db.customStatement('UPDATE habits SET updated_at = 100');
      await db.archiveHabit(id, DateTime(2026, 1, 1));
      expect((await db.getHabit(id))!.updatedAt, greaterThan(1700000000));

      await db.customStatement('UPDATE habits SET updated_at = 100');
      await db.customStatement("UPDATE habits SET name = 'x', updated_at = 77");
      expect((await db.getHabit(id))!.updatedAt, 77);

      await db.customStatement("UPDATE habits SET uid = 'adopted'");
      expect((await db.getHabit(id))!.updatedAt, 77);
    });

    test('deleting records leaves tombstones with the right keys', () async {
      final h = await newHabit();
      final uid = (await db.getHabit(h))!.uid!;
      await db.setEntryStatus(h, '2026-05-01', EntryStatus.done);
      await db.setEntryStatus(h, '2026-05-02', EntryStatus.done);
      await db.setMood('2026-05-01', 3);
      final t = await db.insertTask(TasksCompanion.insert(title: 'T'));
      final tUid = (await db.getAllTasks()).single.uid!;

      await db.setEntryStatus(h, '2026-05-01', null); // cell back to blank
      await db.clearMood('2026-05-01');
      await db.deleteTask(t);
      var keys = {for (final x in await tombs()) '${x.kind}:${x.anahtar}'};
      expect(keys, {'entry:$uid|2026-05-01', 'mood:2026-05-01', 'task:$tUid'});
      expect((await tombs()).every((x) => x.deletedAt > 1700000000), isTrue);

      // Deleting the habit cascades to its cells: one tombstone, for the habit.
      await db.deleteHabit(h);
      keys = {for (final x in await tombs()) '${x.kind}:${x.anahtar}'};
      expect(keys, contains('habit:$uid'));
      expect(keys.where((k) => k.startsWith('entry:')), hasLength(1));
    });

    test('re-adding a record clears its tombstone', () async {
      final h = await newHabit();
      await db.setEntryStatus(h, '2026-05-01', EntryStatus.done);
      await db.setEntryStatus(h, '2026-05-01', null);
      expect(await tombs(), hasLength(1));
      await db.setEntryStatus(h, '2026-05-01', EntryStatus.missed);
      expect(await tombs(), isEmpty);
    });

    test('deleting a task stamps its sessions (task_id set to null)', () async {
      final t = await db.insertTask(TasksCompanion.insert(title: 'T'));
      await db.insertSession(
        kind: 'focus',
        startedAt: DateTime(2026, 5, 1, 9),
        endedAt: DateTime(2026, 5, 1, 9, 25),
        durationS: 1500,
        day: '2026-05-01',
        taskId: t,
      );
      await db.customStatement('UPDATE focus_sessions SET updated_at = 5');
      await db.deleteTask(t);
      final s = (await db.getAllSessions()).single;
      expect(s.taskId, isNull);
      expect(s.updatedAt, greaterThan(1700000000));
    });

    test('dayStartHour keeps a stamp in settings', () async {
      expect(await db.getSetting(AppConstants.dayStartHourStampKey), isNull);
      await db.setSetting(AppConstants.dayStartHourKey, '2');
      final first = await db.getSetting(AppConstants.dayStartHourStampKey);
      expect(int.parse(first!), greaterThan(1700000000));
      await db.customStatement(
        "UPDATE settings SET value = '5' WHERE key = '${AppConstants.dayStartHourStampKey}'",
      );
      await db.setSetting(AppConstants.dayStartHourKey, '3');
      expect(
        int.parse((await db.getSetting(AppConstants.dayStartHourStampKey))!),
        greaterThan(1700000000),
      );
      // Other settings do not touch it.
      await db.setSetting(AppConstants.themeModeKey, 'dark');
      expect(await db.getSetting('${AppConstants.themeModeKey}UpdatedAt'),
          isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Real user databases (copies). Skipped unless HABIT_CANLI_KOPYA is set.
  // ---------------------------------------------------------------------------
  final canli = Platform.environment['HABIT_CANLI_KOPYA'];
  group('gercek canli-veri kopyasi', skip: canli == null ? 'HABIT_CANLI_KOPYA tanimli degil' : false, () {
    for (final (name, version) in const [
      ('aktenak.sqlite.v1-backup-20260719', 1),
      ('aktenak.sqlite.faz0-backup-20260810', 2),
      ('aktenak.sqlite', 4),
    ]) {
      test('$name (v$version) -> v5 without losing a row', () async {
        final src = File('$canli/$name');
        final temp = await Directory.systemTemp.createTemp('aktenak_canli');
        addTearDown(() => temp.delete(recursive: true));
        final file = await src.copy('${temp.path}/aktenak.sqlite');

        // Row counts and the (habit name, date) marks before the upgrade.
        final before = raw.sqlite3.open(file.path);
        final v = before.select('PRAGMA user_version').first.values.first;
        expect(v, version);
        int count(String t) =>
            before.select('SELECT COUNT(*) FROM $t').first.values.first as int;
        final nHabits = count('habits');
        final nEntries = version == 1
            ? before
                .select('SELECT COUNT(*) FROM habit_entries WHERE done = 1')
                .first
                .values
                .first as int
            : count('habit_entries');
        final nSettings = version >= 2 ? count('settings') : 0;
        final habitNames = before
            .select('SELECT name FROM habits ORDER BY name')
            .map((r) => r['name'] as String)
            .toList();
        before.close();

        final db = AppDatabase.forTesting(NativeDatabase(file));
        addTearDown(db.close);

        expect(await userVersion(db), 5);
        final habits = await db.getAllHabits();
        expect(habits, hasLength(nHabits));
        expect((habits.map((h) => h.name).toList()..sort()), habitNames);
        expect(await db.getAllEntries(), hasLength(nEntries));
        // Settings: the old rows are still there (a stamp row may be added).
        final settingRows = await db.select(db.settings).get();
        expect(settingRows.length, greaterThanOrEqualTo(nSettings));
        expect(await db.select(db.silinenler).get(), isEmpty);

        final ids = await uids(db, 'habits');
        expect(ids.toSet(), hasLength(nHabits));
        expect(ids.every(_uuidV4.hasMatch), isTrue);
        expectSchemaEquals(await schemaOf(db), await freshSchema());

        // The upgraded real data must also travel: file -> empty device -> same
        // rows, and a second import changes nothing.
        final other = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(other.close);
        final text = await exportSync(db);
        final first = await importSyncText(other, text);
        expect(first.habit.added, nHabits);
        expect(first.entry.added, nEntries);
        expect((await other.getAllHabits()).map((h) => h.uid).toSet(),
            (await db.getAllHabits()).map((h) => h.uid).toSet());
        expect((await importSyncText(other, text)).changed, isFalse);
        expect(await exportSync(db, now: DateTime(2026)), await exportSync(db, now: DateTime(2026)));
      });
    }
  });
}
