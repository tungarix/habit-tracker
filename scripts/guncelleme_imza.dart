// Güncelleme imzası aracı. Kullanım (depo kökünden):
//   dart run scripts/guncelleme_imza.dart uret <klasor>
//       Yeni Ed25519 anahtar çifti üretir; ÖZEL anahtarı <klasor>/guncelleme-ozel-anahtar.b64'ye yazar
//       (klasör yalnız bu kullanıcıya açılır, Windows). Ekrana yalnız AÇIK anahtar basılır.
//   dart run scripts/guncelleme_imza.dart imzala <dosya> <cikti.sig> [--acik-anahtar <b64>]
//       Özel anahtarı HABIT_UPDATE_SIGNING_KEY ortam değişkeninden okur (base64 tohum), dosyayı imzalar,
//       imzayı AÇIK anahtara karşı doğrular (yanlış sır = hata), ham 64 bayt yazar. Anahtar hiçbir yere basılmaz.
import 'dart:convert';
import 'dart:io';

import 'package:aktenak_habit_tracker/data/update/imza.dart';
import 'package:pinenacl/ed25519.dart';

const _dosyaAdi = 'guncelleme-ozel-anahtar.b64';
const _ortam = 'HABIT_UPDATE_SIGNING_KEY';

Never _hata(String m) {
  stderr.writeln('HATA: $m');
  exit(1);
}

Future<void> main(List<String> a) async {
  if (a.length >= 2 && a[0] == 'uret') return _uret(a[1]);
  if (a.length >= 3 && a[0] == 'imzala') return _imzala(a);
  _hata(
    'kullanım: uret <klasor> | imzala <dosya> <cikti.sig> [--acik-anahtar <b64>]',
  );
}

Future<void> _uret(String klasor) async {
  final dosya = File('$klasor${Platform.pathSeparator}$_dosyaAdi');
  if (dosya.existsSync()) _hata('${dosya.path} zaten var; üzerine yazılmaz.');
  await Directory(klasor).create(recursive: true);
  if (Platform.isWindows) {
    // Miras kapalı, yalnız mevcut kullanıcı tam yetkili.
    final r = await Process.run('icacls', [
      klasor,
      '/inheritance:r',
      '/grant:r',
      '${Platform.environment['USERNAME']}:(OI)(CI)F',
    ]);
    if (r.exitCode != 0) _hata('klasör izinleri ayarlanamadı (icacls).');
  }
  final anahtar = SigningKey.generate();
  await dosya.writeAsString(base64Encode(anahtar.seed.asTypedList));
  stdout.writeln('Özel anahtar yazıldı: ${dosya.path}');
  stdout.writeln(
    'AÇIK anahtar (koda gömülür): ${base64Encode(anahtar.verifyKey.asTypedList)}',
  );
}

Future<void> _imzala(List<String> a) async {
  final sir = Platform.environment[_ortam]?.trim() ?? '';
  if (sir.isEmpty) _hata('$_ortam tanımlı değil; imza üretilemez.');
  final Uint8List tohum;
  try {
    tohum = base64Decode(sir);
  } on FormatException {
    _hata('$_ortam geçerli base64 değil.');
  }
  if (tohum.length != 32) _hata('$_ortam 32 baytlık tohum olmalı.');
  final i = a.indexOf('--acik-anahtar');
  final acik = i >= 0 && i + 1 < a.length
      ? base64Decode(a[i + 1])
      : acikAnahtarBayt();
  final mesaj = await File(a[1]).readAsBytes();
  final imza = SigningKey.fromSeed(tohum).sign(mesaj).signature.asTypedList;
  if (!imzaGecerli(mesaj, imza, acik)) {
    _hata('imza gömülü AÇIK anahtarla doğrulanmadı: $_ortam yanlış anahtar.');
  }
  await File(a[2]).writeAsBytes(imza);
  stdout.writeln('İmza yazıldı: ${a[2]} (açık anahtarla doğrulandı).');
}
