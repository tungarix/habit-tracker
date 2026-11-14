import 'package:aktenak_habit_tracker/app.dart';
import 'package:aktenak_habit_tracker/core/date_utils.dart';
import 'package:aktenak_habit_tracker/core/enums.dart';
import 'package:aktenak_habit_tracker/data/database/database.dart';
import 'package:aktenak_habit_tracker/data/providers.dart';
import 'package:aktenak_habit_tracker/shared/theme.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

String _gun(int onceki) =>
    formatYmd(today().subtract(Duration(days: onceki)));

void main() {
  setUpAll(() => initializeDateFormatting('tr'));

  Future<AppDatabase> bellekDb() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    return db;
  }

  Future<void> ac(WidgetTester tester, AppDatabase db) async {
    tester.view.physicalSize = const Size(1400, 950);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const AktenakApp(),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> bekle(WidgetTester tester) async {
    await tester.pumpAndSettle();
  }

  Future<void> gecmiseGit(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Geçmiş'));
    await bekle(tester);
  }

  Future<void> kapat(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  final silDugmesi = find.byWidgetPredicate(
      (w) => w is IconButton && (w.tooltip ?? '').startsWith('Sil: '));

  testWidgets('Geçmiş: notlar yeniden eskiye sıralı görünür', (tester) async {
    final db = await bellekDb();
    await db.setMood(_gun(3), 2, note: 'eski not');
    await db.setMood(_gun(2), 4, note: 'yeni not');
    await ac(tester, db);
    await gecmiseGit(tester);

    expect(find.text('Ruh hali geçmişi'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('yeni not')).dy,
      lessThan(tester.getTopLeft(find.text('eski not')).dy),
    );
    await kapat(tester);
  });

  testWidgets('Geçmiş: silme onayı iptalde korur, Sil siler', (tester) async {
    final db = await bellekDb();
    await db.setMood(_gun(2), 4, note: 'silinecek');
    await ac(tester, db);
    await gecmiseGit(tester);

    await tester.tap(silDugmesi);
    await bekle(tester);
    expect(find.text('Bu günün kaydı silinsin mi?'), findsOneWidget);
    await tester.tap(find.text('İptal'));
    await bekle(tester);
    expect(await tester.runAsync(() => db.getAllMoods()), hasLength(1));
    expect(find.text('silinecek'), findsOneWidget);

    await tester.tap(silDugmesi);
    await bekle(tester);
    await tester.tap(find.text('Sil'));
    await bekle(tester);
    expect(await tester.runAsync(() => db.getAllMoods()), isEmpty);
    expect(find.text('silinecek'), findsNothing);
    expect(find.text('Henüz ruh hali kaydı yok.'), findsOneWidget);
    await kapat(tester);
  });

  testWidgets('Geçmiş: not düzenlenir, Notu sil notu temizler ruh hali kalır',
      (tester) async {
    final db = await bellekDb();
    final gun = _gun(2);
    await db.setMood(gun, 4, note: 'ilk');
    await ac(tester, db);
    await gecmiseGit(tester);

    await tester.tap(find.text('ilk'));
    await bekle(tester);
    expect(find.text('Bugüne kısa not'), findsNothing);
    final d = parseYmd(gun);
    expect(
      find.descendant(
        of: find.byType(AlertDialog).last,
        matching: find.textContaining('${d.day} '),
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.descendant(
          of: find.byType(AlertDialog).last, matching: find.byType(TextField)),
      'güncel',
    );
    await tester.tap(find.text('Kaydet'));
    await bekle(tester);
    expect(find.text('güncel'), findsOneWidget);

    await tester.tap(find.text('güncel'));
    await bekle(tester);
    await tester.tap(find.text('Notu sil'));
    await bekle(tester);
    final kayit = (await tester.runAsync(() => db.getMood(gun)))!;
    expect(kayit.note, isNull);
    expect(kayit.mood, 4);
    expect(find.text('Not yok'), findsOneWidget);
    await kapat(tester);
  });

  testWidgets('Ortalama satırı: 4 ve 2 → 3,0', (tester) async {
    final db = await bellekDb();
    await db.setMood(_gun(1), 4);
    await db.setMood(_gun(2), 2);
    await ac(tester, db);
    expect(find.text('Son 30 gün ortalaması: 3,0 / 5 (2 kayıt)'),
        findsOneWidget);
    await kapat(tester);
  });

  testWidgets('Ortalama satırı kayıt yokken görünmez', (tester) async {
    final db = await bellekDb();
    await ac(tester, db);
    expect(find.textContaining('Son 30 gün ortalaması'), findsNothing);
    await kapat(tester);
  });

  testWidgets('Seçili ruh haline tekrar dokun: notlu günde onay, İptal korur',
      (tester) async {
    final db = await bellekDb();
    final gun = formatYmd(today());
    await db.setMood(gun, Mood.memnun.value, note: 'kalsın');
    await ac(tester, db);

    // Seçili ruh hali başlıkta da yazdığı için Semantics etiketiyle değil ikonla bul.
    final secili = find.byIcon(Mood.memnun.icon);
    await tester.tap(secili);
    await bekle(tester);
    expect(find.text('Ruh hali silinsin mi?'), findsOneWidget);
    await tester.tap(find.text('İptal'));
    await bekle(tester);
    expect((await tester.runAsync(() => db.getMood(gun)))!.note, 'kalsın');

    await tester.tap(secili);
    await bekle(tester);
    await tester.tap(find.text('Sil'));
    await bekle(tester);
    expect(await tester.runAsync(() => db.getMood(gun)), isNull);
    await kapat(tester);
  });
}
