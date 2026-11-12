import 'dart:convert';

import 'package:aktenak_habit_tracker/core/constants.dart';
import 'package:aktenak_habit_tracker/core/enums.dart';
import 'package:aktenak_habit_tracker/data/database/database.dart';
import 'package:aktenak_habit_tracker/data/repositories/backup_repository.dart';
import 'package:aktenak_habit_tracker/data/sync/sync_format.dart' show syncMaxRecords;
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Importing a backup (merge and replace) against an in-memory database.
///
/// The failure mode worth guarding: ids in a backup come from another device,
/// so "merge" must never treat id 1 in the file as id 1 here, and importing
/// the same file twice must not pile up duplicates.

// Distinct creation times, so two rows can tell each other apart.
final _t1 = DateTime.utc(2026, 2, 1, 8);
final _t2 = DateTime.utc(2026, 2, 7, 19, 30);

AppDatabase _memoryDb() {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  return db;
}

// ---------------------------------------------------------------------------
// Rows already on "this device"
// ---------------------------------------------------------------------------

Future<int> _addHabit(AppDatabase db, String name, DateTime createdAt) =>
    db.insertHabit(
      HabitsCompanion.insert(
        name: name,
        colorValue: 0xFF4CAF50,
        iconCodePoint: 0xe000,
        createdAt: Value(createdAt),
      ),
    );

Future<int> _addTask(AppDatabase db, String title, DateTime createdAt) =>
    db.insertTask(
      TasksCompanion.insert(title: title, createdAt: Value(createdAt)),
    );

Future<int> _addSession(
  AppDatabase db, {
  required DateTime startedAt,
  int durationS = 1500,
  String day = '2026-03-02',
  String kind = 'focus',
  int? taskId,
}) => db.insertSession(
  kind: kind,
  startedAt: startedAt,
  endedAt: startedAt.add(Duration(seconds: durationS)),
  durationS: durationS,
  day: day,
  taskId: taskId,
);

// ---------------------------------------------------------------------------
// Rows in the backup file
// ---------------------------------------------------------------------------

/// A habit as the file carries it; [createdAt] null leaves the key out, the
/// way a v1 backup does.
Map<String, dynamic> _fileHabit(int id, String name, DateTime? createdAt) => {
  'id': id,
  'name': name,
  'description': null,
  'colorValue': 0xFF2196F3,
  'iconCodePoint': 0xe001,
  'category': 'beden',
  'kind': 'bool',
  'target': 1,
  if (createdAt != null) 'createdAt': createdAt.toUtc().toIso8601String(),
  'archivedAt': null,
  'sortOrder': 0,
  'scheduledWeekdays': '',
};

Map<String, dynamic> _fileEntry(
  int habitId,
  String date, {
  String status = 'done',
}) => {
  'habitId': habitId,
  'date': date,
  'status': status,
  'value': status == 'done' ? 1 : 0,
};

Map<String, dynamic> _fileTask(int id, String title, DateTime? createdAt) => {
  'id': id,
  'title': title,
  'status': 'todo',
  'priority': 1,
  'dueDay': null,
  if (createdAt != null) 'createdAt': createdAt.toUtc().toIso8601String(),
  'completedAt': null,
};

Map<String, dynamic> _fileSession(
  DateTime startedAt, {
  int durationS = 1500,
  String day = '2026-03-02',
  String kind = 'focus',
  int? taskId,
}) => {
  'kind': kind,
  'startedAt': startedAt.toUtc().toIso8601String(),
  'endedAt': startedAt
      .add(Duration(seconds: durationS))
      .toUtc()
      .toIso8601String(),
  'durationS': durationS,
  'day': day,
  'taskId': taskId,
};

