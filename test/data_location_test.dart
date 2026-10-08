import 'dart:io';

import 'package:aktenak_habit_tracker/core/enums.dart';
import 'package:aktenak_habit_tracker/data/data_location.dart';
import 'package:aktenak_habit_tracker/data/database/database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// v1.2.0–v1.2.1 wrote to "Aktenak Habit Tracker" instead of the original
/// "aktenak_habit_tracker" folder; the next launch must bring that data back
/// without losing what's already in the original.
void main() {
  late Directory root;
  late Directory canonical;
  late Directory stray;
  final now = DateTime(2026, 10, 8, 20, 30);

  setUp(() {
    root = Directory.systemTemp.createTempSync('aktenak_location');
    canonical = Directory(p.join(root.path, 'aktenak_habit_tracker'));
    stray = Directory(p.join(root.path, 'Aktenak Habit Tracker'))
      ..createSync();
  });

  tearDown(() => root.deleteSync(recursive: true));

  File dbIn(Directory d) => File(p.join(d.path, 'aktenak.sqlite'));

  /// Creates [dir]/aktenak.sqlite holding one habit [name] with a ✓ mark.
  ///
  /// [createdAt] matters: the merge import treats same id + same creation
  /// second as the same habit, so two databases seeded in the same second
  /// would look like one habit — never the case across real installs.
  Future<void> seed(
    Directory dir,
    String name, {
    bool empty = false,
    DateTime? createdAt,
  }) async {
    dir.createSync(recursive: true);
    final db = AppDatabase.forTesting(NativeDatabase(dbIn(dir)));
    if (empty) {
      await db.getAllHabits(); // just create the schema
    } else {
      final id = await db.insertHabit(
        HabitsCompanion.insert(
          name: name,
          colorValue: 0xFF4CAF50,
          iconCodePoint: 0xe000,
          createdAt: createdAt == null
              ? const Value.absent()
              : Value(createdAt),
        ),
      );
      await db.setEntryStatus(id, '2026-10-01', EntryStatus.done);
    }
    await db.close();
  }

  Future<List<String>> habitNames(Directory dir) async {
    final db = AppDatabase.forTesting(NativeDatabase(dbIn(dir)));
    final names = (await db.getAllHabits()).map((h) => h.name).toList();
    await db.close();
    return names..sort();
  }

  test('yanlış klasörde dosya yoksa hiçbir şey yapmaz', () async {
    await seed(canonical, 'Kitap');
    expect(
      await recoverStrayV12Data(canonical: canonical, stray: stray, now: now),
      isNull,
    );
    expect(await habitNames(canonical), ['Kitap']);
  });

  test('yanlış klasördeki boş veritabanı kenara alınır, bir daha bakılmaz',
      () async {
    await seed(canonical, 'Kitap');
    await seed(stray, '', empty: true);

    expect(
      await recoverStrayV12Data(canonical: canonical, stray: stray, now: now),
      isNull,
    );
    expect(dbIn(stray).existsSync(), isFalse);
    expect(
      File('${dbIn(stray).path}.bos-20261008-2030').existsSync(),
      isTrue,
    );
    expect(await habitNames(canonical), ['Kitap']);
  });

  test('asıl klasör yoksa yanlış klasördeki veri olduğu gibi taşınır',
      () async {
    await seed(stray, 'Egzersiz');

    final saved = await recoverStrayV12Data(
      canonical: canonical,
      stray: stray,
      now: now,
    );

    expect(await habitNames(canonical), ['Egzersiz']);
    expect(saved!.existsSync(), isTrue);
    expect(p.basename(saved.parent.path), 'yedekler');
    expect(dbIn(stray).existsSync(), isFalse);
    expect(
      File('${dbIn(stray).path}.tasindi-20261008-2030').existsSync(),
      isTrue,
    );

    final db = AppDatabase.forTesting(NativeDatabase(dbIn(canonical)));
    final entries = await db.getAllEntries();
    await db.close();
    expect(entries.single.date, '2026-10-01');
  });

  test('iki tarafta da veri varsa birleştirir, eskiyi önce yedekler', () async {
    // Both have a habit with id 1 — a real collision the merge must survive.
    await seed(canonical, 'Kitap', createdAt: DateTime(2026, 9, 1));
    await seed(stray, 'Egzersiz', createdAt: DateTime(2026, 9, 27));

    await recoverStrayV12Data(canonical: canonical, stray: stray, now: now);

    expect(await habitNames(canonical), ['Egzersiz', 'Kitap']);
    expect(
      File('${dbIn(canonical).path}.v12-oncesi-20261008-2030').existsSync(),
      isTrue,
    );
  });

  test('ikinci açılışta tekrar çalışmaz', () async {
    await seed(stray, 'Egzersiz');
    await recoverStrayV12Data(canonical: canonical, stray: stray, now: now);
    await recoverStrayV12Data(
      canonical: canonical,
      stray: stray,
      now: now.add(const Duration(minutes: 5)),
    );
    expect(await habitNames(canonical), ['Egzersiz']);
  });
}
