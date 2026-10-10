import 'package:aktenak_habit_tracker/core/enums.dart';
import 'package:aktenak_habit_tracker/data/database/database.dart';
import 'package:aktenak_habit_tracker/data/providers.dart';
import 'package:aktenak_habit_tracker/features/habits/habits_screen.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Aktif bir alışkanlık doğrudan silinebilmeli (eskiden önce arşivlemek şarttı).
void main() {
  setUpAll(() => initializeDateFormatting('tr'));

  late AppDatabase db;
  late int keepId;
  late int dropId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    keepId = await db.insertHabit(
      HabitsCompanion.insert(
        name: 'Kitap',
        colorValue: 0xFF2196F3,
        iconCodePoint: 0xe000,
        sortOrder: const Value(0),
      ),
    );
    dropId = await db.insertHabit(
      HabitsCompanion.insert(
        name: 'Gitar',
        colorValue: 0xFF9C27B0,
        iconCodePoint: 0xe001,
        sortOrder: const Value(1),
      ),
    );
    await db.setEntryStatus(keepId, '2026-10-01', EntryStatus.done);
    await db.setEntryStatus(dropId, '2026-10-01', EntryStatus.done);
    await db.setEntryStatus(dropId, '2026-10-02', EntryStatus.done);
  });

  tearDown(() => db.close());

  Future<void> openMenuOf(WidgetTester tester, String habitName) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: HabitsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final tile = find.ancestor(
      of: find.text(habitName),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: tile, matching: find.byType(PopupMenuButton<String>)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('aktif alışkanlık menüden onayla silinir, kayıtları da gider', (
    tester,
  ) async {
    await openMenuOf(tester, 'Gitar');
    await tester.tap(find.text('Sil…'));
    await tester.pumpAndSettle();

    expect(find.text('Kalıcı olarak sil?'), findsOneWidget);
    expect(find.textContaining('Arşivle'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, 'Sil'));
    await tester.pumpAndSettle();

    final names = (await db.getAllHabits()).map((h) => h.name).toList();
    expect(names, ['Kitap']);
    final entries = await db.getAllEntries();
    expect(entries.map((e) => e.habitId).toSet(), {keepId});
    expect(entries, hasLength(1));
    expect(find.text('Gitar'), findsNothing);

    await dispose(tester);
  });

  testWidgets('İptal alışkanlığa dokunmaz', (tester) async {
    await openMenuOf(tester, 'Gitar');
    await tester.tap(find.text('Sil…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('İptal'));
    await tester.pumpAndSettle();

    expect(await db.getAllHabits(), hasLength(2));
    expect(await db.getEntry(dropId, '2026-10-02'), isNotNull);
    expect(find.text('Gitar'), findsOneWidget);

    await dispose(tester);
  });
}
