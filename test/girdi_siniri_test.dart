import 'package:aktenak_habit_tracker/app.dart';
import 'package:aktenak_habit_tracker/core/enums.dart';
import 'package:aktenak_habit_tracker/data/database/database.dart';
import 'package:aktenak_habit_tracker/data/providers.dart';
import 'package:aktenak_habit_tracker/data/sync/sync_format.dart';
import 'package:aktenak_habit_tracker/shared/widgets/count_entry_dialog.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'helpers.dart';

/// Arayüz girişi, senkron ayrıştırıcısının ve tabloların sınırlarını aşamaz:
/// aşarsa ya kayıt sessizce düşer ya da cihazın kendi .habitsync dosyası reddedilir.
void main() {
  setUpAll(() => initializeDateFormatting('tr'));

  testWidgets('alışkanlık adı, açıklama ve hedef sınırlarda kısılır',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const AktenakApp(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Alışkanlık ekle (Ctrl+N)'));
    await tester.pumpAndSettle();

    Finder field(String label) => find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextField, label));

    await tester.enterText(field('Ad'), 'a' * (syncMaxHabitName + 50));
    await tester.enterText(
        field('Açıklama (opsiyonel)'), 'b' * (syncMaxTextLength + 50));
    await tester.tap(find.text(HabitKind.count.label));
    await tester.pumpAndSettle();
    await tester.enterText(field('Günlük hedef'), '12000000000');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    final h = (await db.getAllHabits()).single; // diyalog kapandı, kayıt var
    expect(h.name.length, syncMaxHabitName);
    expect(h.description!.length, syncMaxTextLength);
    expect(h.target, lessThanOrEqualTo(syncMaxCount));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('hızlı eklenen görev başlığı sınırda kısılır', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    tester.view.physicalSize = const Size(1400, 950);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const AktenakApp(),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Bugüne görev ekle…'),
        'c' * (syncMaxTaskTitle + 50));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect((await db.getAllTasks()).single.title.length, syncMaxTaskTitle);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('sayaç miktarı senkron sınırını aşamaz', (tester) async {
    int? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await CountEntryDialog.show(context,
              habit: testHabit(kind: 'count', target: 10000), current: 0),
          child: const Text('ac'),
        ),
      ),
    ));
    await tester.tap(find.text('ac'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '99999999999');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(result, syncMaxCount);
  });
}