String _file({
  int version = AppConstants.backupVersion,
  List<Map<String, dynamic>> habits = const [],
  List<Map<String, dynamic>> entries = const [],
  List<Map<String, dynamic>> tasks = const [],
  List<Map<String, dynamic>> sessions = const [],
  List<Map<String, dynamic>> moods = const [],
}) => jsonEncode({
  'format': AppConstants.backupFormat,
  'version': version,
  'habits': habits,
  'entries': entries,
  'moods': moods,
  'tasks': tasks,
  'sessions': sessions,
});

/// Row counts per table: habits, entries, tasks, sessions.
Future<List<int>> _counts(AppDatabase db) async => [
  (await db.getAllHabits()).length,
  (await db.getAllEntries()).length,
  (await db.getAllTasks()).length,
  (await db.getAllSessions()).length,
];

Future<Habit> _habitNamed(AppDatabase db, String name) async =>
    (await db.getAllHabits()).singleWhere((h) => h.name == name);

Future<Task> _taskTitled(AppDatabase db, String title) async =>
    (await db.getAllTasks()).singleWhere((t) => t.title == title);

Future<Set<String>> _datesOf(AppDatabase db, int habitId) async => {
  for (final e in await db.getAllEntries())
    if (e.habitId == habitId) e.date,
};

