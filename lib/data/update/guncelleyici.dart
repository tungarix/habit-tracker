// Güncelleyici: denetim zamanı, ETag ve bulunan sürümün saklanması + indirme/doğrulama/açma.
// Durum Settings tablosunda (ayarlar.dart) (kullanıcı verisi değil: bozuksa "hiç denetlenmedi" sayılır).
// Kurulum (dosya değiştirme) burada DEĞİL: `uygula.dart` (yeni sürümün kendi exe'si); akışı `akis.dart` yönetir.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/sha256.dart';
import 'ag.dart';
import 'ayarlar.dart';
import 'imza.dart';
import 'paket.dart';
import 'saf.dart';

/// Günde en çok bir denetim. "Şimdi denetle" bu sınıra takılmaz: o, kullanıcının kendi isteği.
const denetimAraligi = Duration(hours: 24);

class Guncelleyici {
  Guncelleyici({
    required this.ayarlar,
    required this.klasor,
    required this.surum,
    Ag? ag,
    DateTime Function()? saat,
    List<int>? acikAnahtar,
  }) : ag = ag ?? Ag(surum: surum),
       acikAnahtar = acikAnahtar ?? acikAnahtarBayt(),
       _saat = saat ?? DateTime.now;

  final GuncellemeAyarlari ayarlar;

  /// Hazırlık klasörü (kullanıcıya özel): `indirme/` zip, `yeni/` açılmış paket.
  final Directory klasor;
  final String surum;
  final Ag ag;

  /// SHA256SUMS.txt imzasının doğrulandığı Ed25519 açık anahtarı (üretimde koda gömülü; yalnız testler değiştirir).
  final List<int> acikAnahtar;
  final DateTime Function() _saat;

  /// Açılmış yeni paket (`hazirla` başarılıysa dolu).
  Directory get yeniPaket => Directory(p.join(klasor.path, 'yeni'));

  /// `null` = hiç sorulmadı (ağ isteği YOK), true/false = kullanıcının seçimi.
  bool? get denetim => ayarlar.guncellemeDenetimi;

  Future<void> denetimYaz(bool acik) => ayarlar.guncellemeDenetimiYaz(acik);

  DateTime? get sonDenetim {
    final s = ayarlar.guncellemeKaydi['son_denetim'];
    if (s is! String) return null;
    final an = DateTime.tryParse(s);
    return (an != null && an.isUtc) ? an : null;
  }

  String? get hataKodu {
    final k = ayarlar.guncellemeKaydi['hata_kodu'];
    return k is String ? k : null;
  }

  /// Saklı teklif; yalnızca şimdikinden KESİN yüksek ve adresi hâlâ geçerliyse (dosya elle bozulmuş olabilir).
  Yayin? get teklif {
    final y = Yayin.fromJson(ayarlar.guncellemeKaydi['yayin']);
    if (y == null || !dahaYeniMi(y.surum, surum)) return null;
    if (!adresUygun(y.zipUrl, ag.depo, ag.ekSunucular) ||
        !adresUygun(y.ozetUrl, ag.depo, ag.ekSunucular)) {
      return null;
    }
    return y;
  }

  /// Son denetimden en az 24 saat geçti mi (ya da hiç denetlenmedi mi).
  bool get denetimZamaniGeldi {
    final son = sonDenetim, simdi = _saat().toUtc();
    // Saat geriye alındıysa (son gelecekte) beklemek yerine yeniden denetle.
    return son == null ||
        son.isAfter(simdi) ||
        simdi.difference(son) >= denetimAraligi;
  }

  /// GitHub'a sorar ve sonucu saklar. İstisna atmaz: hata `hata_kodu` olarak saklanır (mevcut sürümle
  /// devam). Hatada da `son_denetim` yazılır: kötü ağda her açılışta yeniden denenmesin.
  Future<void> denetle() async {
    final kayit = ayarlar.guncellemeKaydi;
    final etagSakli = kayit['etag'];
    final etag = teklif != null && etagSakli is String ? etagSakli : null;
    try {
      final (sonuc, yayin, yeniEtag) = await ag.sonYayin(etag);
      kayit.remove('hata_kodu');
      if (sonuc == 'yeni' && yayin != null) {
        kayit['yayin'] = yayin.toJson();
        kayit['etag'] = yeniEtag;
      } else if (sonuc == 'yok') {
        kayit
          ..remove('yayin')
          ..remove('etag');
      }
      // "degismedi": saklı sürüm olduğu gibi kalır
    } on GuncellemeHatasi catch (e) {
      kayit['hata_kodu'] = e.kod;
    }
    kayit['son_denetim'] = _saat().toUtc().toIso8601String();
    await ayarlar.guncellemeKaydiYaz(kayit);
  }

