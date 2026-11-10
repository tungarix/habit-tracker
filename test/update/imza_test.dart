import 'dart:convert';

import 'package:aktenak_habit_tracker/data/update/imza.dart';
import 'package:aktenak_habit_tracker/data/update/saf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart';

void main() {
  // TEST anahtarı: gerçek yayın anahtarı bu testlerde hiç kullanılmaz.
  final anahtar = SigningKey.generate();
  final acik = anahtar.verifyKey.asTypedList;
  final mesaj = utf8.encode('${'ab' * 32}  dosya.zip\n');
  List<int> imzala(List<int> m) =>
      anahtar.sign(Uint8List.fromList(m)).signature.asTypedList;

  test('gömülü açık anahtar 32 bayt', () {
    expect(acikAnahtarBayt(), hasLength(32));
  });

  test('geçerli imza kabul; mesaj, imza ya da anahtar bozulunca ret', () {
    final imza = imzala(mesaj);
    expect(imzaGecerli(mesaj, imza, acik), isTrue);
    expect(imzaGecerli([...mesaj, 0], imza, acik), isFalse);
    expect(imzaGecerli(mesaj, [...imza]..[0] ^= 0x80, acik), isFalse);
    expect(
      imzaGecerli(mesaj, imza, SigningKey.generate().verifyKey.asTypedList),
      isFalse,
    );
    expect(imzaGecerli(mesaj, imza.sublist(1), acik), isFalse);
    expect(imzaGecerli(mesaj, imza, acik.sublist(1)), isFalse);
    expect(imzaGecerli(mesaj, List.filled(64, 0), acik), isFalse);
  });

  group('yayinCoz', () {
    const zip = 'aktenak-habit-tracker-v1.4.0-windows.zip';
    String url(String ad) =>
        'https://github.com/tungarix/habit-tracker/releases/download/v1.4.0/$ad';
    Map<String, Object?> yayin({bool sig = true, String? sigUrl}) => {
      'tag_name': 'v1.4.0',
      'assets': [
        for (final ad in [zip, 'SHA256SUMS.txt', if (sig) imzaVarlikAdi])
          {
            'name': ad,
            'size': 10,
            'browser_download_url': ad == imzaVarlikAdi && sigUrl != null
                ? sigUrl
                : url(ad),
          },
      ],
    };

    test('.sig varsa imzaUrl dolar ve JSON gidiş-dönüşünde korunur', () {
      final y = yayinCoz(yayin(), guncellemeDeposu)!;
      expect(y.imzaUrl, url(imzaVarlikAdi));
      expect(Yayin.fromJson(y.toJson())!.imzaUrl, y.imzaUrl);
    });

    test(
      '.sig yoksa ya da adresi izinsizse imzaUrl null (sürüm yine teklif)',
      () {
        expect(yayinCoz(yayin(sig: false), guncellemeDeposu)!.imzaUrl, isNull);
        final kotu = yayin(sigUrl: 'https://evil.example/x.sig');
        expect(yayinCoz(kotu, guncellemeDeposu)!.imzaUrl, isNull);
      },
    );
  });
}
