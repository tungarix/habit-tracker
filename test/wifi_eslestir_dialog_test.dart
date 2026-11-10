import 'dart:async';
import 'dart:io';

import 'package:aktenak_habit_tracker/core/wifi_sync/sertifika.dart';
import 'package:aktenak_habit_tracker/core/wifi_sync/sunucu.dart';
import 'package:aktenak_habit_tracker/data/database/database.dart';
import 'package:aktenak_habit_tracker/data/providers.dart';
import 'package:aktenak_habit_tracker/features/eslestir/eslestir_dialog.dart';
import 'package:aktenak_habit_tracker/features/eslestir/qr_cizici.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'wifi_test_yardimci.dart';

/// "Telefonla eşleştir" penceresi, gerçek sunucu (127.0.0.1) ve gerçek
/// pinleyen istemciyle; kamera/LAN/Windows güvenlik duvarı kanıtlanmaz.
/// Gerçek ağ işi testWidgets'ın sahte zamanlayıcı bölgesinde değil, kök bölgede başlar.
Future<T> gercek<T>(Future<T> Function() f) => Zone.root.run(() => f().catchError((Object e, StackTrace st) { throw e; }));

void main() {
  setUpAll(() async {
    HttpOverrides.global = null; // testWidgets gerçek HttpClient'ı sahteyle değiştirir
    await initializeDateFormatting('tr');
    testCert = await OturumSertifikasi.uret(['127.0.0.1']);
  });

  late AppDatabase db;
  late Directory dataDir;
  EslestirmeSunucusu? sunucu;

  Future<void> ac(WidgetTester t, {List<String> adresler = const ['127.0.0.1']}) async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    dataDir = Directory.systemTemp.createTempSync('aktenak_eslestir');
    addTearDown(() => dataDir.deleteSync(recursive: true));
    sunucu = null;
    t.view.physicalSize = const Size(1000, 1600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dataDirectoryProvider.overrideWith((ref) async => dataDir),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => EslestirDialog(
                      sunucuFabrikasi: ({
                        required durumAl,
                        required onizle,
                        required uygula,
                        required yedekAl,
                      }) =>
                          sunucu = EslestirmeSunucusu(
                            durumAl: durumAl,
                            onizle: onizle,
                            uygula: uygula,
                            yedekAl: yedekAl,
                            sunucuAdi: 'ARDA-PC',
                            adresler: adresler,
                            sertifika: testCert,
                            ayar: const EslestirmeAyar(loopbackIzinli: true),
                          ),
                    ),
                  ),
                  child: const Text('Aç'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Aç'));
    await t.pump();
  }

  /// Yanıtı beklerken sahte bölgedeki sunucu mikro görevleri de işlensin diye pompalar.
  Future<R> sonuc<R>(WidgetTester t, Future<R> f) async {
    R? r;
    var bitti = false;
    unawaited(f.then((v) {
      r = v;
      bitti = true;
    }));
    for (var i = 0; i < 100 && !bitti; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(bitti, isTrue, reason: 'yanıt gelmedi');
    return r as R;
  }

  Future<void> bekle(WidgetTester t, Finder f) async {
    for (var i = 0; i < 100; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(milliseconds: 50));
      if (f.evaluate().isNotEmpty) return;
    }
    fail('Bulunamadı: $f');
  }

  testWidgets('tam akış: QR, Onay 2, özet, Onay 4, sonuç; yedek alınır, sunucu kapanır', (t) async {
    await ac(t);
    await db.insertHabit(HabitsCompanion.insert(name: 'Yürüyüş', colorValue: 0xFF4CAF50, iconCodePoint: 0xe000));
    final sem = t.ensureSemantics();
    await bekle(t, find.textContaining('Kalan süre'));
    await t.pump();
    expect(t.getSemantics(find.byType(QrCizici)).label, contains('Eşleştirme QR kodu'));
    expect(find.textContaining('habitsync://p?v=1'), findsOneWidget);
    expect(t.getSize(find.widgetWithText(TextButton, 'İptal')).height, greaterThanOrEqualTo(48));

    final q = sunucu!.qr!;
    final tel = (await t.runAsync(telefonDosyasi))!;
    final f1 = gercek(() => istek(q, 'POST', '/v1/session', bearer: q.jeton, govde: oturumGovdesi));
    await bekle(t, find.textContaining('bağlanmak istiyor'));
    expect(find.textContaining('«Pixel 7»'), findsOneWidget);
    expect(t.getSize(find.widgetWithText(FilledButton, 'Evet, bu benim telefonum')).height,
        greaterThanOrEqualTo(48));
    await t.tap(find.text('Evet, bu benim telefonum'));
    await t.pump();
    final key = (await sonuc(t, f1)).json['session'] as String;

    final f2 = gercek(() => istek(q, 'POST', '/v1/state', bearer: key, govde: tel));
    await bekle(t, find.textContaining('1 eklenecek'));
    expect(find.textContaining('Alışkanlık: 1 eklenecek'), findsOneWidget);
    expect(await db.getAllHabits().then((l) => l.length), 1, reason: 'onaydan önce veri değişmez');
    await t.tap(find.text('Uygula'));
    await t.pump();
    expect((await sonuc(t, f2)).kod, 200);

    await bekle(t, find.textContaining('Eşleştirme tamam'));
    expect(await db.getAllHabits().then((l) => l.length), 2);
    final yedekler = Directory('${dataDir.path}${Platform.pathSeparator}yedekler').listSync();
    expect(yedekler.where((e) => e.path.contains('aktenak-sync-')).length, 1);

    await t.tap(find.text('Kapat'));
    await t.pumpAndSettle();
    expect(find.byType(EslestirDialog), findsNothing);
    expect(sunucu!.durum, EslestirmeDurum.tamam);
    sem.dispose();
  });

  testWidgets('İptal: oturum kapanır, veri değişmez', (t) async {
    await ac(t);
    await bekle(t, find.textContaining('Kalan süre'));
    await t.tap(find.text('İptal'));
    await t.pump();
    expect(find.textContaining('iptal edildi'), findsOneWidget);
    expect(sunucu!.durum, EslestirmeDurum.iptal);
    await t.tap(find.text('Kapat'));
    await t.pumpAndSettle();
  });

  testWidgets('Onay 2 "Hayır": telefon 403 alır', (t) async {
    await ac(t);
    await bekle(t, find.textContaining('Kalan süre'));
    final q = sunucu!.qr!;
    final f = gercek(() => istek(q, 'POST', '/v1/session', bearer: q.jeton, govde: oturumGovdesi));
    await bekle(t, find.textContaining('bağlanmak istiyor'));
    await t.tap(find.text('Hayır'));
    await t.pump();
    expect((await sonuc(t, f)).hata, 'reddedildi');
    expect(find.textContaining('reddedildi'), findsOneWidget);
    await t.tap(find.text('Kapat'));
    await t.pumpAndSettle();
  });

  testWidgets('özel ağ yoksa açıklayıcı mesaj, sunucu açılmaz', (t) async {
    await ac(t, adresler: const []);
    await bekle(t, find.textContaining('Özel bir ağa bağlı değilsin'));
    expect(find.textContaining('dosya ile senkronu'), findsOneWidget);
    await t.tap(find.text('Kapat'));
    await t.pumpAndSettle();
  });
}
