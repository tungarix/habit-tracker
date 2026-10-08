import 'dart:convert';
import 'dart:io';

import 'package:aktenak_habit_tracker/core/constants.dart';
import 'package:aktenak_habit_tracker/data/auto_backup.dart';
import 'package:aktenak_habit_tracker/data/database/database.dart';
import 'package:aktenak_habit_tracker/data/repositories/backup_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase db;
  late Directory dir;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.insertHabit(
      HabitsCompanion.insert(
        name: 'Egzersiz',
        colorValue: 0xFF4CAF50,
        iconCodePoint: 0xe000,
      ),
    );
    dir = await Directory.systemTemp.createTemp('aktenak_auto_backup');
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  AutoBackup backup({int keep = 14}) =>
      AutoBackup(repo: BackupRepository(db), dir: dir, keep: keep);

  List<String> names() =>
      dir.listSync().map((e) => p.basename(e.path)).toList()..sort();

  test('günde bir kez yazar, ertesi gün yenisini alır', () async {
    final b = backup();

    final first = await b.runIfDue(DateTime(2026, 10, 8, 9));
    expect(first, isNotNull);
    expect(await b.runIfDue(DateTime(2026, 10, 8, 23)), isNull);
    expect(await b.runIfDue(DateTime(2026, 10, 9, 0, 5)), isNotNull);

    expect(names(), [
      'aktenak-auto-20261008.json',
      'aktenak-auto-20261009.json',
    ]);
  });

  test('yedek geçerli, içe aktarılabilir bir JSON', () async {
    final file = await backup().runIfDue(DateTime(2026, 10, 8));
    final json = jsonDecode(await file!.readAsString()) as Map;

    expect(json['format'], AppConstants.backupFormat);
    expect((json['habits'] as List).single['name'], 'Egzersiz');
    expect(names().where((n) => n.endsWith('.tmp')), isEmpty);
  });

  test('yalnızca en yeni N otomatik yedeği tutar', () async {
    final b = backup(keep: 3);
    for (var day = 1; day <= 5; day++) {
      await b.runIfDue(DateTime(2026, 10, day));
    }

    expect(names(), [
      'aktenak-auto-20261003.json',
      'aktenak-auto-20261004.json',
      'aktenak-auto-20261005.json',
    ]);
  });

  test('budama elle alınan yedeklere ve başka dosyalara dokunmaz', () async {
    File(
      p.join(dir.path, 'aktenak-backup-20260101-1200.json'),
    ).writeAsStringSync('{}');
    File(p.join(dir.path, 'notlar.txt')).writeAsStringSync('x');

    final b = backup(keep: 1);
    await b.runIfDue(DateTime(2026, 10, 1));
    await b.runIfDue(DateTime(2026, 10, 2));

    expect(names(), [
      'aktenak-auto-20261002.json',
      'aktenak-backup-20260101-1200.json',
      'notlar.txt',
    ]);
  });

  test('klasör yoksa oluşturur; hiç yedek yokken latest null', () async {
    final nested = Directory(p.join(dir.path, 'yedekler'));
    final b = AutoBackup(repo: BackupRepository(db), dir: nested);

    expect(await b.latest(), isNull);
    await b.runIfDue(DateTime(2026, 10, 8));
    expect(await b.latest(), isNotNull);
  });
}
