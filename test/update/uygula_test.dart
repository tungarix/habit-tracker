import 'dart:convert';
import 'dart:io';

import 'package:aktenak_habit_tracker/data/database/database.dart';
import 'package:aktenak_habit_tracker/data/update/ag.dart';
import 'package:aktenak_habit_tracker/data/update/akis.dart';
import 'package:aktenak_habit_tracker/data/update/ayarlar.dart';
import 'package:aktenak_habit_tracker/data/update/guncelleyici.dart';
import 'package:aktenak_habit_tracker/data/update/uygula.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Uygulayıcı ve Kurucu: yalnız geçici klasörlerde ve sahte başlatıcılarla. Gerçek kurulum YOK.
void main() {
  late Directory tmp, kurulum, yeni;
  late File sonuc;
  final basladi = <String>[];

  void yaz(Directory d, String yol, String icerik) {
    final f = File(p.join(d.path, yol))..createSync(recursive: true);
    f.writeAsStringSync(icerik);
  }

  String oku(Directory d, String yol) =>
      File(p.join(d.path, yol)).readAsStringSync();

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('uygula_test');
    kurulum = Directory(p.join(tmp.path, 'kurulum'))..createSync();
    yeni = Directory(p.join(tmp.path, 'yeni'))..createSync();
    sonuc = File(p.join(tmp.path, 'veri', 'sonuc.json'));
    basladi.clear();
    // eski kurulum
    yaz(kurulum, uygulamaExe, 'eski-exe');
    yaz(kurulum, 'flutter_windows.dll', 'eski-dll');
    yaz(kurulum, 'data/app.so', 'eski-app');
    yaz(kurulum, 'data/eski_dosya.bin', 'eski-yalniz');
    yaz(kurulum, 'notlarim.txt', 'kullanici dosyasi'); // kümenin dışında
    // yeni paket
    yaz(yeni, uygulamaExe, 'yeni-exe');
    yaz(yeni, 'flutter_windows.dll', 'yeni-dll');
    yaz(yeni, 'data/app.so', 'yeni-app');
    yaz(yeni, 'data/icudtl.dat', 'yeni-icu');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<UygulaSonucu> calistir({
    Future<bool> Function(int) calisiyorMu = _bitti,
    Future<void> Function(FileSystemEntity, String)? kopyala,
    Duration bekleme = const Duration(milliseconds: 200),
  }) => uygula(
    yeni: yeni,
    hedef: kurulum,
    sonuc: sonuc,
    pid: 123,
    bekleme: bekleme,
    aralik: const Duration(milliseconds: 20),
    calisiyorMu: calisiyorMu,
    baslat: (exe, calisma) async => basladi.add(exe),
    kopyala: kopyala ?? _varsayilanKopya,
  );

  test(
    'başarı: küme değişir, eski .eski altında, dışarıdaki dosyaya dokunulmaz, yeni exe açılır',
    () async {
      final s = await calistir();
      expect(s.durum, 'tamam');
      expect(oku(kurulum, uygulamaExe), 'yeni-exe');
      expect(oku(kurulum, 'data/app.so'), 'yeni-app');
      expect(oku(kurulum, 'data/icudtl.dat'), 'yeni-icu');
      expect(
        File(p.join(kurulum.path, 'data/eski_dosya.bin')).existsSync(),
        isFalse,
      );
      expect(oku(kurulum, '.eski/$uygulamaExe'), 'eski-exe');
      expect(oku(kurulum, '.eski/data/eski_dosya.bin'), 'eski-yalniz');
      expect(oku(kurulum, 'notlarim.txt'), 'kullanici dosyasi');
      expect(basladi, [p.join(kurulum.path, uygulamaExe)]);
      expect(jsonDecode(sonuc.readAsStringSync())['durum'], 'tamam');
    },
  );

  test(
    'kopyalama hatası: tam geri alma, eski exe yeniden açılır, sonuç geri_alindi',
    () async {
      var n = 0;
      final s = await calistir(
        kopyala: (e, h) async {
          if (++n == 2) throw const FileSystemException('disk');
          await _varsayilanKopya(e, h);
        },
      );
      expect(s.durum, 'geri_alindi');
      expect(s.kod, 'uygulama_basarisiz');
      expect(oku(kurulum, uygulamaExe), 'eski-exe');
      expect(oku(kurulum, 'flutter_windows.dll'), 'eski-dll');
      expect(oku(kurulum, 'data/app.so'), 'eski-app');
      expect(oku(kurulum, 'data/eski_dosya.bin'), 'eski-yalniz');
      expect(
        File(p.join(kurulum.path, 'data/icudtl.dat')).existsSync(),
        isFalse,
        reason: 'yarım yeni dosya kalmamalı',
      );
      expect(oku(kurulum, 'notlarim.txt'), 'kullanici dosyasi');
      expect(basladi, [p.join(kurulum.path, uygulamaExe)]);
      expect(oku(kurulum, uygulamaExe), 'eski-exe');
    },
  );

  test(
    'eski süreç kapanmazsa uygulama_mesgul, hiçbir dosya değişmez',
    () async {
      final s = await calistir(calisiyorMu: (_) async => true);
      expect(s.durum, 'uygulama_mesgul');
      expect(oku(kurulum, uygulamaExe), 'eski-exe');
      expect(oku(kurulum, 'data/app.so'), 'eski-app');
      expect(Directory(p.join(kurulum.path, '.eski')).existsSync(), isFalse);
    },
  );

  test('paketi exe içermiyorsa dokunmadan geri alındı', () async {
    File(p.join(yeni.path, uygulamaExe)).deleteSync();
    final s = await calistir();
    expect(s.durum, 'geri_alindi');
    expect(oku(kurulum, uygulamaExe), 'eski-exe');
  });

  group('argüman doğrulama', () {
    late Directory veri;
    setUp(() => veri = Directory(p.join(tmp.path, 'veri'))..createSync());
    List<String> a({
      String? hedef,
      String? sonucYolu,
      String pid = '42',
      bool bayrak = true,
    }) => [
      if (bayrak) guncelleBayragi,
      '--hedef',
      hedef ?? kurulum.path,
      '--sonuc',
      sonucYolu ?? p.join(veri.path, 's.json'),
      '--pid',
      pid,
    ];
    test('geçerli', () {
      final c = UygulaArgumanlari.coz(a(), veri)!;
      expect(c.pid, 42);
      expect(c.hedef.path, p.normalize(kurulum.path));
    });
    test(
      'bayrak yok / göreli yol / exe yok / sonuç veri dışında / kötü pid reddedilir',
      () {
        expect(UygulaArgumanlari.coz(a(bayrak: false), veri), isNull);
        expect(UygulaArgumanlari.coz(a(hedef: 'goreli/yol'), veri), isNull);
        expect(UygulaArgumanlari.coz(a(hedef: tmp.path), veri), isNull);
        expect(
          UygulaArgumanlari.coz(
            a(sonucYolu: p.join(tmp.path, 'baska.json')),
            veri,
          ),
          isNull,
        );
        expect(
          UygulaArgumanlari.coz(
            a(sonucYolu: p.join(veri.path, '..', 'baska.json')),
            veri,
          ),
          isNull,
        );
        expect(UygulaArgumanlari.coz(a(pid: 'x'), veri), isNull);
        expect(UygulaArgumanlari.coz(a(pid: '0'), veri), isNull);
      },
    );
  });

  test('sonucuOkuVeTemizle: mesaj verir, .eski ve hazırlığı siler', () async {
    await calistir();
    final hazirlik = Directory(p.join(tmp.path, 'hazirlik'))..createSync();
    final m = await sonucuOkuVeTemizle(
      sonuc: sonuc,
      kurulum: kurulum,
      hazirlik: hazirlik,
      surum: '1.4.0',
    );
    expect(m, '1.4.0 sürümüne güncellendi.');
    expect(sonuc.existsSync(), isFalse);
    expect(Directory(p.join(kurulum.path, '.eski')).existsSync(), isFalse);
    expect(hazirlik.existsSync(), isFalse);
    expect(
      await sonucuOkuVeTemizle(
        sonuc: sonuc,
        kurulum: kurulum,
        hazirlik: hazirlik,
        surum: '1.4.0',
      ),
      isNull,
    );
  });

  group('Kurucu (sahte)', () {
    late Guncelleyici g;
    final olaylar = <String>[];
    late AppDatabase db;
    setUp(() async {
      olaylar.clear();
      db = AppDatabase.forTesting(NativeDatabase.memory());
      g = Guncelleyici(
        ayarlar: await GuncellemeAyarlari.yukle(db),
        klasor: Directory(p.join(tmp.path, 'hazirlik')),
        surum: '1.0.0',
      );
      yaz(g.yeniPaket, uygulamaExe, 'x');
    });
    tearDown(() => db.close());
    Kurucu kurucu({bool yedekHata = false}) => Kurucu(
      kurulumKlasoru: kurulum,
      sonucDosyasi: sonuc,
      surecNo: 77,
      yedekAl: () async {
        olaylar.add('yedek');
        if (yedekHata) throw StateError('yok');
      },
      uygulayiciyiBaslat: (exe, args) async =>
          olaylar.add('baslat ${p.basename(exe)} ${args.join(' ')}'),
      kapat: () async => olaylar.add('kapat'),
    );

    test('sıra: yedek, uygulayıcı, kapat; argümanlar doğru', () async {
      await kurucu().kur(g);
      expect(olaylar, [
        'yedek',
        'baslat $uygulamaExe $guncelleBayragi --hedef ${kurulum.path} --sonuc ${sonuc.path} --pid 77',
        'kapat',
      ]);
    });

    test('yedek başarısızsa kurulum başlamaz ve uygulama kapanmaz', () async {
      await expectLater(
        kurucu(yedekHata: true).kur(g),
        throwsA(isA<GuncellemeHatasi>()),
      );
      expect(olaylar, ['yedek']);
    });

    test('hazır paket yoksa hiçbir şey yapılmaz', () async {
      File(p.join(g.yeniPaket.path, uygulamaExe)).deleteSync();
      await expectLater(kurucu().kur(g), throwsA(isA<GuncellemeHatasi>()));
      expect(olaylar, isEmpty);
    });

    test('önkoşul: yazılamayan klasör klasor_yazilamaz', () async {
      final yok = Kurucu(
        kurulumKlasoru: Directory(p.join(tmp.path, 'olmayan', 'klasor')),
        sonucDosyasi: sonuc,
        yedekAl: () async {},
        uygulayiciyiBaslat: (_, _) async {},
        kapat: () async {},
      );
      await expectLater(
        yok.onKosul(),
        throwsA(
          isA<GuncellemeHatasi>().having(
            (e) => e.kod,
            'kod',
            'klasor_yazilamaz',
          ),
        ),
      );
      await kurucu().onKosul();
    });
  });
}

Future<bool> _bitti(int _) async => false;

Future<void> _varsayilanKopya(FileSystemEntity e, String h) async {
  if (e is File) {
    await e.copy(h);
  } else if (e is Directory) {
    await Directory(h).create(recursive: true);
    await for (final c in e.list()) {
      await _varsayilanKopya(c, p.join(h, p.basename(c.path)));
    }
  }
}
