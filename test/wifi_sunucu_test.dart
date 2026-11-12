import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aktenak_habit_tracker/core/sha256.dart';
import 'package:aktenak_habit_tracker/core/wifi_sync/sertifika.dart';
import 'package:aktenak_habit_tracker/core/wifi_sync/sozlesme.dart';
import 'package:aktenak_habit_tracker/core/wifi_sync/sunucu.dart';
import 'package:aktenak_habit_tracker/data/sync/sync_export.dart';
import 'package:aktenak_habit_tracker/data/sync/sync_format.dart';
import 'package:aktenak_habit_tracker/data/sync/sync_import.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sync_harness.dart';
import 'wifi_test_yardimci.dart';

class Kur {
  Kur(this.dev, this.sunucu, this.q);
  final Dev dev;
  final EslestirmeSunucusu sunucu;
  final QrBaglanti q;
  int yedekSayisi = 0;
  StreamSubscription<EslestirmeDurum>? _abone;

  /// Onay 2 / Onay 4'ü otomatik verir (null: elle).
  void otomatik({bool? o2, bool? o4}) {
    _abone = sunucu.durumlar.listen((d) {
      if (d == EslestirmeDurum.baglantiOnayi && o2 != null) sunucu.baglantiyiOnayla(o2);
      if (d == EslestirmeDurum.birlesmeOnayi && o4 != null) sunucu.birlesmeyiOnayla(o4);
    });
  }

  Future<String> oturumAc() async {
    final r = await istek(q, 'POST', '/v1/session', bearer: q.jeton, govde: oturumGovdesi);
    expect(r.kod, 200, reason: r.govde);
    return r.json['session'] as String;
  }

  Future<void> bitir() async {
    await _abone?.cancel();
    await sunucu.kapat();
    await dev.close();
  }
}

Future<Kur> kur({
  EslestirmeAyar? ayar,
  Future<SyncReport> Function(Uint8List)? uygula,
  Future<void> Function()? yedek,
  Future<SyncReport> Function(Uint8List)? onizle,
}) async {
  final dev = Dev('pc');
  await dev.habit('Yürüyüş', stamp: 1);
  late Kur k;
  final s = EslestirmeSunucusu(
    durumAl: () async => Uint8List.fromList(utf8.encode(await exportSync(dev.db, deviceName: 'pc'))),
    onizle: onizle ?? (b) => previewSyncBytes(dev.db, b),
    uygula: uygula ?? (b) => importSyncBytes(dev.db, b),
    yedekAl: () async {
      k.yedekSayisi++;
      await yedek?.call();
    },
    sunucuAdi: 'ARDA-PC',
    adresler: const ['127.0.0.1'],
    sertifika: testCert,
    ayar: ayar ?? const EslestirmeAyar(loopbackIzinli: true),
  );
  final q = await s.baslat();
  k = Kur(dev, s, q);
  return k;
}

const hizli = EslestirmeAyar(
  loopbackIzinli: true,
  onayBekleme: Duration(milliseconds: 400),
  govdeOkuma: Duration(milliseconds: 400),
);