void main() {
  group('merge twice', () {
    test(
      'the same file merged twice changes nothing the second time',
      () async {
        final db = _memoryDb();
        // This device already uses id 1 for another habit and another task, so
        // everything in the file has to be renumbered.
        final kitap = await _addHabit(db, 'Kitap', _t1);
        await db.setEntryStatus(kitap, '2026-03-01', EntryStatus.done);
        await _addTask(db, 'Eski görev', _t1);

        final file = _file(
          habits: [_fileHabit(1, 'Spor', _t2)],
          entries: [
            _fileEntry(1, '2026-03-01', status: 'missed'),
            _fileEntry(1, '2026-03-02'),
          ],
          tasks: [_fileTask(1, 'Yeni görev', _t2)],
          sessions: [
            _fileSession(DateTime.utc(2026, 3, 2, 9), taskId: 1),
            _fileSession(DateTime.utc(2026, 3, 2, 11), durationS: 900),
          ],
        );
        final repo = BackupRepository(db);

        final first = await repo.importJson(file, replace: false);
        final afterFirst = await _counts(db);
        final second = await repo.importJson(file, replace: false);
        final afterSecond = await _counts(db);

        expect(afterFirst, [2, 3, 2, 2]); // habits, entries, tasks, sessions
        expect(afterSecond, afterFirst);
        expect(first.sessions, 2);
        expect(second.sessions, 0);
      },
    );

    test(
      'exporting and merging back into the same database is a no-op',
      () async {
        final db = _memoryDb();
        final habitId = await _addHabit(db, 'Spor', _t1);
        await db.setEntryStatus(habitId, '2026-03-01', EntryStatus.done);
        final taskId = await _addTask(db, 'Görev', _t2);
        await _addSession(
          db,
          startedAt: DateTime.utc(2026, 3, 1, 9),
          taskId: taskId,
        );
        await _addSession(
          db,
          startedAt: DateTime.utc(2026, 3, 1, 10),
          durationS: 300,
        );
        final before = await _counts(db);

        final repo = BackupRepository(db);
        final result = await repo.importJson(
          await repo.exportJson(),
          replace: false,
        );

        expect(await _counts(db), before);
        expect(result.sessions, 0);
        // Nothing was renumbered or re-linked either.
        expect(
          (await db.getAllSessions()).where((s) => s.taskId == taskId),
          hasLength(1),
        );
        expect(await _datesOf(db, habitId), {'2026-03-01'});
      },
    );
  });

  group('merge id clashes', () {
    test(
      'a habit with a taken id is added as a new habit, not written over',
      () async {
        final db = _memoryDb();
        final kitap = await _addHabit(db, 'Kitap', _t1);
        await db.setEntryStatus(kitap, '2026-03-01', EntryStatus.done);
        expect(kitap, 1);

        await BackupRepository(db).importJson(
          _file(
            habits: [_fileHabit(1, 'Spor', _t2)], // id 1 on the other device
            entries: [
              _fileEntry(
                1,
                '2026-03-01',
                status: 'missed',
              ), // same day as Kitap's mark
              _fileEntry(1, '2026-03-02'),
            ],
          ),
          replace: false,
        );

        expect(await db.getAllHabits(), hasLength(2));
        final kitapAfter = await db.getHabit(kitap);
        expect(kitapAfter!.name, 'Kitap');
        // Kitap's marks are exactly what they were.
        final kitapEntry = await db.getEntry(kitap, '2026-03-01');
        expect(kitapEntry!.status, EntryStatus.done);
        expect(await _datesOf(db, kitap), {'2026-03-01'});
        // Spor got a fresh id and its own marks.
        final spor = await _habitNamed(db, 'Spor');
        expect(spor.id, isNot(kitap));
        expect(await _datesOf(db, spor.id), {'2026-03-01', '2026-03-02'});
        expect(
          (await db.getEntry(spor.id, '2026-03-01'))!.status,
          EntryStatus.missed,
        );
      },
    );

    test(
      'a task with a taken id is added as new and its sessions follow it',
      () async {
        final db = _memoryDb();
        final eski = await _addTask(db, 'Eski görev', _t1);
        final oldSession = await _addSession(
          db,
          startedAt: DateTime.utc(2026, 3, 1, 9),
          taskId: eski,
        );
        expect(eski, 1);

        await BackupRepository(db).importJson(
          _file(
            tasks: [_fileTask(1, 'Yeni görev', _t2)],
            sessions: [_fileSession(DateTime.utc(2026, 3, 2, 9), taskId: 1)],
          ),
          replace: false,
        );

        expect(await db.getAllTasks(), hasLength(2));
        expect((await _taskTitled(db, 'Eski görev')).id, eski);
        final yeni = await _taskTitled(db, 'Yeni görev');
        expect(yeni.id, isNot(eski));

        final sessions = await db.getAllSessions();
        final imported = sessions.singleWhere((s) => s.id != oldSession);
        expect(imported.taskId, yeni.id); // not the unrelated task 1
        expect(sessions.singleWhere((s) => s.id == oldSession).taskId, eski);
      },
    );

    test(
      'a habit renamed here (same id and creation time) is updated, not copied',
      () async {
        final db = _memoryDb();
        final id = await _addHabit(db, 'Spor', _t1);
        await db.setEntryStatus(id, '2026-03-01', EntryStatus.done);
        final taskId = await _addTask(db, 'Rapor', _t2);

        await BackupRepository(db).importJson(
          _file(
            habits: [_fileHabit(id, 'Fitness', _t1)],
            entries: [_fileEntry(id, '2026-03-02')],
            tasks: [_fileTask(taskId, 'Rapor yaz', _t2)],
          ),
          replace: false,
        );

        expect(await db.getAllHabits(), hasLength(1));
        expect((await db.getHabit(id))!.name, 'Fitness');
        expect(await _datesOf(db, id), {'2026-03-01', '2026-03-02'});
        expect(await db.getAllTasks(), hasLength(1));
        expect((await _taskTitled(db, 'Rapor yaz')).id, taskId);
      },
    );

    test('creation time is compared to the second', () async {
      final db = _memoryDb();
      final id = await _addHabit(db, 'Spor', _t1);

      // The file carries milliseconds the database never stored.
      await BackupRepository(db).importJson(
        _file(
          habits: [
            _fileHabit(id, 'Spor', _t1.add(const Duration(milliseconds: 400))),
          ],
        ),
        replace: false,
      );

      expect(await db.getAllHabits(), hasLength(1));
    });
  });

  group('replace', () {
    test('keeps every id exactly as the file has it', () async {
      final db = _memoryDb();
      final kitap = await _addHabit(db, 'Kitap', _t1); // id 1, to be wiped
      await db.setEntryStatus(kitap, '2026-03-01', EntryStatus.done);
      await _addTask(db, 'Eski görev', _t1);
      await _addSession(db, startedAt: DateTime.utc(2026, 3, 1, 9));

      final result = await BackupRepository(db).importJson(
        _file(
          habits: [_fileHabit(5, 'Spor', _t2)],
          entries: [_fileEntry(5, '2026-03-02')],
          tasks: [_fileTask(7, 'Yeni görev', _t2)],
          sessions: [_fileSession(DateTime.utc(2026, 3, 2, 9), taskId: 7)],
        ),
        replace: true,
      );

      expect((await db.getAllHabits()).map((h) => h.id), [5]);
      expect((await db.getAllTasks()).map((t) => t.id), [7]);
      expect((await db.getAllEntries()).map((e) => e.habitId), [5]);
      expect((await db.getAllSessions()).map((s) => s.taskId), [7]);
      expect(result.sessions, 1);
    });
  });

  group('v1 files', () {
    test('without a creation time a habit matches by name', () async {
      final db = _memoryDb();
      final kitap = await _addHabit(db, 'Kitap', _t1);

      await BackupRepository(db).importJson(
        jsonEncode({
          'format': AppConstants.backupFormat,
          'version': 1,
          'habits': [_fileHabit(1, 'Kitap', null)],
          'entries': [
            {'habitId': 1, 'date': '2026-03-01', 'done': true},
            {'habitId': 1, 'date': '2026-03-02', 'done': false}, // no mark
          ],
        }),
        replace: false,
      );

      expect(await db.getAllHabits(), hasLength(1));
      final after = await db.getHabit(kitap);
      expect(after!.createdAt.toUtc(), _t1); // not stamped with "now"
      expect(await _datesOf(db, kitap), {'2026-03-01'});
    });

    test(
      'a v1 habit whose id is taken by another habit is added as new, once',
      () async {
        final db = _memoryDb();
        final kitap = await _addHabit(db, 'Kitap', _t1);
        final v1 = jsonEncode({
          'format': AppConstants.backupFormat,
          'version': 1,
          'habits': [_fileHabit(1, 'Spor', null)], // id 1 here is Kitap
          'entries': [
            {'habitId': 1, 'date': '2026-03-01', 'done': true},
          ],
        });
        final repo = BackupRepository(db);

        await repo.importJson(v1, replace: false);
        await repo.importJson(v1, replace: false);

        expect(await db.getAllHabits(), hasLength(2));
        expect(
          await _datesOf(db, kitap),
          isEmpty,
        ); // Spor's mark did not land on Kitap
        final spor = await _habitNamed(db, 'Spor');
        expect(await _datesOf(db, spor.id), {'2026-03-01'});
      },
    );
  });

  group('rows that cannot be resolved', () {
    test(
      'an entry for a habit that exists nowhere is skipped, the rest imports',
      () async {
        final db = _memoryDb();
        final kitap = await _addHabit(db, 'Kitap', _t1);

        final result = await BackupRepository(db).importJson(
          _file(
            habits: [_fileHabit(3, 'Spor', _t2)],
            entries: [
              _fileEntry(
                99,
                '2026-03-01',
              ), // in neither the file nor the database
              _fileEntry(3, '2026-03-02'),
              _fileEntry(kitap, '2026-03-03'), // not in the file, but here
            ],
          ),
          replace: false,
        );

        expect(await db.getAllEntries(), hasLength(2));
        expect(result.entries, 2);
        expect(await _datesOf(db, kitap), {'2026-03-03'});
      },
    );

    test('replace mode skips such an entry too instead of failing', () async {
      final db = _memoryDb();

      final result = await BackupRepository(db).importJson(
        _file(
          habits: [_fileHabit(3, 'Spor', _t2)],
          entries: [_fileEntry(99, '2026-03-01'), _fileEntry(3, '2026-03-02')],
        ),
        replace: true,
      );

      expect(await db.getAllEntries(), hasLength(1));
      expect(result.entries, 1);
    });

    test('a session whose task is unknown is kept without a task', () async {
      final db = _memoryDb();

      final result = await BackupRepository(db).importJson(
        _file(
          sessions: [_fileSession(DateTime.utc(2026, 3, 2, 9), taskId: 42)],
        ),
        replace: false,
      );

      final sessions = await db.getAllSessions();
      expect(sessions, hasLength(1));
      expect(sessions.single.taskId, isNull);
      expect(result.sessions, 1);
    });
  });

  group('session count', () {
    test('only counts sessions that were actually added', () async {
      final db = _memoryDb();
      final start = DateTime.utc(2026, 3, 2, 9);
      await _addSession(db, startedAt: start);

      final result = await BackupRepository(db).importJson(
        _file(
          sessions: [
            _fileSession(start), // identical to the stored one
            _fileSession(start, kind: 'break'), // other kind
            _fileSession(start, durationS: 600), // other length
            _fileSession(start, day: '2026-03-03'), // other day
            _fileSession(start.add(const Duration(minutes: 1))), // other start
            _fileSession(
              start.add(const Duration(milliseconds: 250)),
            ), // same second
          ],
        ),
        replace: false,
      );

      expect(result.sessions, 4);
      expect(await db.getAllSessions(), hasLength(5));
    });
  });

  group('bozuk ya da sınır dışı yedek', () {
    // Each must throw a readable FormatException and leave the data alone, in both modes.
    Future<void> reddedilir(String json, Matcher mesaj) async {
      for (final replace in [false, true]) {
        final db = _memoryDb();
        await _addHabit(db, 'Mevcut', _t1);
        final before = await _counts(db);
        await expectLater(
          BackupRepository(db).importJson(json, replace: replace),
          throwsA(isA<FormatException>().having((e) => e.message, 'message', mesaj)),
        );
        expect(await _counts(db), before, reason: 'replace=$replace');
      }
    }

    test('yanlış alan türü TypeError değil okunur hata verir', () async {
      final h = _fileHabit(1, 'Spor', _t2)..['colorValue'] = 'kırmızı';
      await reddedilir(_file(habits: [h]), contains('beklenen türde değil'));
      final id = _fileHabit(1, 'Spor', _t2)..['id'] = 'bir';
      await reddedilir(_file(habits: [id]), contains('beklenen türde değil'));
      await reddedilir(
        jsonEncode({'format': AppConstants.backupFormat, 'version': 5, 'habits': [1, 2]}),
        contains('beklenen türde değil'),
      );
    });

    test('gerçek olmayan gün: kayıt, ruh hali ve görev bitiş günü reddedilir', () async {
      for (final bad in ['abc', '2026-13-45', '2026-02-30', '2026-3-1', '']) {
        await reddedilir(
          _file(habits: [_fileHabit(1, 'Spor', _t2)], entries: [_fileEntry(1, bad)]),
          contains('kayıt tarihi'),
        );
        await reddedilir(
          _file(moods: [
            {'date': bad, 'mood': 3},
          ]),
          contains('ruh hali tarihi'),
        );
      }
      for (final bad in ['abc', '2026-13-45', 7]) {
        final t = _fileTask(1, 'x', _t2)..['dueDay'] = bad;
        await reddedilir(_file(tasks: [t]), contains('görev bitiş günü'));
      }
    });

    test('çok iç içe JSON ve bozuk JSON', () async {
      await reddedilir('[' * 5000, contains('iç içe'));
      await reddedilir('{', contains('JSON'));
    });

    test('uzun ad ve çok kayıt', () async {
      await reddedilir(_file(habits: [_fileHabit(1, 'x' * 101, _t2)]), contains('alışkanlık adı'));
      await reddedilir(
        _file(entries: List.filled(syncMaxRecords + 1, <String, dynamic>{})),
        contains('en çok'),
      );
    });
  });
}