  /// Arka plan kuralı (plan §1.1): kullanıcı denetimi açmadıysa (kapalı ya da hiç sorulmadı) ağ isteği
  /// YOK; açıksa en çok günde bir. Ağa GİTTİYSE true.
  Future<bool> otomatikAdim() async {
    if (denetim != true || !denetimZamaniGeldi) return false;
    await denetle();
    return true;
  }

  /// Hazırlığı siler (ilk onay vermeyen / "Sonra" diyen için: yarım kurulum durumu tutulmaz).
  Future<void> temizle() async {
    try {
      if (await klasor.exists()) await klasor.delete(recursive: true);
    } on FileSystemException {
      // kilitli dosya bir sonraki hazırlıkta yeniden silinmeyi dener
    }
  }

  /// [y]'nin SHA256SUMS.txt imzasını (Ed25519) doğrular, zip'i indirir, SHA-256 ile DOĞRULAR ve [yeniPaket]'e açar. Özet bulunamaz/belirsizse, tutmazsa ya da
  /// paket bozuksa her şey silinir ve [GuncellemeHatasi] atılır. Önceki hazırlık önce temizlenir.
  Future<void> hazirla(
    Yayin y, {
    void Function(int alinan)? ilerleme,
    Iptal? iptal,
  }) async {
    if (!dahaYeniMi(y.surum, surum)) {
      throw const GuncellemeHatasi('surum_dusuk');
    }
    await temizle();
    await klasor.create(recursive: true);
    try {
      final ozetBayt = await ag.baytIndir(y.ozetUrl, ozetSiniri);
      await _imzaDogrula(y, ozetBayt);
      final beklenen = ozetCoz(
        utf8.decode(ozetBayt, allowMalformed: true),
        y.zipAdi,
      );
      if (beklenen == null) {
        throw const GuncellemeHatasi(
          'ozet_bulunamadi',
          'SHA256SUMS.txt icinde zip satiri yok ya da belirsiz',
        );
      }
      final hedef = File(p.join(klasor.path, 'indirme', y.zipAdi));
      final gelen = await ag.indir(
        y.zipUrl,
        hedef,
        y.zipBoyut,
        ilerleme: ilerleme,
        iptal: iptal,
      );
      if (gelen != beklenen) {
        throw GuncellemeHatasi('ozet_uyusmuyor', '$gelen != $beklenen');
      }
      // Dosya indirmeden sonra değişmiş olabilir: açmadan hemen önce yeniden özetle.
      if (await dosyaOzeti(hedef) != beklenen) {
        throw const GuncellemeHatasi('ozet_uyusmuyor', 'açma öncesi');
      }
      await paketiAc(hedef, yeniPaket);
      await hedef.parent.delete(recursive: true);
    } on Object {
      await temizle();
      rethrow;
    }
  }

  /// İmzasız / bozuk / başka anahtarla atılmış imza = kurulum reddi. Zip bu doğrulamadan ÖNCE indirilmez.
  Future<void> _imzaDogrula(Yayin y, List<int> ozetBayt) async {
    final url = y.imzaUrl;
    if (url == null) throw const GuncellemeHatasi('imza_yok');
    final List<int> imza;
    try {
      imza = await ag.baytIndir(url, 256);
    } on GuncellemeHatasi catch (e) {
      // 404: sürümde .sig varlığı yok
      throw e.ayrinti == 'HTTP 404' ? const GuncellemeHatasi('imza_yok') : e;
    }
    if (!imzaGecerli(ozetBayt, imza, acikAnahtar)) {
      throw const GuncellemeHatasi('imza_gecersiz');
    }
  }

  /// Dosyanın SHA-256'sı (test ve kurulum öncesi yeniden doğrulama için).
  static Future<String> dosyaOzeti(File f) async {
    final ozet = Sha256Akis();
    await for (final parca in f.openRead()) {
      ozet.ekle(parca);
    }
    return onaltilik(ozet.bitir());
  }
}
