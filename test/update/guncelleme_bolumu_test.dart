import 'dart:io';

import 'package:aktenak_habit_tracker/data/database/database.dart';
import 'package:aktenak_habit_tracker/data/update/ag.dart';
import 'package:aktenak_habit_tracker/data/update/akis.dart';
import 'package:aktenak_habit_tracker/data/update/ayarlar.dart';
import 'package:aktenak_habit_tracker/data/update/guncelleyici.dart';
import 'package:aktenak_habit_tracker/features/update/guncelleme_bolumu.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;

import 'yardimci.dart';

/// Gerçek G/Ç (yerel soket) bitene kadar gerçek zamanla bekler, her turda kare çizer.
Future<void> bekle(WidgetTester t, Finder f) async {
  for (var i = 0; i < 80 && f.evaluate().isEmpty; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// Ayarlar bölümü: denetle -> indir -> kur, sahte GitHub + sahte kurucu (gerçek kurulum YOK).
void main() {
  setUpAll(() => initializeDateFormatting('tr'));
  // flutter_test her HTTP isteğine 400 döndürür; yerel sahte sunucu için gerçek HttpClient gerekir.
  setUp(() => HttpOverrides.global = null);

  testWidgets('denetle, indir ve doğrula, kapat ve güncelle akışı', (
    tester,
  ) async {
    final gh = await tester.runAsync(() => SahteGithub(zipUret()).baslat());
    final tmp = Directory.systemTemp.createTempSync('bolum_test');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      await gh!.kapat();
      await db.close();
      tmp.deleteSync(recursive: true);
    });
    final olaylar = <String>[];
    final g = Guncelleyici(
      ayarlar: (await tester.runAsync(() => GuncellemeAyarlari.yukle(db)))!,
      klasor: Directory(p.join(tmp.path, 'g')),
      surum: '1.3.3',
      ag: Ag(surum: '1.3.3', apiTaban: gh!.taban, ekSunucular: {'127.0.0.1'}),
      acikAnahtar: gh.acikAnahtar,
    );
    final kurucu = Kurucu(
      kurulumKlasoru: tmp,
      sonucDosyasi: File(p.join(tmp.path, 's.json')),
      yedekAl: () async => olaylar.add('yedek'),
      uygulayiciyiBaslat: (exe, args) async => olaylar.add('baslat'),
      kapat: () async => olaylar.add('kapat'),
    );

    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          guncelleyiciProvider.overrideWith((ref) async => g),
          kurucuProvider.overrideWith((ref) async => kurucu),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: GuncellemeBolumu()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Hiç sorulmadı: ağ isteği yok, teklif yok.
    expect(find.text('Sürüm 1.3.3'), findsOneWidget);
    expect(find.text('Henüz denetlenmedi.'), findsOneWidget);
    expect(find.textContaining('Yeni sürüm 9.9.9'), findsNothing);
    expect(gh.istekler, isEmpty);

    await tester.tap(find.text('Şimdi denetle'));
    await bekle(tester, find.textContaining('Yeni sürüm 9.9.9'));
    expect(find.textContaining('Yeni sürüm 9.9.9'), findsOneWidget);
    expect(find.textContaining('imzası ve SHA-256'), findsOneWidget);

    await tester.tap(find.text('İndir ve doğrula'));
    await bekle(tester, find.textContaining('Güncelleme hazır'));
    expect(find.textContaining('Güncelleme hazır'), findsOneWidget);
    expect(olaylar, isEmpty, reason: 'indirme kurulum başlatmaz');

    await tester.tap(find.text('Kapat ve güncelle'));
    await tester.pumpAndSettle();
    expect(olaylar, ['yedek', 'baslat', 'kapat']);
  });

  testWidgets('uygulayıcı başlatılamazsa hata gösterilir, düğmeler geri açılır', (
    tester,
  ) async {
    final gh = await tester.runAsync(() => SahteGithub(zipUret()).baslat());
    final tmp = Directory.systemTemp.createTempSync('bolum_test3');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      await gh!.kapat();
      await db.close();
      tmp.deleteSync(recursive: true);
    });
    final olaylar = <String>[];
    final g = Guncelleyici(
      ayarlar: (await tester.runAsync(() => GuncellemeAyarlari.yukle(db)))!,
      klasor: Directory(p.join(tmp.path, 'g')),
      surum: '1.3.3',
      ag: Ag(surum: '1.3.3', apiTaban: gh!.taban, ekSunucular: {'127.0.0.1'}),
      acikAnahtar: gh.acikAnahtar,
    );
    final kurucu = Kurucu(
      kurulumKlasoru: tmp,
      sonucDosyasi: File(p.join(tmp.path, 's.json')),
      yedekAl: () async {},
      // Antivirüs / SmartScreen / Windows dışı sistem: Process.start fırlatır.
      uygulayiciyiBaslat: (exe, args) async =>
          throw const ProcessException('x.exe', [], 'engellendi'),
      kapat: () async => olaylar.add('kapat'),
    );
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          guncelleyiciProvider.overrideWith((ref) async => g),
          kurucuProvider.overrideWith((ref) async => kurucu),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: GuncellemeBolumu()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Şimdi denetle'));
    await bekle(tester, find.text('İndir ve doğrula'));
    await tester.tap(find.text('İndir ve doğrula'));
    await bekle(tester, find.text('Kapat ve güncelle'));
    await tester.tap(find.text('Kapat ve güncelle'));
    await tester.pumpAndSettle();

    expect(find.textContaining('(uygulayici_baslamadi)'), findsOneWidget);
    expect(olaylar, isEmpty, reason: 'uygulama kapanmamalı');
    final kapatDugme = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Kapat ve güncelle'),
    );
    expect(kapatDugme.onPressed, isNotNull, reason: 'kullanıcı yeniden deneyebilmeli');
  });

  testWidgets('doğrulama hatası Türkçe metin + kodla gösterilir', (
    tester,
  ) async {
    final gh = await tester.runAsync(() => SahteGithub(zipUret()).baslat());
    final tmp = Directory.systemTemp.createTempSync('bolum_test2');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      await gh!.kapat();
      await db.close();
      tmp.deleteSync(recursive: true);
    });
    gh!.yanlisOzet = '0' * 64;
    final g = Guncelleyici(
      ayarlar: (await tester.runAsync(() => GuncellemeAyarlari.yukle(db)))!,
      klasor: Directory(p.join(tmp.path, 'g')),
      surum: '1.3.3',
      ag: Ag(surum: '1.3.3', apiTaban: gh.taban, ekSunucular: {'127.0.0.1'}),
      acikAnahtar: gh.acikAnahtar,
    );
    final kurucu = Kurucu(
      kurulumKlasoru: tmp,
      sonucDosyasi: File(p.join(tmp.path, 's.json')),
      yedekAl: () async {},
      uygulayiciyiBaslat: (_, _) async {},
      kapat: () async {},
    );
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          guncelleyiciProvider.overrideWith((ref) async => g),
          kurucuProvider.overrideWith((ref) async => kurucu),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: GuncellemeBolumu()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Şimdi denetle'));
    await bekle(tester, find.text('İndir ve doğrula'));
    await tester.tap(find.text('İndir ve doğrula'));
    await bekle(tester, find.textContaining('(ozet_uyusmuyor)'));
    expect(find.textContaining('(ozet_uyusmuyor)'), findsOneWidget);
    expect(find.text('Kapat ve güncelle'), findsNothing);
    expect(g.klasor.existsSync(), isFalse);
  });
}
