import 'package:aktenak_habit_tracker/data/database/database.dart';
import 'package:aktenak_habit_tracker/data/providers.dart';
import 'package:aktenak_habit_tracker/features/tasks/task_edit_dialog.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'helpers.dart';

void main() {
  setUpAll(() => initializeDateFormatting('tr'));

  testWidgets('bir yıldan eski bitiş günü olan görevde tarih seçici açılır', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final eski = DateTime(DateTime.now().year - 3, 5, 17);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          locale: const Locale('tr'),
          supportedLocales: const [Locale('tr'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  TaskEditDialog.show(context, existing: testTask(dueDay: eski)),
              child: const Text('aç'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ActionChip));
    await tester.pumpAndSettle();

    // Eski haliyle initialDate < firstDate: debug'da AssertionError.
    expect(tester.takeException(), isNull);
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('Sil onay ister; İptal görevi korur, onay siler', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final id = await tester.runAsync(() => db.insertTask(
          TasksCompanion.insert(title: 'Sil beni', createdAt: Value(DateTime(2026, 1, 1))),
        ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          locale: const Locale('tr'),
          supportedLocales: const [Locale('tr'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => TaskEditDialog.show(context,
                  existing: testTask(id: id!, title: 'Sil beni')),
              child: const Text('aç'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Sil'));
    await tester.pumpAndSettle();
    expect(find.text('Görev silinsin mi?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'İptal').last);
    await tester.pumpAndSettle();
    expect((await tester.runAsync(db.getAllTasks))!.length, 1);

    await tester.tap(find.widgetWithText(TextButton, 'Sil'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sil'));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect((await tester.runAsync(db.getAllTasks))!, isEmpty);
  });
}
