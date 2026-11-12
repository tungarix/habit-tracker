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
        name: 'Kitap',
        colorValue: 0xFF2196F3,
        iconCodePoint: 0xe000,
        sortOrder: const Value(0),
      ),
    );
  });

  tearDown(() => db.close());

  test('aynı hücreye üst üste iki dokunuş: ✓ sonra ✗, hata yok', () async {
    final sonuc = await Future.wait([
      db.cycleEntry(id, '2026-05-01'),
      db.cycleEntry(id, '2026-05-01'),
    ]);
    expect(sonuc, [EntryStatus.done, EntryStatus.missed]);
    expect((await db.getEntry(id, '2026-05-01'))!.status, EntryStatus.missed);
  });
}
