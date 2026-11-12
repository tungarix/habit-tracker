import 'package:aktenak_habit_tracker/app.dart';
import 'package:aktenak_habit_tracker/core/date_utils.dart';
import 'package:aktenak_habit_tracker/core/enums.dart';
import 'package:aktenak_habit_tracker/data/database/database.dart';
import 'package:aktenak_habit_tracker/data/providers.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('tr'));

  Future<AppDatabase> seed() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final id = await db.insertHabit(HabitsCompanion.insert(
      name: 'Su iç',
      colorValue: 0xFF2196F3,
      iconCodePoint: 0xe000,
      createdAt: Value(DateTime.now().subtract(const Duration(days: 40))),
    ));
    // Son 7 gün: 5 ✓ + 2 – (atlandı).
    final t = today();
    for (var i = 0; i < 7; i++) {
      await db.setEntryStatus(id, formatYmd(t.subtract(Duration(days: i))),
          i == 2 || i == 4 ? EntryStatus.skipped : EntryStatus.done);
    }
    return db;
  }

  Future<void> pump(WidgetTester tester, AppDatabase db, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const AktenakApp(),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('haftalık yüzde atlanan günü paydadan çıkarır (5 ✓ + 2 – = %100)',
      (tester) async {
    final db = await seed();
    addTearDown(db.close);
    await pump(tester, db, const Size(1400, 950));

    expect(find.text('%71'), findsNothing); // 5/7 değil
    expect(find.text('%100'), findsWidgets); // 5/5
    await dispose(tester);
  });

  testWidgets('pencere sütun eşiğini geçince çalışan odak sayacı kaybolmaz',
      (tester) async {
    final db = await seed();
    addTearDown(db.close);
    await pump(tester, db, const Size(1400, 950));

    await tester.tap(find.text('Odak başlat'));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Bitir'), findsOneWidget);

    for (final size in const [Size(900, 800), Size(420, 900), Size(1400, 950)]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('Bitir'), findsOneWidget, reason: '$size');
    }
    await dispose(tester);
  });
}
