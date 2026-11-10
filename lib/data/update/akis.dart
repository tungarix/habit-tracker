// Kullanıcının tetiklediği kurulum akışı: önkoşul -> yedek -> uygulayıcıyı başlat -> uygulamayı kapat.
// Gerçek kurucu burada ENJEKTE edilir (Kurucu): testler sahtesini verir, hiçbir dosya değiştirilmez.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../shared/desktop_integration.dart';
import '../../surum.dart';
import '../providers.dart';
import 'ag.dart';
import 'ayarlar.dart';
import 'guncelleyici.dart';
import 'saf.dart';
import 'uygula.dart';

/// GELİŞTİRME / uçtan uca deneme: `--dart-define=GUNCELLEME_TABAN=http://127.0.0.1:8123` güncelleyiciyi
/// tool/guncelleme_sahte_github.py'ye bağlar. Yayın derlemesinde ASLA verilmez.
const _guncellemeTaban = String.fromEnvironment('GUNCELLEME_TABAN');

Ag guncellemeAgi(String surum) => _guncellemeTaban.isEmpty
    ? Ag(surum: surum)
    : Ag(
        surum: surum,
        apiTaban: _guncellemeTaban,
        ekSunucular: {Uri.parse(_guncellemeTaban).host},
      );

/// Kurulumun dış dünyaya dokunan adımları. Varsayılanlar gerçek; testler [Kurucu]'yu sahteleriyle kurar.
class Kurucu {
  const Kurucu({
    required this.kurulumKlasoru,
    required this.sonucDosyasi,
    required this.yedekAl,
    required this.uygulayiciyiBaslat,
    required this.kapat,
    this.surecNo,
  });

  final Directory kurulumKlasoru;
  final File sonucDosyasi;
  final Future<void> Function() yedekAl;
  final Future<void> Function(String exe, List<String> args) uygulayiciyiBaslat;
  final Future<void> Function() kapat;
  final int? surecNo;

  /// İndirmeden önce: kurulum klasörüne yazılabiliyor mu?
  Future<void> onKosul() => kurulumKlasoruDenetle(kurulumKlasoru);

  /// Hazır paketi uygulatır ve uygulamayı kapatır. Yedek alınamazsa kurulum BAŞLAMAZ.
  Future<void> kur(Guncelleyici g) async {
    final exe = p.join(g.yeniPaket.path, uygulamaExe);
    if (!File(exe).existsSync()) {
      throw const GuncellemeHatasi('paket_bozuk', 'hazır paket yok');
    }
    try {
      await yedekAl();
    } on Object {
      throw const GuncellemeHatasi('izin_yok', 'yedek alınamadı');
    }
    await uygulayiciyiBaslat(exe, [
      guncelleBayragi,
      '--hedef',
      kurulumKlasoru.path,
      '--sonuc',
      sonucDosyasi.path,
      '--pid',
      '${surecNo ?? pid}',
    ]);
    await kapat();
  }
}

final guncelleyiciProvider = FutureProvider<Guncelleyici>((ref) async {
  final veri = await ref.watch(dataDirectoryProvider.future);
  return Guncelleyici(
    ayarlar: await GuncellemeAyarlari.yukle(ref.watch(databaseProvider)),
    klasor: Directory(p.join(veri.path, 'guncelleme')),
    surum: uygulamaSurumu,
    ag: guncellemeAgi(uygulamaSurumu),
  );
});

final kurucuProvider = FutureProvider<Kurucu>((ref) async {
  final veri = await ref.watch(dataDirectoryProvider.future);
  return Kurucu(
    kurulumKlasoru: File(Platform.resolvedExecutable).parent,
    sonucDosyasi: File(p.join(veri.path, 'guncelleme_sonucu.json')),
    yedekAl: () async =>
        (await ref.read(autoBackupProvider.future)).runIfDue(DateTime.now()),
    uygulayiciyiBaslat: (exe, args) async {
      await Process.start(exe, args, mode: ProcessStartMode.detached);
    },
    kapat: () async => TrayService.current?.quit(),
  );
});

/// Sürüm notları sayfasını varsayılan tarayıcıda açar; yalnız izinli GitHub adresi.
Future<bool> surumNotlariniAc(Yayin y) async {
  if (!adresUygun(y.sayfaUrl, guncellemeDeposu, const {})) return false;
  try {
    await Process.start('rundll32', [
      'url.dll,FileProtocolHandler',
      y.sayfaUrl,
    ], mode: ProcessStartMode.detached);
    return true;
  } on Object {
    return false;
  }
}
