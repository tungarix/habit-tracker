import 'package:aktenak_habit_tracker/app.dart';
import 'package:aktenak_habit_tracker/data/database/database.dart';
import 'package:aktenak_habit_tracker/data/providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// End-to-end (widget-level) check of the "add habit" flow: open the dialog
/// from the app bar, type a name, hit Kaydet, and expect the habit in the DB.
void main() {
  setUpAll(() async {
    // sqlite3 3.x resolves its native library through native assets, so an
    // in-memory NativeDatabase works in host tests without extra setup.
    await initializeDateFormatting('tr');
  });

  testWidgets('add a habit through the edit dialog', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const AktenakApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Open the add dialog from the app bar.
    await tester.tap(find.byTooltip('Alışkanlık ekle (Ctrl+N)'));
    await tester.pumpAndSettle();
    expect(find.text('Yeni alışkanlık'), findsOneWidget);

    // Type a name and save. The finder is scoped to the dialog: the dashboard
    // behind it has its own text field (quick-add task) that would otherwise
    // match first.
    await tester.enterText(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          )
          .first,
      'Deneme alışkanlık',
    );
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    // Dialog closed, habit persisted.
    expect(find.text('Yeni alışkanlık'), findsNothing);
    final habits = await db.getAllHabits();
    expect(habits, hasLength(1));
    expect(habits.single.name, 'Deneme alışkanlık');
    expect(habits.single.category, 'beden');

    // And it surfaces on the dashboard (today's list and the momentum card
    // both name it, so this only asserts that it appeared at all).
    expect(find.text('Deneme alışkanlık'), findsAtLeastNWidgets(1));

    // Dispose the tree and flush drift's zero-duration stream-cleanup timers
    // so the test binding's pending-timer check stays green.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
