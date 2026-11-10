import 'dart:io';

import 'package:aktenak_habit_tracker/data/database/database.dart';
import 'package:aktenak_habit_tracker/data/providers.dart';
import 'package:aktenak_habit_tracker/features/backup/backup_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// "Yedek & Ayarlar" has the phone-sync section: two buttons, nothing else new.
void main() {
  setUpAll(() => initializeDateFormatting('tr'));

  testWidgets('Telefonla senkron bölümü iki düğmeyle görünür', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final dataDir = Directory.systemTemp.createTempSync('aktenak_syncui');
    addTearDown(() => dataDir.deleteSync(recursive: true));
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dataDirectoryProvider.overrideWith((ref) async => dataDir),
        ],
        child: const MaterialApp(home: BackupScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Telefonla senkron: dosya dışa/içe aktar'), findsOneWidget);
    expect(find.text('Telefon için dışa aktar'), findsOneWidget);
    expect(find.text('Telefondan içe aktar'), findsOneWidget);
    // The older backup actions are still there.
    expect(find.text('Dışa aktar'), findsOneWidget);
    expect(find.text('İçe aktar'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
