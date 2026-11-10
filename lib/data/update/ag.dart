// Güncelleme ağ katmanı: GitHub'dan son sürümü sorar, zip'i indirir.
// Yalnızca `izinliSunucular`'a gider; yönlendirmeler elle izlenir ve her adım aynı denetimden geçer.
// Hiçbir kimlik, çerez ya da kullanıcı verisi gönderilmez; tek başlık `User-Agent: HabitTracker/<sürüm>`.
// Çağıran taraf bu sınıfı yalnızca kullanıcı denetimi AÇTIYSA (ya da "Şimdi denetle"ye bastıysa) kullanır.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/sha256.dart';
import 'saf.dart';

const _jsonSiniri = 1024 * 1024;

/// SHA256SUMS.txt üst sınırı.
const ozetSiniri = 64 * 1024;
const _enFazlaYonlendirme = 5;

/// [kod] arayüzde yerelleştirilen kısa tanımlayıcı (`limit`, `ag_hatasi`, `ozet_uyusmuyor`...).
class GuncellemeHatasi implements Exception {
  const GuncellemeHatasi(this.kod, [this.ayrinti = '']);
  final String kod;
  final String ayrinti;

  @override
  String toString() =>
      'GuncellemeHatasi($kod${ayrinti.isEmpty ? '' : ', $ayrinti'})';
}

/// İndirmeyi iptal etmek için bayrak (arayüzdeki İptal düğmesi).
class Iptal {
  bool iptalEdildi = false;
  void iptalEt() => iptalEdildi = true;
}

/// ("yeni", yayin, etag) | ("degismedi", null, etag) | ("yok", null, null)
typedef SonYayinSonucu = (String, Yayin?, String?);

class Ag {
  Ag({
    this.depo = guncellemeDeposu,
    this.surum = '',
    this.apiTaban = 'https://api.github.com',
    this.ekSunucular = const {},
    this.zamanAsimi = const Duration(seconds: 10),
  });

  final String depo;
  final String surum;
  final String apiTaban;

  /// Yalnız testler (yerel sahte sunucu); üretim kodu boş bırakır, böylece izinli küme gevşemez.
  final Set<String> ekSunucular;
  final Duration zamanAsimi;

  /// Yönlendirmeleri elle izleyerek (her adımda adres denetimi) istek açar. Yanıtı çağıran tüketir.
  Future<(HttpClient, HttpClientResponse)> _ac(
    String url, [
    Map<String, String> baslik = const {},
  ]) async {
    final istemci = HttpClient()..connectionTimeout = zamanAsimi;
    try {
      var adres = url;
      for (var i = 0; i <= _enFazlaYonlendirme; i++) {
        if (!adresUygun(adres, depo, ekSunucular)) {
          throw GuncellemeHatasi('adres_izinsiz', adres);
        }
        final istek = await istemci
            .getUrl(Uri.parse(adres))
            .timeout(zamanAsimi);
        istek.followRedirects = false;
        istek.headers.set(HttpHeaders.userAgentHeader, 'HabitTracker/$surum');
        baslik.forEach(istek.headers.set);
        final yanit = await istek.close().timeout(zamanAsimi);
        if (yanit.isRedirect) {
          final yer = yanit.headers.value(HttpHeaders.locationHeader);
          await yanit.drain<void>().timeout(zamanAsimi);
          if (yer == null) {
            throw const GuncellemeHatasi('ag_hatasi', 'yönlendirme adresi yok');
          }
          adres = Uri.parse(adres).resolve(yer).toString();
          continue;
        }
        return (istemci, yanit);
      }
      throw const GuncellemeHatasi('ag_hatasi', 'çok fazla yönlendirme');
    } catch (_) {
      istemci.close(force: true);
      rethrow;
    }
  }

  static GuncellemeHatasi _agHatasi(Object e) => e is GuncellemeHatasi
      ? e
      : GuncellemeHatasi('ag_hatasi', e.runtimeType.toString());

  /// Gövdeyi [sinir] baytla sınırlı okur; aşılırsa `bozuk_yanit`.
  Future<List<int>> _oku(HttpClientResponse y, int sinir) async {
    final tampon = <int>[];
    await for (final parca in y.timeout(zamanAsimi)) {
      tampon.addAll(parca);
      if (tampon.length > sinir) {
        throw const GuncellemeHatasi('bozuk_yanit', 'yanıt çok büyük');
      }
    }
    return tampon;
  }

