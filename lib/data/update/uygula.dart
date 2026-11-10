// Uygulayıcı: çalışan uygulamanın dosyalarını değiştirir. Yeni sürümün KENDİ exe'si `--guncelle-uygula`
// bayrağıyla bunu yapar (PowerShell/cmd betiği ve ek exe yok). Saf Dart + dart:io; testler sahte klasör kullanır.
//
// Sahip olunan küme: kökteki *.exe, *.dll ve `data/`. Eski öğeler `<hedef>/.eski/` altına TAŞINIR (silinmez),
// yenileri kopyalanır; hata olursa kopyalananlar silinir, taşınanlar geri taşınır. Kümenin dışındaki
// dosyalara ve kullanıcı verisine (%APPDATA%) dokunulmaz.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'ag.dart' show GuncellemeHatasi;

const uygulamaExe = 'aktenak_habit_tracker.exe';
const guncelleBayragi = '--guncelle-uygula=1';
const eskiKlasoru = '.eski';

/// Uygulayıcının komut satırı: yalnız bu üç değer dışarıdan gelir, hepsi doğrulanır.
class UygulaArgumanlari {
  const UygulaArgumanlari(this.hedef, this.sonuc, this.pid);
  final Directory hedef;
  final File sonuc;
  final int pid;

  /// Geçersizse null (uygulayıcı hiçbir şeye dokunmadan çıkar). [veriKlasoru]: sonuç dosyası orada olmalı.
  static UygulaArgumanlari? coz(List<String> args, Directory veriKlasoru) {
    if (!args.contains(guncelleBayragi)) return null;
    String? deger(String ad) {
      final i = args.indexOf(ad);
      return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
    }

    final hedef = deger('--hedef'),
        sonuc = deger('--sonuc'),
        pid = int.tryParse(deger('--pid') ?? '');
    if (hedef == null || sonuc == null || pid == null || pid <= 0) return null;
    if (!p.isAbsolute(hedef) || !p.isAbsolute(sonuc)) return null;
    if (!File(p.join(hedef, uygulamaExe)).existsSync()) return null;
    if (!p.isWithin(veriKlasoru.path, sonuc)) return null;
    return UygulaArgumanlari(
      Directory(p.normalize(hedef)),
      File(p.normalize(sonuc)),
      pid,
    );
  }
}

/// Kökteki *.exe / *.dll dosyaları ve `data/` klasörü.
List<FileSystemEntity> sahipOlunanKume(Directory d) {
  if (!d.existsSync()) return const [];
  return [
    for (final e in d.listSync(followLinks: false))
      if ((e is File &&
              RegExp(r'\.(exe|dll)$', caseSensitive: false).hasMatch(e.path)) ||
          (e is Directory && p.basename(e.path).toLowerCase() == 'data'))
        e,
  ];
}

Future<void> _kopyala(FileSystemEntity e, String hedefYol) async {
  if (e is File) {
    await e.copy(hedefYol);
  } else if (e is Directory) {
    await Directory(hedefYol).create(recursive: true);
    await for (final c in e.list(followLinks: false)) {
      await _kopyala(c, p.join(hedefYol, p.basename(c.path)));
    }
  }
}

Future<void> _sil(String yol) async {
  final tur = FileSystemEntity.typeSync(yol, followLinks: false);
  if (tur == FileSystemEntityType.directory) {
    await Directory(yol).delete(recursive: true);
  } else if (tur != FileSystemEntityType.notFound) {
    await File(yol).delete();
  }
}

Future<void> _tasi(String kaynak, String hedef) async {
  if (FileSystemEntity.isDirectorySync(kaynak)) {
    await Directory(kaynak).rename(hedef);
  } else {
    await File(kaynak).rename(hedef);
  }
}

/// `tasklist` ile sürecin yaşayıp yaşamadığına bakar (Windows; kabuk yok, argüman listesi).
Future<bool> surecCalisiyorMu(int pid) async {
  final r = await Process.run('tasklist', [
    '/FI',
    'PID eq $pid',
    '/NH',
    '/FO',
    'CSV',
  ]);
  return (r.stdout as String).contains('"$pid"');
}

Future<void> varsayilanBaslat(String exe, String calisma) async {
  await Process.start(
    exe,
    const [],
    workingDirectory: calisma,
    mode: ProcessStartMode.detached,
  );
}

class UygulaSonucu {
  const UygulaSonucu(this.durum, [this.kod = '']);

  /// `tamam` | `geri_alindi` | `uygulama_mesgul`
  final String durum;
  final String kod;
  Map<String, String> toJson() => {'durum': durum, 'kod': kod};
}

