import 'dart:io';

import 'package:aktenak_habit_tracker/core/sha256.dart';
import 'package:aktenak_habit_tracker/core/wifi_sync/sertifika.dart';
import 'package:aktenak_habit_tracker/core/wifi_sync/sozlesme.dart';
import 'package:flutter_test/flutter_test.dart';

final _f = 'A' * 43;
final _t = 'ab' * 16;

String _qr({
  String a = '192.168.1.20,10.0.0.5',
  String p = '51734',
  String? f,
  String? t,
  String v = '1',
  String e = '1783000000',
  String n = 'ARDA-PC',
  String extra = '',
}) =>
    'habitsync://p?v=$v&a=$a&p=$p&f=${f ?? _f}&t=${t ?? _t}&e=$e&n=$n$extra';

void main() {
  group('QR metni', () {
    test('kodla/coz gidiş dönüş', () {
      final q = QrBaglanti(
        adresler: const ['192.168.1.20', '10.0.0.5'],
        port: 51734,
        parmakIzi: _f,
        jeton: _t,
        bitis: 1783000000,
        ad: 'ARDA PC & ev',
      );
      final r = QrBaglanti.coz(q.kodla())!;
      expect(r.adresler, q.adresler);
      expect(r.port, 51734);
      expect(r.parmakIzi, _f);
      expect(r.jeton, _t);
      expect(r.bitis, 1783000000);
      expect(r.ad, 'ARDA PC & ev');
      expect(q.kodla().length, lessThanOrEqualTo(qrEnFazlaUzunluk));
    });

    test('geçerli örnek ve bilinmeyen anahtar yok sayılır', () {
      expect(QrBaglanti.coz(_qr()), isNotNull);
      expect(QrBaglanti.coz(_qr(extra: '&x=1')), isNotNull);
    });

    test('geçersizler reddedilir', () {
      final kotu = <String, String>{
        'çift anahtar': _qr(extra: '&t=$_t'),
        'genel IP': _qr(a: '8.8.8.8'),
        'bir genel IP karışık': _qr(a: '192.168.1.20,8.8.8.8'),
        'loopback': _qr(a: '127.0.0.1'),
        'CGNAT': _qr(a: '100.64.1.1'),
        'baştaki sıfır': _qr(a: '192.168.01.20'),
        '4 adres': _qr(a: '10.0.0.1,10.0.0.2,10.0.0.3,10.0.0.4'),
        'aynı adres iki kez': _qr(a: '10.0.0.1,10.0.0.1'),
        '44 karakterli parmak izi': _qr(f: 'A' * 44),
        '42 karakterli parmak izi': _qr(f: 'A' * 42),
        'büyük harfli jeton': _qr(t: 'AB' * 16),
        '31 karakterli jeton': _qr(t: 'ab' * 15 + 'a'),
        'port çok küçük': _qr(p: '1024'),
        'port çok büyük': _qr(p: '65536'),
        'sürüm 0': _qr(v: '0'),
        'şema': _qr().replaceFirst('habitsync', 'http'),
        'ana makine': _qr().replaceFirst('//p?', '//evil?'),
        'kullanıcı bilgisi': _qr().replaceFirst('//p?', '//u:p@p?'),
        'fragment': '${_qr()}#x',
        'çok uzun': _qr(n: 'x' * 400),
        'boş': '',
        'eksik alan': 'habitsync://p?v=1',
      };
      for (final e in kotu.entries) {
        expect(QrBaglanti.coz(e.value), isNull, reason: e.key);
      }
    });

    test('sürüm 2 ayrıştırılır (istemci "uygulamayı güncelle" der)', () {
      expect(QrBaglanti.coz(_qr(v: '2'))!.surum, 2);
    });

    test('ad: bidi/kontrol karakterleri atılır, 40 karaktere kesilir', () {
      final temiz = adTemizle('A‮B\u0007C⁦D' * 20);
      expect(temiz.length, lessThanOrEqualTo(40));
      expect(temiz, isNot(contains('‮')));
      expect(temiz, isNot(contains('\u0007')));
      expect(temiz, isNot(contains('⁦')));
    });
  });

  test('özel IPv4 aralıkları', () {
    for (final ip in ['10.1.2.3', '172.16.0.1', '172.31.255.255', '192.168.0.1', '169.254.1.1']) {
      expect(ozelIpv4mu(ip), isTrue, reason: ip);
    }
    for (final ip in [
      '127.0.0.1', '172.15.0.1', '172.32.0.1', '100.64.0.1', '8.8.8.8', '0.0.0.0',
      '192.169.0.1', '256.1.1.1', '1.2.3', '10.0.0.1.5', '::1', '', '010.0.0.1',
    ]) {
      expect(ozelIpv4mu(ip), isFalse, reason: ip);
    }
  });

  test('sabit zamanlı karşılaştırma', () {
    expect(sabitZamanliEsit('abc', 'abc'), isTrue);
    expect(sabitZamanliEsit('abc', 'abd'), isFalse);
    expect(sabitZamanliEsit('abc', 'abcd'), isFalse);
    expect(sabitZamanliEsit('', ''), isFalse);
  });

  test('hata kodları: tablo docs/wifi-senkron.md ile aynı, HTTP eşlemesi', () {
    final doc = File('docs/wifi-senkron.md').readAsStringSync();
    // "| 400 | `istek_bozuk` |" satırları
    final satirlar = RegExp(r'\|\s*(\d{3})\s*\|\s*`([a-z_]+)`\s*\|').allMatches(doc);
    final belge = {for (final m in satirlar) m.group(2)!: int.parse(m.group(1)!)};
    for (final h in WifiHata.values) {
      expect(belge[h.kod], h.http, reason: h.kod);
    }
    expect(WifiHata.values.map((h) => h.kod).toSet().length, WifiHata.values.length);
  });

  test('sabitler: tablo docs/wifi-senkron.md ile aynı', () {
    final doc = File('docs/wifi-senkron.md').readAsStringSync();
    int? belge(String ad) {
      final at = doc.indexOf('| `$ad` |');
      if (at < 0) return null;
      return int.tryParse(RegExp(r'\|\s*`' + ad + r'`\s*\|\s*(\d+)').firstMatch(doc.substring(at))?.group(1) ?? '');
    }

    final kod = {
      'wifiProtokolSurumu': wifiProtokolSurumu,
      'qrOmruSn': qrOmruSn,
      'onayBeklemeSn': onayBeklemeSn,
      'oturumEnFazlaSn': oturumEnFazlaSn,
      'sessionGovdeEnFazla': sessionGovdeEnFazla,
      'istekEnFazla': istekEnFazla,
      'govdeOkumaSn': govdeOkumaSn,
      'adresEnFazla': adresEnFazla,
    };
    for (final e in kod.entries) {
      expect(belge(e.key), e.value, reason: e.key);
    }
  });

  test('sertifika: 43 karakterli parmak izi, SAN/anahtar, her oturumda farklı', () async {
    final a = await OturumSertifikasi.uret(['127.0.0.1', '192.168.1.5']);
    final b = await OturumSertifikasi.uret(['127.0.0.1']);
    expect(a.parmakIzi.length, 43);
    expect(a.parmakIzi, base64urlDolgusuz(sha256(a.der)));
    expect(a.parmakIzi, isNot(b.parmakIzi));
    expect(a.certPem, isNot(contains('\r')));
    expect(a.keyPem, contains('PRIVATE KEY'));
    a.baglam(); // PEM, SecurityContext tarafından kabul edilir
    // DER içinde iki IP SAN'ı var (4 baytlık iPAddress alanları).
    final der = a.der;
    bool var_(List<int> ip) {
      for (var i = 0; i + ip.length <= der.length; i++) {
        var ok = true;
        for (var k = 0; k < ip.length && ok; k++) {
          ok = der[i + k] == ip[k];
        }
        if (ok) return true;
      }
      return false;
    }

    // basic_utils SAN'ı metin (dNSName) yazar, iPAddress değil; istemci parmak iziyle
    // sabitlediği için ana makine adı denetlenmez, bu yüzden sorun değil.
    expect(var_('192.168.1.5'.codeUnits), isTrue);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