  /// Son sürümü sorar. 304 limit yemez (ETag'in amacı). Ağ/limit hatasında [GuncellemeHatasi].
  Future<SonYayinSonucu> sonYayin([String? etag]) async {
    final baslik = {
      'Accept': 'application/vnd.github+json',
      'If-None-Match': ?etag,
    };
    final HttpClient istemci;
    final HttpClientResponse yanit;
    try {
      (istemci, yanit) = await _ac(
        '$apiTaban/repos/$depo/releases/latest',
        baslik,
      );
    } on Object catch (e) {
      throw _agHatasi(e);
    }
    try {
      switch (yanit.statusCode) {
        case 304:
          return ('degismedi', null, etag);
        case 404:
          return ('yok', null, null);
        case 403 || 429:
          throw GuncellemeHatasi('limit', 'HTTP ${yanit.statusCode}');
        case != 200:
          throw GuncellemeHatasi('ag_hatasi', 'HTTP ${yanit.statusCode}');
      }
      final ham = await _oku(yanit, _jsonSiniri);
      final Object? veri;
      try {
        veri = jsonDecode(utf8.decode(ham));
      } on FormatException {
        throw const GuncellemeHatasi('bozuk_yanit', 'geçersiz JSON');
      }
      final yayin = yayinCoz(veri, depo, ekSunucular: ekSunucular);
      final yeniEtag = yanit.headers.value(HttpHeaders.etagHeader);
      return yayin == null
          ? ('yok', null, yeniEtag)
          : ('yeni', yayin, yeniEtag);
    } on Object catch (e) {
      throw _agHatasi(e);
    } finally {
      istemci.close(force: true);
    }
  }

  /// Küçük bir dosya (SHA256SUMS.txt, .sig), ham baytlar: imza bayt üzerinden doğrulanır, metne çevrilmez.
  Future<List<int>> baytIndir(String url, int sinir) async {
    try {
      final (istemci, yanit) = await _ac(url);
      try {
        if (yanit.statusCode != 200) {
          throw GuncellemeHatasi('ag_hatasi', 'HTTP ${yanit.statusCode}');
        }
        return await _oku(yanit, sinir);
      } finally {
        istemci.close(force: true);
      }
    } on Object catch (e) {
      throw _agHatasi(e);
    }
  }

  /// [url]'yi [hedef]'e indirir, SHA-256'sını (küçük harfli onaltılık) döndürür. Önce `<hedef>.part`'a
  /// yazılır, tamamlanınca taşınır; her hatada kısmi dosya silinir. Boyut [beklenenBoyut]'tan farklıysa
  /// iptal: sunucunun bildirdiğinden fazlasını diske yazmıyoruz.
  Future<String> indir(
    String url,
    File hedef,
    int beklenenBoyut, {
    void Function(int alinan)? ilerleme,
    Iptal? iptal,
  }) async {
    final gecici = File('${hedef.path}.part');
    IOSink? cikti;
    try {
      await hedef.parent.create(recursive: true);
      final (istemci, yanit) = await _ac(url);
      try {
        if (yanit.statusCode != 200) {
          throw GuncellemeHatasi('ag_hatasi', 'HTTP ${yanit.statusCode}');
        }
        cikti = gecici.openWrite();
        final ozet = Sha256Akis();
        var toplam = 0;
        await for (final parca in yanit.timeout(zamanAsimi)) {
          if (iptal?.iptalEdildi ?? false) {
            throw const GuncellemeHatasi('iptal');
          }
          toplam += parca.length;
          if (toplam > beklenenBoyut) {
            throw const GuncellemeHatasi(
              'boyut_uyusmuyor',
              'beklenenden büyük',
            );
          }
          ozet.ekle(parca);
          cikti.add(parca);
          ilerleme?.call(toplam);
        }
        await cikti.close();
        cikti = null;
        if (toplam != beklenenBoyut) {
          throw GuncellemeHatasi(
            'boyut_uyusmuyor',
            '$toplam != $beklenenBoyut',
          );
        }
        await gecici.rename(hedef.path);
        return onaltilik(ozet.bitir());
      } finally {
        istemci.close(force: true);
      }
    } on Object catch (e) {
      try {
        await cikti?.close();
      } on Object {
        // kapanış hatası asıl hatayı gölgelemesin
      }
      try {
        if (await gecici.exists()) await gecici.delete();
      } on FileSystemException {
        // silinemeyen kısmi dosya bir sonraki indirmede ezilir
      }
      if (e is FileSystemException) {
        throw GuncellemeHatasi('izin_yok', e.runtimeType.toString());
      }
      throw _agHatasi(e);
    }
  }
}
