import 'package:aktenak_habit_tracker/core/enums.dart';
import 'package:aktenak_habit_tracker/data/database/database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late int id;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    id = await db.insertHabit(
      HabitsCompanion.insert(
        name: 'Adım',
        colorValue: 0xFF2196F3,
        iconCodePoint: 0xe000,
        sortOrder: const Value(0),
        kind: const Value('count'),
        target: const Value(10),
      ),
    );
    await db.setEntryAmount(id, '2026-05-01', 6, 10); // ✗
    await db.setEntryAmount(id, '2026-05-02', 12, 10); // ✓
    await db.setEntryStatus(id, '2026-05-03', EntryStatus.skipped);
  });

  tearDown(() => db.close());

  Future<void> hedefYap(int hedef) async =>
      db.updateHabit((await db.getHabit(id))!.copyWith(target: hedef));

  test('hedef düşünce yeni hedefe ulaşmış ✗ gün ✓ olur', () async {
    await hedefYap(5);
    expect((await db.getEntry(id, '2026-05-01'))!.status, EntryStatus.done);
    expect((await db.getEntry(id, '2026-05-03'))!.status, EntryStatus.skipped);
  });

  test('hedefe hâlâ ulaşmayan ✗ gün ✗ kalır; hedef yükselince ✓ gün bozulmaz',
      () async {
    await hedefYap(8);
    expect((await db.getEntry(id, '2026-05-01'))!.status, EntryStatus.missed);
    await hedefYap(50);
    expect((await db.getEntry(id, '2026-05-02'))!.status, EntryStatus.done);
  });
}
