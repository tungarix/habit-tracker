import 'package:aktenak_habit_tracker/data/update/saf.dart';
import 'package:flutter_test/flutter_test.dart';

const _depo = guncellemeDeposu;
const _zip = 'aktenak-habit-tracker-v1.4.0-windows.zip';
const _ok = 'https://github.com/$_depo/releases/download/v1.4.0/$_zip';
const _sums =
    'https://github.com/$_depo/releases/download/v1.4.0/SHA256SUMS.txt';

Map<String, Object?> _yayin({
  String tag = 'v1.4.0',
  int boyut = 1000,
  String? url,
  bool draft = false,
}) => {
  'tag_name': tag,
  'draft': draft,
  'prerelease': false,
  'html_url': 'https://github.com/$_depo/releases/tag/$tag',
  'assets': [
    {'name': _zip, 'size': boyut, 'browser_download_url': url ?? _ok},
    {'name': 'SHA256SUMS.txt', 'size': 90, 'browser_download_url': _sums},
  ],
};

void main() {
  group('sürüm karşılaştırma', () {
    test('sayısal, kesin büyük', () {
      expect(dahaYeniMi('1.10.0', '1.9.0'), isTrue);
      expect(dahaYeniMi('v1.3.4', '1.3.3'), isTrue);
      expect(dahaYeniMi('1.3.3', '1.3.3'), isFalse);
      expect(dahaYeniMi('1.3.2', '1.3.3'), isFalse);
      expect(dahaYeniMi('2.0.0', '1.99.99'), isTrue);
    });
    test('çözülemeyen ve ön sürüm teklif değildir', () {
      expect(surumCoz('1.4.0-beta'), isNull);
      expect(surumCoz('1.4'), isNull);
      expect(surumCoz(null), isNull);
      expect(dahaYeniMi('abc', '1.0.0'), isFalse);
    });
  });

  group('adres izin listesi (host / port)', () {
    bool ok(String u, [Set<String> ek = const {}]) => adresUygun(u, _depo, ek);
    test('izinli sunucular', () {
      expect(ok(_ok), isTrue);
      expect(ok('https://api.github.com/repos/$_depo/releases/latest'), isTrue);
      expect(ok('https://objects.githubusercontent.com/x/y'), isTrue);
      expect(ok('https://release-assets.githubusercontent.com/x'), isTrue);
    });
    test(
      'başka host, başka depo, http, port, kullanıcı bilgisi reddedilir',
      () {
        expect(ok('https://evil.example/x'), isFalse);
        expect(
          ok('https://github.com.evil.example/$_depo/releases/x'),
          isFalse,
        );
        expect(
          ok('https://github.com/baska/depo/releases/download/v1/x'),
          isFalse,
        );
        expect(ok('http://github.com/$_depo/releases/x'), isFalse);
        expect(ok('https://github.com:8443/$_depo/releases/x'), isFalse);
        expect(ok('https://github.com:443/$_depo/releases/x'), isTrue);
        expect(ok('https://user@github.com/$_depo/releases/x'), isFalse);
        expect(ok('https://api.github.com:444/x'), isFalse);
      },
    );
    test('yol hileleri ve ASCII dışı reddedilir', () {
      expect(ok('https://github.com/$_depo/releases/../../x'), isFalse);
      expect(ok('https://objects.githubusercontent.com/%2e%2e/x'), isFalse);
      expect(ok('https://objects.githubusercontent.com/a\b'), isFalse);
      expect(ok('https://objects.githubusercontent.com/ç'), isFalse);
      expect(ok('https://objects.githubusercontent.com/a b'), isFalse);
      expect(
        ok(
          'https://objects.githubusercontent.com/x/y?X-Amz-Credential=a%2F2026%2Fs3',
        ),
        isTrue,
      );
    });
    test('ek sunucu yalnız açıkça verilirse kabul edilir', () {
      expect(ok('http://127.0.0.1:8123/x'), isFalse);
      expect(ok('http://127.0.0.1:8123/x', {'127.0.0.1'}), isTrue);
    });
  });

  group('yayinCoz', () {
    test('geçerli yayın', () {
      final y = yayinCoz(_yayin(), _depo)!;
      expect(y.surum, '1.4.0');
      expect(y.zipAdi, _zip);
      expect(y.zipBoyut, 1000);
    });
    test('taslak, ön sürüm, kötü etiket reddedilir', () {
      expect(yayinCoz(_yayin(draft: true), _depo), isNull);
      expect(yayinCoz(_yayin(tag: 'v1.4.0-rc1'), _depo), isNull);
      expect(yayinCoz('x', _depo), isNull);
    });
    test('boyut sınırı: sıfır ve fazla reddedilir', () {
      expect(yayinCoz(_yayin(boyut: 0), _depo), isNull);
      expect(yayinCoz(_yayin(boyut: zipEnFazlaBayt + 1), _depo), isNull);
      expect(yayinCoz(_yayin(boyut: zipEnFazlaBayt), _depo), isNotNull);
    });
    test('izinsiz adres ya da yanlış ad reddedilir', () {
      expect(
        yayinCoz(_yayin(url: 'https://evil.example/$_zip'), _depo),
        isNull,
      );
      final v = _yayin();
      (v['assets'] as List)[0] = {
        'name': 'baska.zip',
        'size': 5,
        'browser_download_url': _ok,
      };
      expect(yayinCoz(v, _depo), isNull);
    });
  });

  group('ozetCoz', () {
    final h = 'a' * 64;
    test('CRLF ve * ayracı kabul', () {
      expect(ozetCoz('$h  $_zip\r\n', _zip), h);
      expect(ozetCoz('${h.toUpperCase()} *$_zip\n', _zip), h);
    });
    test('yok, geçersiz ya da çift satır = null', () {
      expect(ozetCoz('$h  baska.zip\n', _zip), isNull);
      expect(ozetCoz('zz  $_zip\n', _zip), isNull);
      expect(ozetCoz('$h  $_zip\n${'b' * 64}  $_zip\n', _zip), isNull);
    });
  });
}
