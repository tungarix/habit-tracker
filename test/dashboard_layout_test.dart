import 'package:aktenak_habit_tracker/app.dart';
import 'package:aktenak_habit_tracker/core/enums.dart';
import 'package:aktenak_habit_tracker/data/database/database.dart';
import 'package:aktenak_habit_tracker/data/providers.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// A dense dashboard is exactly where RenderFlex overflows hide. These render
/// the real app, with real data, at the three layout breakpoints — an overflow
/// throws and fails the test.
void main() {
  setUpAll(() => initializeDateFormatting('tr'));

  Future<AppDatabase> seed() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());

    final walk = await db.insertHabit(HabitsCompanion.insert(
      name: '10 bin adım',
      colorValue: 0xFF2196F3,
      iconCodePoint: 0xe000,
      kind: const Value('count'),
      target: const Value(10000),
      category: const Value('beden'),
    ));
    final read = await db.insertHabit(HabitsCompanion.insert(
      name: 'Kitap oku 30 dk',
      colorValue: 0xFF4CAF50,
      iconCodePoint: 0xe001,
      category: const Value('zihin'),
    ));
    await db.insertHabit(HabitsCompanion.insert(
      name: 'Uzun isimli bir alışkanlık adı taşma testi için',
      colorValue: 0xFF9C27B0,
      iconCodePoint: 0xe002,
    ));

    final today = DateTime.now();
    String ymd(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

    for (var i = 0; i < 10; i++) {
      final day = ymd(today.subtract(Duration(days: i)));
      await db.setEntryAmount(walk, day, 8000 + i * 400, 10000);
      await db.setEntryStatus(read, day,
          i.isEven ? EntryStatus.done : EntryStatus.skipped);
      await db.setMood(day, (i % 5) + 1, note: i == 0 ? 'yoğun gün' : null);
    }

    await db.insertTask(TasksCompanion.insert(
      title: 'Bugün bitmesi gereken uzunca bir görev başlığı',
      dueDay: Value(ymd(today)),
      priority: const Value(2),
    ));
    await db.insertTask(TasksCompanion.insert(
      title: 'Geciken görev',
      dueDay: Value(ymd(today.subtract(const Duration(days: 3)))),
    ));
    await db.insertSession(
      kind: 'focus',
      startedAt: today.subtract(const Duration(hours: 2)),
      endedAt: today.subtract(const Duration(hours: 1)),
      durationS: 3600,
      day: ymd(today),
    );

    return db;
  }

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    final db = await seed();
    addTearDown(db.close);

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const AktenakApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> settleAndDispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('dashboard lays out at three columns (wide desktop)',
      (tester) async {
    await pumpAt(tester, const Size(1400, 950));
    expect(find.text('Bugün'), findsWidgets);
    expect(find.text('Son 30 gün'), findsOneWidget);
    expect(find.text('Odak'), findsOneWidget);
    expect(find.text('Bu hafta'), findsOneWidget);
    await settleAndDispose(tester);
  });

  testWidgets('dashboard lays out at two columns', (tester) async {
    await pumpAt(tester, const Size(900, 800));
    expect(find.text('Son 30 gün'), findsOneWidget);
    await settleAndDispose(tester);
  });

  testWidgets('dashboard lays out in one column (phone width)', (tester) async {
    await pumpAt(tester, const Size(420, 900));
    expect(find.text('Son 30 gün'), findsOneWidget);
    await settleAndDispose(tester);
  });

  testWidgets('every tab renders without overflowing', (tester) async {
    await pumpAt(tester, const Size(1280, 860));

    for (final tab in ['Aylık', 'Görevler', 'İstatistik', 'Panel']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
    }
    await settleAndDispose(tester);
  });
}
