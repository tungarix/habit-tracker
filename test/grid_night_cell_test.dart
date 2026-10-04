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

/// The monthly grid decides per cell whether a day is "before the habit
/// existed" (greyed out, not tappable). That start day has to be the tracking
/// day the habit was created on: a habit added at 01:30 started on the day
/// that was still running, and its cell must accept a mark.
void main() {
  setUpAll(() => initializeDateFormatting('tr'));

  testWidgets('a habit created after midnight can be marked on its first day',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // The tracking day the app is on right now, whatever time the test runs.
    // Created "the next night at 01:30": its tracking day is [t], while its
    // calendar day is the day after. (The stamp is set by hand so the case does
    // not depend on the wall clock.)
    final t = today();
    final created = DateTime(t.year, t.month, t.day + 1, 1, 30);
    final habitId = await db.insertHabit(HabitsCompanion.insert(
      name: 'Gece eklenen',
      colorValue: 0xFF4CAF50,
      iconCodePoint: 0xe000,
      createdAt: Value(created),
    ));

    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const AktenakApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aylık'));
    await tester.pumpAndSettle();

    Finder cellOf(DateTime day) =>
        find.byKey(ValueKey('grid-cell-$habitId-${formatYmd(day)}'));

    // A day before the creation tracking day stays closed (when it is still in
    // the displayed month): the fix must not open the whole month.
    if (t.day > 1) {
      final before = previousDay(t);
      await tester.ensureVisible(cellOf(before));
      await tester.tap(cellOf(before));
      await tester.pumpAndSettle();
      expect(await db.getEntry(habitId, formatYmd(before)), isNull,
          reason: 'a day before the habit existed must not be markable');
    }

    // The creation tracking day accepts a tap: the first press marks it ✓.
    await tester.ensureVisible(cellOf(t));
    await tester.tap(cellOf(t));
    await tester.pumpAndSettle();

    final entry = await db.getEntry(habitId, formatYmd(t));
    expect(entry, isNotNull,
        reason: 'the creation tracking day should be markable in the grid');
    expect(entry!.status, EntryStatus.done);

    // Dispose the tree and flush drift's stream-cleanup timers.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