void main() {
  setUpAll(() async => testCert = await OturumSertifikasi.uret(['127.0.0.1']));

  test('tam akış: oturum, durum al, gönder, onay, birleştir; sunucu kapanır', () async {
    final k = await kur();
    addTearDown(k.bitir);
    k.otomatik(o2: true, o4: true);
    final tel = await telefonDosyasi();

    final key = await k.oturumAc();
    expect(k.sunucu.istemci!.ad, 'Pixel 7');

    final st = await istek(k.q, 'GET', '/v1/state', bearer: key);
    expect(st.kod, 200);
    expect(st.json['format'], 'habit-sync');
    expect((st.json['habits'] as List).single['name'], 'Yürüyüş');

    final post = await istek(k.q, 'POST', '/v1/state', bearer: key, govde: tel);
    expect(post.kod, 200, reason: post.govde);
    expect(post.json['result'], 'merged');
    expect(post.json['report']['habit']['added'], 1);
    expect(await k.sunucu.bitti, EslestirmeDurum.tamam);
    expect(k.yedekSayisi, 1);
    expect((await k.dev.db.getAllHabits()).map((h) => h.name), containsAll(['Yürüyüş', 'Kitap']));
    expect(k.sunucu.ozet!.habit.added, 1); // Onay 4 özeti = gerçek sonuç

    // Çıktıda sır yok: yanıtlar ve olay listesi.
    // (oturum yanıtı anahtarı telefona vermek için taşır; durum dosyası kullanıcının verisidir)
    final cikti = tumYanitlar.where((t) => !t.contains('"session"') && !t.contains('"habits"')).join() +
        k.sunucu.olaylar.join();
    for (final sir in [k.q.jeton, key, k.q.parmakIzi, 'Kitap']) {
      expect(cikti, isNot(contains(sir)), reason: 'sızıntı: $sir');
    }
    // Sunucu gerçekten kapandı.
    await Future<void>.delayed(const Duration(milliseconds: 2300));
    await expectLater(istek(k.q, 'GET', '/v1/state', bearer: key), throwsA(isA<Exception>()));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('jeton tek kullanımlık; yanlış/eksik jeton 401 yalnız {"error"}', () async {
    final k = await kur();
    addTearDown(k.bitir);
    k.otomatik(o2: true);
    for (final b in [null, 'yanlis', 'ab' * 16]) {
      final r = await istek(k.q, 'POST', '/v1/session', bearer: b, govde: oturumGovdesi);
      expect(r.kod, 401);
      expect(r.json, {'error': 'yetkisiz'});
    }
    await k.oturumAc();
    final tekrar = await istek(k.q, 'POST', '/v1/session', bearer: k.q.jeton, govde: oturumGovdesi);
    expect(tekrar.kod, 401);
    // Jeton oturum anahtarı gibi de kullanılamaz.
    expect((await istek(k.q, 'GET', '/v1/state', bearer: k.q.jeton)).kod, 401);
  });

  test('bilinmeyen yol da kimlik yoksa 401, kimlik varsa 404/405', () async {
    final k = await kur();
    addTearDown(k.bitir);
    expect((await istek(k.q, 'GET', '/v1/yok')).kod, 401);
    expect((await istek(k.q, 'GET', '/v1/yok', bearer: k.q.jeton)).hata, 'yok');
    expect((await istek(k.q, 'GET', '/v1/session', bearer: k.q.jeton)).hata, 'metot');
    // Jeton ile oturum gerektiren uç: sıra hatalı.
    expect((await istek(k.q, 'GET', '/v1/state', bearer: k.q.jeton)).hata, 'sira_hatali');
  });

  test('beş hatadan sonra o IP yanıtsız kapatılır, oturum sürer', () async {
    final k = await kur();
    addTearDown(k.bitir);
    for (var i = 0; i < ipBasinaHata; i++) {
      expect((await istek(k.q, 'GET', '/v1/state', bearer: 'x$i')).kod, 401);
    }
    await expectLater(
        istek(k.q, 'POST', '/v1/session', bearer: k.q.jeton, govde: oturumGovdesi),
        throwsA(isA<Exception>()));
    expect(k.sunucu.durum, EslestirmeDurum.bekliyor);
  });

  test('yanlış parmak izi el sıkışmada reddedilir, sunucu hiçbir istek görmez', () async {
    final k = await kur();
    addTearDown(k.bitir);
    final yanlis = base64urlDolgusuz(sha256([1, 2, 3]));
    await expectLater(
        istek(k.q, 'POST', '/v1/session', bearer: k.q.jeton, govde: oturumGovdesi, pin: yanlis),
        throwsA(isA<HandshakeException>()));
    expect(k.sunucu.olaylar.where((e) => e.contains('Bağlantı geldi')), isEmpty);
    expect(k.sunucu.durum, EslestirmeDurum.bekliyor);
  });

  test('QR süresi dolunca oturum kapanır (jeton ölür)', () async {
    final k = await kur(
        ayar: const EslestirmeAyar(loopbackIzinli: true, qrOmru: Duration(milliseconds: 200)));
    addTearDown(k.bitir);
    expect(await k.sunucu.bitti, EslestirmeDurum.sureDoldu);
    final r = istek(k.q, 'POST', '/v1/session', bearer: k.q.jeton, govde: oturumGovdesi);
    // Kapanma penceresinde 401, sonra bağlantı reddi; ikisi de "kabul edilmedi".
    try {
      expect((await r).kod, 401);
    } on Exception {
      // bağlantı reddi
    }
  });

  test('oturum üst süresi sonunda kapanır', () async {
    final k = await kur(
        ayar: const EslestirmeAyar(loopbackIzinli: true, oturumEnFazla: Duration(milliseconds: 300)));
    addTearDown(k.bitir);
    expect(await k.sunucu.bitti, EslestirmeDurum.sureDoldu);
  });

  group('boyut ve biçim sınırları', () {
    test('411: Content-Length yok', () async {
      final k = await kur();
      addTearDown(k.bitir);
      final out = await ham(
          k.q,
          'POST /v1/session HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer ${k.q.jeton}\r\n'
          'Content-Type: application/json\r\nConnection: close\r\n\r\n');
      expect(out, startsWith('HTTP/1.1 411'));
      expect(out, contains('"uzunluk_gerekli"'));
    });

    test('413: bildirilen gövde sınırı aşar, gövde okunmadan', () async {
      final k = await kur();
      addTearDown(k.bitir);
      final out = await ham(
          k.q,
          'POST /v1/session HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer ${k.q.jeton}\r\n'
          'Content-Type: application/json\r\nContent-Length: ${sessionGovdeEnFazla + 1}\r\n'
          'Connection: close\r\n\r\n');
      expect(out, startsWith('HTTP/1.1 413'));
      expect(out, contains('"cok_buyuk"'));
      expect(k.sunucu.durum, EslestirmeDurum.bekliyor); // jeton yanmadı
    });

    test('413: /v1/state için 16 MiB + 1', () async {
      final k = await kur();
      addTearDown(k.bitir);
      k.otomatik(o2: true);
      final key = await k.oturumAc();
      final out = await ham(
          k.q,
          'POST /v1/state HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer $key\r\n'
          'Content-Type: application/json\r\nContent-Length: ${syncMaxFileBytes + 1}\r\n'
          'Connection: close\r\n\r\n');
      expect(out, startsWith('HTTP/1.1 413'));
      expect(k.sunucu.durum, EslestirmeDurum.hazir);
    });

    test('415: JSON olmayan içerik türü', () async {
      final k = await kur();
      addTearDown(k.bitir);
      final r = await istek(k.q, 'POST', '/v1/session',
          bearer: k.q.jeton, govde: '{}', tip: 'text/plain');
      expect(r.kod, 415);
    });

    test('408: gövde süresinde gelmezse', () async {
      final k = await kur(ayar: hizli);
      addTearDown(k.bitir);
      final out = await ham(
          k.q,
          'POST /v1/session HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer ${k.q.jeton}\r\n'
          'Content-Type: application/json\r\nContent-Length: 100\r\nConnection: close\r\n\r\n{"a":',
          bekle: const Duration(milliseconds: 100));
      expect(out, startsWith('HTTP/1.1 408'));
    });

    test('bozuk oturum gövdesi: istek_bozuk, jeton yanar, oturum biter', () async {
      final k = await kur();
      addTearDown(k.bitir);
      final r = await istek(k.q, 'POST', '/v1/session', bearer: k.q.jeton, govde: '{degil json');
      expect(r.hata, 'istek_bozuk');
      expect(await k.sunucu.bitti, EslestirmeDurum.hata);
    });

    test('protokol sürümü uyuşmazlığı', () async {
      final k = await kur();
      addTearDown(k.bitir);
      final g = {...oturumGovdesi, 'protocol': 2};
      final r = await istek(k.q, 'POST', '/v1/session', bearer: k.q.jeton, govde: g);
      expect(r.hata, 'protokol_surumu');
    });
  });

  group('onaylar', () {
    test('Onay 2 reddi: 403, telefona veri verilmez', () async {
      final k = await kur();
      addTearDown(k.bitir);
      k.otomatik(o2: false);
      final r = await istek(k.q, 'POST', '/v1/session', bearer: k.q.jeton, govde: oturumGovdesi);
      expect(r.kod, 403);
      expect(r.hata, 'reddedildi');
      expect(await k.sunucu.bitti, EslestirmeDurum.reddedildi);
    });

    test('Onay 2 zaman aşımı: 408', () async {
      final k = await kur(ayar: hizli);
      addTearDown(k.bitir);
      final r = await istek(k.q, 'POST', '/v1/session', bearer: k.q.jeton, govde: oturumGovdesi);
      expect(r.kod, 408);
      expect(await k.sunucu.bitti, EslestirmeDurum.sureDoldu);
    });

    test('Onay 2 beklerken masaüstü İptal: bekleyen istek 409 iptal', () async {
      final k = await kur();
      addTearDown(k.bitir);
      final f = istek(k.q, 'POST', '/v1/session', bearer: k.q.jeton, govde: oturumGovdesi);
      await k.sunucu.durumlar.firstWhere((d) => d == EslestirmeDurum.baglantiOnayi);
      k.sunucu.iptalEt();
      final r = await f;
      expect(r.kod, 409);
      expect(r.hata, 'iptal');
      expect(await k.sunucu.bitti, EslestirmeDurum.iptal);
    });

    test('Onay 4 reddi: 403 ve masaüstü verisi değişmez', () async {
      final k = await kur();
      addTearDown(k.bitir);
      k.otomatik(o2: true, o4: false);
      final key = await k.oturumAc();
      final once = await k.dev.state();
      final r = await istek(k.q, 'POST', '/v1/state', bearer: key, govde: await telefonDosyasi());
      expect(r.hata, 'reddedildi');
      expect(await k.dev.state(), once);
      expect(k.yedekSayisi, 0);
      expect(await k.sunucu.bitti, EslestirmeDurum.reddedildi);
    });

    test('Onay 4 zaman aşımı: 408, veri değişmez', () async {
      final k = await kur(ayar: hizli);
      addTearDown(k.bitir);
      k.otomatik(o2: true);
      final key = await k.oturumAc();
      final once = await k.dev.state();
      final r = await istek(k.q, 'POST', '/v1/state', bearer: key, govde: await telefonDosyasi());
      expect(r.kod, 408);
      expect(await k.dev.state(), once);
    });

    test('Onay 4 beklerken ikinci POST: 409 mesgul', () async {
      final k = await kur();
      addTearDown(k.bitir);
      k.otomatik(o2: true);
      final key = await k.oturumAc();
      final tel = await telefonDosyasi();
      final ilk = istek(k.q, 'POST', '/v1/state', bearer: key, govde: tel);
      await k.sunucu.durumlar.firstWhere((d) => d == EslestirmeDurum.birlesmeOnayi);
      final ikinci = await istek(k.q, 'POST', '/v1/state', bearer: key, govde: tel);
      expect(ikinci.hata, 'mesgul');
      k.sunucu.birlesmeyiOnayla(true);
      expect((await ilk).kod, 200);
    });
  });

  test('bozuk telefon dosyası: senkron_bozuk, oturum açık kalır, sonra geçerli dosya gider', () async {
    final k = await kur();
    addTearDown(k.bitir);
    k.otomatik(o2: true, o4: true);
    final key = await k.oturumAc();
    final once = await k.dev.state();
    final r = await istek(k.q, 'POST', '/v1/state', bearer: key, govde: '{"format":"yanlis"}');
    expect(r.kod, 400);
    expect(r.hata, 'senkron_bozuk');
    expect(await k.dev.state(), once);
    expect(k.sunucu.durum, EslestirmeDurum.hazir);
    final iyi = await istek(k.q, 'POST', '/v1/state', bearer: key, govde: await telefonDosyasi());
    expect(iyi.kod, 200);
  });

  test('önizleme beklenmedik hata verirse ic_hata, telefon yeniden deneyebilir', () async {
    var cagri = 0;
    late Kur k;
    k = await kur(
      onizle: (b) => ++cagri == 1 ? throw StateError('db') : previewSyncBytes(k.dev.db, b),
    );
    addTearDown(k.bitir);
    k.otomatik(o2: true, o4: true);
    final key = await k.oturumAc();
    final govde = await telefonDosyasi();
    final r = await istek(k.q, 'POST', '/v1/state', bearer: key, govde: govde);
    expect(r.kod, 500);
    expect(r.hata, 'ic_hata');
    expect(k.sunucu.durum, EslestirmeDurum.hazir);
    final tekrar = await istek(k.q, 'POST', '/v1/state', bearer: key, govde: govde);
    expect(tekrar.kod, 200, reason: tekrar.govde);
  });

  test('daha yeni senkron sürümü: senkron_surumu', () async {
    final k = await kur();
    addTearDown(k.bitir);
    k.otomatik(o2: true);
    final key = await k.oturumAc();
    final doc = jsonDecode(utf8.decode(await telefonDosyasi())) as Map<String, dynamic>;
    doc['version'] = syncVersion + 1;
    final r = await istek(k.q, 'POST', '/v1/state', bearer: key, govde: doc);
    expect(r.hata, 'senkron_surumu');
  });

  test('yedek alınamazsa birleştirme yapılmaz (ic_hata)', () async {
    final k = await kur(yedek: () async => throw const FileSystemException('disk dolu'));
    addTearDown(k.bitir);
    k.otomatik(o2: true, o4: true);
    final key = await k.oturumAc();
    final once = await k.dev.state();
    final r = await istek(k.q, 'POST', '/v1/state', bearer: key, govde: await telefonDosyasi());
    expect(r.hata, 'ic_hata');
    expect(await k.dev.state(), once);
    expect(await k.sunucu.bitti, EslestirmeDurum.hata);
  });

  test('birleştirme sürerken İptal yok sayılır, veri birleşir', () async {
    final tut = Completer<void>();
    late Kur k;
    k = await kur(uygula: (b) async {
      await tut.future;
      return importSyncBytes(k.dev.db, b);
    });
    addTearDown(k.bitir);
    k.otomatik(o2: true, o4: true);
    final key = await k.oturumAc();
    final f = istek(k.q, 'POST', '/v1/state', bearer: key, govde: await telefonDosyasi());
    await k.sunucu.durumlar.firstWhere((d) => d == EslestirmeDurum.isleniyor);
    k.sunucu.iptalEt();
    expect(k.sunucu.durum, EslestirmeDurum.isleniyor);
    tut.complete();
    expect((await f).kod, 200);
    expect(await k.sunucu.bitti, EslestirmeDurum.tamam);
    expect((await k.dev.db.getAllHabits()).length, 2);
  });

  test('POST /v1/end: telefon vazgeçince oturum kapanır', () async {
    final k = await kur();
    addTearDown(k.bitir);
    k.otomatik(o2: true);
    final key = await k.oturumAc();
    final r = await istek(k.q, 'POST', '/v1/end', bearer: key, govde: {'reason': 'cancel'});
    expect(r.kod, 200);
    expect(await k.sunucu.bitti, EslestirmeDurum.iptal);
  });

  test('oturum anahtarı oturumu açan IP\'ye bağlı; GET /v1/state en çok iki kez', () async {
    final k = await kur();
    addTearDown(k.bitir);
    k.otomatik(o2: true);
    final key = await k.oturumAc();
    expect((await istek(k.q, 'GET', '/v1/state', bearer: key)).kod, 200);
    expect((await istek(k.q, 'GET', '/v1/state', bearer: key)).kod, 200);
    expect((await istek(k.q, 'GET', '/v1/state', bearer: key)).hata, 'sira_hatali');
  });

  test('kapat() sunucuyu hemen kapatır (uygulama kapanırken)', () async {
    final k = await kur();
    addTearDown(k.bitir);
    await k.sunucu.kapat();
    expect(k.sunucu.durum, EslestirmeDurum.iptal);
    await expectLater(
        istek(k.q, 'POST', '/v1/session', bearer: k.q.jeton, govde: oturumGovdesi),
        throwsA(isA<Exception>()));
  });

  test('üretim ayarı loopback bağlantısını kabul etmez', () async {
    final k = await kur(ayar: const EslestirmeAyar());
    addTearDown(k.bitir);
    await expectLater(
        istek(k.q, 'POST', '/v1/session', bearer: k.q.jeton, govde: oturumGovdesi),
        throwsA(isA<Exception>()));
    expect(k.sunucu.durum, EslestirmeDurum.bekliyor);
  });

  test('yinelenen Authorization başlığı kimliksiz sayılır: IP hata sınırı işler, oturum ölmez', () async {
    final k = await kur();
    addTearDown(k.bitir);
    const cift = 'GET /v1/state HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer a\r\n'
        'Authorization: Bearer b\r\nConnection: close\r\n\r\n';
    for (var i = 0; i < ipBasinaHata; i++) {
      expect(await ham(k.q, cift), startsWith('HTTP/1.1 401'), reason: 'istek $i');
    }
    expect(await ham(k.q, cift), isEmpty, reason: 'beşten sonra yanıtsız kesilir');
    expect(k.sunucu.durum, EslestirmeDurum.bekliyor);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('sızan jeton yarışı: yarım gövdeli eski istek, jeton başkasına yandıktan sonra oturumu ezemez', () async {
    final k = await kur();
    addTearDown(k.bitir);
    k.otomatik(o2: true);
    final govde = jsonEncode({
      ...oturumGovdesi,
      'client': {'name': 'Saldirgan', 'app': 'habit-tracker-mobile', 'version': '0.3.0'},
    });
    final s = await SecureSocket.connect('127.0.0.1', k.q.port,
        onBadCertificate: (c) => base64urlDolgusuz(sha256(c.der)) == k.q.parmakIzi);
    final tampon = <int>[];
    s.listen(tampon.addAll, onError: (_) {});
    s.write('POST /v1/session HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer ${k.q.jeton}\r\n'
        'Content-Type: application/json\r\nContent-Length: ${utf8.encode(govde).length}\r\n'
        'Connection: close\r\n\r\n${govde.substring(0, 5)}');
    await s.flush();
    await Future<void>.delayed(const Duration(milliseconds: 150));

    final key = await k.oturumAc(); // meşru telefon jetonu yakar
    expect(k.sunucu.durum, EslestirmeDurum.hazir);

    s.write(govde.substring(5)); // saldırgan gövdeyi şimdi tamamlar
    await s.flush();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    s.destroy();
    expect(utf8.decode(tampon, allowMalformed: true), startsWith('HTTP/1.1 401'));
    expect(k.sunucu.istemci!.ad, 'Pixel 7');
    expect(k.sunucu.durum, EslestirmeDurum.hazir);
    expect((await istek(k.q, 'GET', '/v1/state', bearer: key)).kod, 200, reason: 'meşru anahtar geçerli kalır');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('birleştirme sürerken genel süre dolsa da oturum sureDoldu olmaz, sonuç tamam', () async {
    final tut = Completer<void>();
    late Kur k;
    k = await kur(
      ayar: const EslestirmeAyar(
        loopbackIzinli: true,
        oturumEnFazla: Duration(milliseconds: 1500),
      ),
      uygula: (b) async {
        await tut.future;
        return importSyncBytes(k.dev.db, b);
      },
    );
    addTearDown(k.bitir);
    k.otomatik(o2: true, o4: true);
    final key = await k.oturumAc();
    final f = istek(k.q, 'POST', '/v1/state', bearer: key, govde: await telefonDosyasi());
    await k.sunucu.durumlar.firstWhere((d) => d == EslestirmeDurum.isleniyor);
    await Future<void>.delayed(const Duration(milliseconds: 2200)); // genel süre doldu
    expect(k.sunucu.durum, EslestirmeDurum.isleniyor);
    tut.complete();
    expect((await f).kod, 200);
    expect(await k.sunucu.bitti, EslestirmeDurum.tamam);
    expect((await k.dev.db.getAllHabits()).length, 2);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('sunucu portu telefonun kabul ettiği aralıkta seçilir', () async {
    for (var i = 0; i < 8; i++) {
      final k = await kur();
      addTearDown(k.bitir);
      expect(k.q.port, inInclusiveRange(portEnAz, portEnCok));
    }
  });

  test('adres yoksa başlamaz', () async {
    final s = EslestirmeSunucusu(
      durumAl: () async => Uint8List(0),
      onizle: (_) async => SyncReport(),
      uygula: (_) async => SyncReport(),
      yedekAl: () async {},
      adresler: const [],
    );
    await expectLater(s.baslat(), throwsStateError);
    await s.kapat();
  });
}
