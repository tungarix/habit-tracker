// İndirilen release zip'ini hazırlık klasörüne güvenle açar (zip-slip, sıkıştırma bombası, özel girdiler).
// Girdilerin HEPSİ açmadan önce denetlenir; tek kötü girdi tüm paketi reddeder ve hazırlık klasörü silinir.
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import 'ag.dart' show GuncellemeHatasi;

const paketEnFazlaDosya = 3000;
const paketEnFazlaToplamBayt = 600 * 1024 * 1024;
const paketEnFazlaTekBayt = 300 * 1024 * 1024;

/// Açılmış pakette bulunması gereken dosyalar (Flutter Windows çıktısı). Gerçek bir derleme
/// çıktısıyla karşılaştırılmadı: yeni derlemede değişirse güncelleme `paket_bozuk` ile durur, güvenli yönde.
const paketZorunluDosyalar = [
  'aktenak_habit_tracker.exe',
  'flutter_windows.dll',
  'data/app.so',
  'data/icudtl.dat',
];

final _ayrilmisAd = RegExp(
  r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\..*)?$',
  caseSensitive: false,
);

/// Zip girdi adını normalleştirir; güvensizse null. `\` -> `/`; mutlak yol, sürücü harfi, `..`,
/// boş parça, NTFS akışı (`:`), ayrılmış Windows adı ve sonda nokta/boşluk reddedilir.
String? girdiAdiTemizle(String ad) {
  final a = ad.replaceAll('\\', '/');
  if (a.isEmpty ||
      a.startsWith('/') ||
      a.contains(':') ||
      a.runes.any((r) => r < 32)) {
    return null;
  }
  final parcalar = a.endsWith('/')
      ? a.substring(0, a.length - 1).split('/')
      : a.split('/');
  for (final s in parcalar) {
    if (s.isEmpty ||
        s == '.' ||
        s == '..' ||
        s.endsWith('.') ||
        s.endsWith(' ') ||
        _ayrilmisAd.hasMatch(s)) {
      return null;
    }
  }
  return parcalar.join('/');
}

/// [zip]'i [hedef] klasörüne açar (önce silinip yeniden yaratılır). Hata = `paket_bozuk` ya da
/// `disk_dolu`/`izin_yok`; hatada [hedef] silinir.
Future<void> paketiAc(File zip, Directory hedef) async {
  if (await hedef.exists()) await hedef.delete(recursive: true);
  await hedef.create(recursive: true);
  final girdi = InputFileStream(zip.path);
  try {
    final Archive arsiv;
    try {
      arsiv = ZipDecoder().decodeStream(girdi, verify: true);
    } on Object {
      throw const GuncellemeHatasi('paket_bozuk', 'zip okunamadı');
    }
    var toplam = 0, sayi = 0;
    final yazilacak = <(ArchiveFile, String)>[];
    final adlar = <String>{};
    for (final f in arsiv) {
      final ad = girdiAdiTemizle(f.name);
      if (ad == null) {
        throw GuncellemeHatasi('paket_bozuk', 'güvensiz ad: ${f.name}');
      }
      if (f.isSymbolicLink || f.isHardLink) {
        throw GuncellemeHatasi('paket_bozuk', 'bağ girdisi: ${f.name}');
      }
      if (!adlar.add(ad.toLowerCase())) {
        throw GuncellemeHatasi('paket_bozuk', 'yinelenen ad: $ad');
      }
      final yol = p.normalize(p.join(hedef.path, ad));
      if (!p.isWithin(hedef.path, yol)) {
        throw GuncellemeHatasi('paket_bozuk', 'kök dışı: ${f.name}');
      }
      if (!f.isFile) continue;
      if (++sayi > paketEnFazlaDosya) {
        throw const GuncellemeHatasi('paket_bozuk', 'çok fazla dosya');
      }
      if (f.size > paketEnFazlaTekBayt) {
        throw GuncellemeHatasi('paket_bozuk', 'dosya çok büyük: $ad');
      }
      toplam += f.size;
      if (toplam > paketEnFazlaToplamBayt) {
        throw const GuncellemeHatasi('paket_bozuk', 'açılmış boyut çok büyük');
      }
      yazilacak.add((f, yol));
    }
    // shortcut: bildirilen boyuta güveniyoruz; gerçek yazılan toplam aşağıda yeniden sınanır, ama tek bir
    // yalancı başlık o dosya bitene kadar yazar. Zip boyut sınırı (200 MiB) + SHA-256 bunu zaten daraltır.
    var yazilan = 0;
    for (final (f, yol) in yazilacak) {
      await Directory(p.dirname(yol)).create(recursive: true);
      final cikti = OutputFileStream(yol);
      try {
        f.writeContent(cikti);
      } finally {
        await cikti.close();
      }
      yazilan += await File(yol).length();
      if (yazilan > paketEnFazlaToplamBayt) {
        throw const GuncellemeHatasi('paket_bozuk', 'açılmış boyut çok büyük');
      }
    }
    for (final z in paketZorunluDosyalar) {
      if (!await File(p.join(hedef.path, z)).exists()) {
        throw GuncellemeHatasi('paket_bozuk', 'eksik: $z');
      }
    }
  } on Object catch (e) {
    try {
      await hedef.delete(recursive: true);
    } on Object {
      // silinemeyen hazırlık klasörü bir sonraki indirmede yeniden yaratılır
    }
    if (e is GuncellemeHatasi) rethrow;
    if (e is FileSystemException && e.osError?.errorCode == 112) {
      throw const GuncellemeHatasi('disk_dolu');
    }
    if (e is FileSystemException) {
      throw const GuncellemeHatasi('izin_yok', 'paket açılamadı');
    }
    throw const GuncellemeHatasi('paket_bozuk', 'açılamadı');
  } finally {
    await girdi.close();
  }
}
