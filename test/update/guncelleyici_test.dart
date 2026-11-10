import 'dart:io';

import 'package:aktenak_habit_tracker/data/database/database.dart';
import 'package:aktenak_habit_tracker/data/update/ag.dart';
import 'package:aktenak_habit_tracker/data/update/ayarlar.dart';
import 'package:aktenak_habit_tracker/data/update/guncelleyici.dart';
import 'package:aktenak_habit_tracker/data/update/paket.dart';
import 'package:aktenak_habit_tracker/data/update/saf.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'yardimci.dart';

Matcher _kod(String k) =>
    throwsA(isA<GuncellemeHatasi>().having((e) => e.kod, 'kod', k));

/// Sahte GitHub sunucusuyla (yerel, gerçek ağ yok) ağ + doğrulama + açma zinciri.
void main() {
  late SahteGithub gh;
  late Directory tmp;
  late AppDatabase db;
  late Guncelleyici g;

  Ag agKur(String mevcut) => Ag(
    surum: mevcut,
    apiTaban: gh.taban,
    ekSunucular: {'127.0.0.1'},
    zamanAsimi: const Duration(seconds: 5),
  );

  Future<void> kur(List<int> zip, {String mevcut = '1.3.3'}) async {
    gh = await SahteGithub(zip).baslat();
    tmp = Directory.systemTemp.createTempSync('guncelleyici_test');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    g = Guncelleyici(
      ayarlar: await GuncellemeAyarlari.yukle(db),
      klasor: Directory(p.join(tmp.path, 'guncelleme')),
      surum: mevcut,
      ag: agKur(mevcut),
    );
  }

  group('sahte GitHub', () {
    tearDown(() async {
      await gh.kapat();
      await db.close();
      tmp.deleteSync(recursive: true);
    });

    Future<Yayin> yeni() async {
      await g.denetle();
      expect(g.hataKodu, isNull);
      return g.teklif!;
    }

    test('denetle: yeni sürümü saklar; aynı sürümde teklif yok', () async {
      await kur(zipUret());
      final y = await yeni();
      expect(y.surum, '9.9.9');
      expect(g.sonDenetim, isNotNull);
      final ayni = Guncelleyici(
        ayarlar: g.ayarlar,
        klasor: g.klasor,
        surum: '9.9.9',
        ag: agKur('9.9.9'),
      );
      expect(ayni.teklif, isNull);
    });

    test('ilk onay yokken ağ isteği yok; açıksa otomatikAdim sorar', () async {
      await kur(zipUret());
      expect(g.denetim, isNull);
      expect(await g.otomatikAdim(), isFalse);
      await g.denetimYaz(false);
      expect(await g.otomatikAdim(), isFalse);
      expect(gh.istekler, isEmpty);
      await g.denetimYaz(true);
      expect(await g.otomatikAdim(), isTrue);
      expect(gh.istekler, isNotEmpty);
      expect(await g.otomatikAdim(), isFalse, reason: 'günde en çok bir kez');
    });

    test('limit (403) hata kodu olarak saklanır, istisna atmaz', () async {
      await kur(zipUret());
      gh.durum = 403;
      await g.denetle();
      expect(g.hataKodu, 'limit');
      expect(g.teklif, isNull);
    });

    test('indir ve doğrula: zip açılır, hazırlık yeni/ altında', () async {
      await kur(zipUret());
      final y = await yeni();
      final alinan = <int>[];
      await g.hazirla(y, ilerleme: alinan.add);
      expect(alinan, isNotEmpty);
      for (final z in paketZorunluDosyalar) {
        expect(
          File(p.join(g.yeniPaket.path, z)).existsSync(),
          isTrue,
          reason: z,
        );
      }
      expect(Directory(p.join(g.klasor.path, 'indirme')).existsSync(), isFalse);
    });

    test('yanlış SHA-256 reddedilir, hiçbir dosya kalmaz', () async {
      await kur(zipUret());
      final y = await yeni();
      gh.yanlisOzet = '0' * 64;
      await expectLater(g.hazirla(y), _kod('ozet_uyusmuyor'));
      expect(g.klasor.existsSync(), isFalse);
    });

    test('SHA256SUMS içinde geçerli satır yoksa ozet_bulunamadi', () async {
      await kur(zipUret());
      final y = await yeni();
      gh.yanlisOzet = 'zz';
      await expectLater(g.hazirla(y), _kod('ozet_bulunamadi'));
    });

    test(
      'sunucu beyan ettiğinden fazla gönderirse boyut_uyusmuyor, kısmi dosya silinir',
      () async {
        final zip = zipUret();
        await kur(zip);
        gh.zipGovdesi = [...zip, ...List.filled(500, 7)];
        final y = await yeni();
        await expectLater(g.hazirla(y), _kod('boyut_uyusmuyor'));
        expect(g.klasor.existsSync(), isFalse);
      },
    );

    test('sunucu eksik gönderirse boyut_uyusmuyor', () async {
      final zip = zipUret();
      await kur(zip);
      gh.zipGovdesi = zip.sublist(0, zip.length - 10);
      final y = await yeni();
      await expectLater(g.hazirla(y), _kod('boyut_uyusmuyor'));
    });

    test('izinsiz sunucuya yönlendirme adres_izinsiz ile durur', () async {
      await kur(zipUret());
      final y = await yeni();
      gh.yonlendir = 'https://evil.example/x.zip';
      await expectLater(g.hazirla(y), _kod('adres_izinsiz'));
    });

    test('iptal: indirme yarıda kesilir, dosyalar silinir', () async {
      await kur(
        zipUret(ek: {'buyuk.bin': List.generate(300000, (i) => i * 7 % 251)}),
      );
      gh.yavasla = const Duration(milliseconds: 300);
      final y = await yeni();
      final iptal = Iptal();
      await expectLater(
        g.hazirla(y, iptal: iptal, ilerleme: (_) => iptal.iptalEt()),
        _kod('iptal'),
      );
      expect(g.klasor.existsSync(), isFalse);
    });

    test('daha düşük/eşit sürüm kurulmaz (surum_dusuk)', () async {
      await kur(zipUret());
      final y = await yeni();
      final dusuk = Guncelleyici(
        ayarlar: g.ayarlar,
        klasor: g.klasor,
        surum: '9.9.9',
        ag: g.ag,
      );
      await expectLater(dusuk.hazirla(y), _kod('surum_dusuk'));
    });

    test('zip-slip içeren paket paket_bozuk, kök dışına yazılmaz', () async {
      await kur(
        zipUret(
          ek: {
            '../kacak.txt': [1, 2, 3],
          },
        ),
      );
      final y = await yeni();
      await expectLater(g.hazirla(y), _kod('paket_bozuk'));
      expect(File(p.join(tmp.path, 'kacak.txt')).existsSync(), isFalse);
      expect(File(p.join(g.klasor.path, 'kacak.txt')).existsSync(), isFalse);
      expect(g.klasor.existsSync(), isFalse);
    });

    test('zorunlu dosyası eksik paket paket_bozuk', () async {
      await kur(
        zipUret(
          zorunlu: false,
          ek: {
            'a.txt': [1],
          },
        ),
      );
      final y = await yeni();
      await expectLater(g.hazirla(y), _kod('paket_bozuk'));
    });
  });

  group('girdiAdiTemizle', () {
    test('güvenli adlar', () {
      expect(girdiAdiTemizle('data/app.so'), 'data/app.so');
      expect(
        girdiAdiTemizle(r'data\flutter_assets\x'),
        'data/flutter_assets/x',
      );
      expect(girdiAdiTemizle('data/'), 'data');
    });
    test('güvensiz adlar', () {
      for (final k in [
        '../x',
        '/x',
        r'C:\x',
        'a/../b',
        'a//b',
        'CON',
        'nul.txt',
        'a:b',
        'x.',
        'a/b ',
        '',
      ]) {
        expect(girdiAdiTemizle(k), isNull, reason: k);
      }
    });
  });
}
