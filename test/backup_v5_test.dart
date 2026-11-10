import 'dart:convert';

import 'package:aktenak_habit_tracker/core/constants.dart';
import 'package:aktenak_habit_tracker/core/enums.dart';
import 'package:aktenak_habit_tracker/data/repositories/backup_repository.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'sync_harness.dart';

/// JSON backup format v5: carries the sync identity and the delete log.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('v5 export carries uid, updatedAt, habitUid, taskUid and deleted', () async {
    final a = Dev('a');
    addTearDown(a.close);
    await a.habit('Kitap', stamp: 10, created: 1);
    await a.cell('Kitap', '2026-05-01', EntryStatus.done, 20);
    await a.cell('Kitap', '2026-05-02', EntryStatus.done, 20);
    await a.clearCell('Kitap', '2026-05-02', 30);
    await a.task('Rapor', stamp: 10, created: 2);
    await a.session(100, 1500, taskTitle: 'Rapor', stamp: 10);

    final json = jsonDecode(await BackupRepository(a.db).exportJson()) as Map<String, dynamic>;
    expect(json['version'], 5);
    final habit = (json['habits'] as List).single as Map;
    expect(habit['uid'], isNotEmpty);
    expect(habit['updatedAt'], isNotNull);
    expect((json['entries'] as List).single['habitUid'], habit['uid']);
    final task = (json['tasks'] as List).single as Map;
    expect((json['sessions'] as List).single['taskUid'], task['uid']);
    expect((json['deleted'] as List).single['kind'], 'entry');
  });

  test('replace from a v5 backup reproduces the sync state exactly', () async {
    final a = Dev('a');
    final b = Dev('b');
    addTearDown(a.close);
    addTearDown(b.close);
    await a.habit('Kitap', stamp: 10, created: 1);
    await a.cell('Kitap', '2026-05-01', EntryStatus.done, 20);
    await a.cell('Kitap', '2026-05-02', EntryStatus.missed, 25);
    await a.clearCell('Kitap', '2026-05-02', 30);
    await a.mood('2026-05-01', 3, 40, note: 'n');
    await a.task('Rapor', stamp: 10, created: 2);
    await a.session(100, 1500, taskTitle: 'Rapor', stamp: 50);
    await a.setDayStart(2, 60); // not part of the backup: must not matter

    final backup = await BackupRepository(a.db).exportJson();
    await b.habit('Başka', stamp: 5, created: 9); // wiped by replace
    await BackupRepository(b.db).importJson(backup, replace: true);

    final sa = jsonDecode(await a.state()) as Map<String, dynamic>;
    final sb = jsonDecode(await b.state()) as Map<String, dynamic>;
    for (final k in ['habits', 'entries', 'moods', 'tasks', 'sessions']) {
      expect(sb[k], sa[k], reason: k);
    }
    // The wipe left a tombstone for what the backup does not bring back.
    final dead = (sb['deleted'] as List).map((d) => '${d['kind']}:${(d as Map)['key']}').toList();
    expect(dead, contains('entry:${(sa['habits'] as List).single['uid']}|2026-05-02'));
    expect(dead.where((d) => d.startsWith('habit:')), hasLength(1)); // "Başka"
  });

  test('a backup from a newer version is refused', () async {
    final a = Dev('a');
    addTearDown(a.close);
    final json = jsonEncode({'format': AppConstants.backupFormat, 'version': 6});
    await expectLater(
      BackupRepository(a.db).importJson(json, replace: true),
      throwsA(isA<FormatException>()),
    );
  });
}