/// [yeni] klasöründeki paketi [hedef]'e uygular. [pid] bitene kadar en çok [bekleme] bekler.
/// Sonucu [sonuc] dosyasına yazar, eski ya da yeni exe'yi [baslat] ile açar. İstisna atmaz.
Future<UygulaSonucu> uygula({
  required Directory yeni,
  required Directory hedef,
  required File sonuc,
  required int pid,
  Duration bekleme = const Duration(seconds: 30),
  Duration aralik = const Duration(milliseconds: 250),
  Future<bool> Function(int pid) calisiyorMu = surecCalisiyorMu,
  Future<void> Function(String exe, String calisma) baslat = varsayilanBaslat,
  Future<void> Function(FileSystemEntity kaynak, String hedefYol) kopyala =
      _kopyala,
}) async {
  Future<UygulaSonucu> bitir(UygulaSonucu s, String acilacakExe) async {
    try {
      await sonuc.parent.create(recursive: true);
      await sonuc.writeAsString(jsonEncode(s.toJson()), flush: true);
    } on Object {
      // sonuç yazılamasa da uygulama açılmalı
    }
    try {
      await baslat(acilacakExe, hedef.path);
    } on Object {
      // açılamayan uygulamayı kullanıcı kısayoldan açar
    }
    return s;
  }

  final eskiExe = p.join(hedef.path, uygulamaExe);
  final yeniExe = p.join(hedef.path, uygulamaExe);

  // 1) Eski süreç kapanana kadar bekle.
  final son = DateTime.now().add(bekleme);
  while (await calisiyorMu(pid)) {
    if (DateTime.now().isAfter(son)) {
      return bitir(
        const UygulaSonucu('uygulama_mesgul', 'uygulama_mesgul'),
        eskiExe,
      );
    }
    await Future<void>.delayed(aralik);
  }

  final yeniler = sahipOlunanKume(yeni);
  if (!yeniler.any((e) => p.basename(e.path) == uygulamaExe)) {
    return bitir(const UygulaSonucu('geri_alindi', 'paket_bozuk'), eskiExe);
  }
  final eskiDizin = p.join(hedef.path, eskiKlasoru);
  final tasinan = <(String, String)>[]; // (özgün yol, .eski yolu)
  final kopyalanan = <String>[];
  try {
    await _sil(eskiDizin);
    await Directory(eskiDizin).create(recursive: true);
    for (final e in sahipOlunanKume(hedef)) {
      final k = p.join(eskiDizin, p.basename(e.path));
      await _tasi(e.path, k);
      tasinan.add((e.path, k));
    }
    for (final e in yeniler) {
      final h = p.join(hedef.path, p.basename(e.path));
      kopyalanan.add(h);
      await kopyala(e, h);
    }
  } on Object catch (e) {
    for (final k in kopyalanan) {
      try {
        await _sil(k);
      } on Object {
        // geri alma en iyi çaba; taşınanlar yine de geri konur
      }
    }
    for (final (ozgun, eski) in tasinan.reversed) {
      try {
        await _tasi(eski, ozgun);
      } on Object {
        // geri alınamayan öğe .eski içinde kalır; kullanıcıya kod gösterilir
      }
    }
    final disk = e is FileSystemException && e.osError?.errorCode == 112;
    return bitir(
      UygulaSonucu('geri_alindi', disk ? 'disk_dolu' : 'uygulama_basarisiz'),
      eskiExe,
    );
  }
  return bitir(const UygulaSonucu('tamam'), yeniExe);
}

/// Yeni uygulamanın ilk açılışında: sonuç dosyasını okur, siler; kullanıcıya gösterilecek metni verir
/// (yoksa null). Başarıda ya da geri almada `.eski` ve hazırlık klasörü temizlenir.
Future<String?> sonucuOkuVeTemizle({
  required File sonuc,
  required Directory kurulum,
  required Directory hazirlik,
  required String surum,
}) async {
  String? mesaj;
  if (await sonuc.exists()) {
    try {
      final j = jsonDecode(await sonuc.readAsString());
      if (j is Map) {
        mesaj = switch (j['durum']) {
          'tamam' => "$surum sürümüne güncellendi.",
          'geri_alindi' || 'uygulama_mesgul' =>
            'Güncelleme uygulanamadı (${j['kod'] is String ? j['kod'] : 'bilinmiyor'}); eski sürüm geri yüklendi.',
          _ => null,
        };
      }
    } on Object {
      // bozuk sonuç dosyası = mesaj yok
    }
    try {
      await sonuc.delete();
    } on Object {
      // bir sonraki açılışta tekrar silinir
    }
  }
  for (final d in [Directory(p.join(kurulum.path, eskiKlasoru)), hazirlik]) {
    try {
      if (await d.exists()) await d.delete(recursive: true);
    } on Object {
      // kilitli temizlik bir sonraki açılışa kalır
    }
  }
  return mesaj;
}

/// Kurulum klasörüne yazılabiliyor mu (geçici dosya yazıp silerek)? Ağ sürücüsü/UNC reddedilir.
Future<void> kurulumKlasoruDenetle(Directory d) async {
  if (d.path.startsWith(r'\\')) {
    throw const GuncellemeHatasi('klasor_yazilamaz', 'ağ yolu');
  }
  final f = File(
    p.join(d.path, '.yazma_denemesi_${DateTime.now().microsecondsSinceEpoch}'),
  );
  try {
    await f.writeAsString('x', flush: true);
    await f.delete();
  } on FileSystemException {
    throw const GuncellemeHatasi('klasor_yazilamaz');
  }
}
