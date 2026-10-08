import 'dart:io';

import 'package:aktenak_habit_tracker/core/constants.dart';
import 'package:aktenak_habit_tracker/data/database/database.dart';
import 'package:aktenak_habit_tracker/data/providers.dart';
import 'package:aktenak_habit_tracker/features/backup/backup_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Yedek & Ayarlar: tema seçimi ve "verilerin nerede" kartı.
void main() {
  setUpAll(() => initializeDateFormatting('tr'));

  testWidgets('tema seçimi kaydedilir, veri klasörü gösterilir', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final dataDir = Directory.systemTemp.createTempSync('aktenak_settings');
    addTearDown(() => dataDir.deleteSync(recursive: true));

    tester.view.physicalSize = const Size(1200, 1400);
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

    expect(find.text('Verilerin burada'), findsOneWidget);
    expect(find.text(dataDir.path), findsOneWidget);
    expect(find.textContaining('Henüz yok'), findsOneWidget);

    // "Sistem" is also the section heading; target the theme control itself.
    Finder segment(String label) => find.descendant(
      of: find.byType(SegmentedButton<ThemeMode>),
      matching: find.text(label),
    );

    await tester.tap(segment('Sistem'));
    await tester.pumpAndSettle();
    expect(await db.getSetting(AppConstants.themeModeKey), 'system');

    await tester.tap(segment('Açık'));
    await tester.pumpAndSettle();
    expect(await db.getSetting(AppConstants.themeModeKey), 'light');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
