/// Wi-Fi senkron sözleşmesi (docs/wifi-senkron.md A2-A5): sabitler, hata
/// kodları, QR metni. Flutter import etmez; iki uygulama aynı kuralları uygular.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../data/sync/sync_format.dart' show syncMaxFileBytes;

const int wifiProtokolSurumu = 1;
const int qrOmruSn = 180;
const int onayBeklemeSn = 60;
const int oturumEnFazlaSn = 600;
const int jetonBayt = 16;
const int oturumBayt = 16 * 2;
const int sessionGovdeEnFazla = 1024;
const int stateGovdeEnFazla = syncMaxFileBytes;
const int istekEnFazla = 20;
const int ipBasinaHata = 5;
const int toplamHata = 50;
const int eszamanliIpBasina = 2;
const int eszamanliToplam = 8;
const int govdeOkumaSn = 30;
const int adresEnFazla = 3;
const int qrEnFazlaUzunluk = 400;
const int adEnFazla = 40;

/// Telefonun kabul ettiği QR port aralığı (Windows/Android geçici port aralığı).
const int portEnAz = 49152;
const int portEnCok = 65535;

/// Hata kodu <-> HTTP durumu (A5). Gövde yalnız `{"error":"kod"}`.
enum WifiHata {
  istekBozuk(400, 'istek_bozuk'),
  protokolSurumu(400, 'protokol_surumu'),
  senkronBozuk(400, 'senkron_bozuk'),
  senkronSurumu(400, 'senkron_surumu'),
  yetkisiz(401, 'yetkisiz'),
  reddedildi(403, 'reddedildi'),
  yok(404, 'yok'),
  metot(405, 'metot'),
  sureDoldu(408, 'sure_doldu'),
  mesgul(409, 'mesgul'),
  iptal(409, 'iptal'),
  siraHatali(409, 'sira_hatali'),
  uzunlukGerekli(411, 'uzunluk_gerekli'),
  cokBuyuk(413, 'cok_buyuk'),
  turHatali(415, 'tur_hatali'),
  cokIstek(429, 'cok_istek'),
  // Tasarımda yok: yedek alınamadı / birleştirme beklenmedik biçimde düştü.
  icHata(500, 'ic_hata');

  const WifiHata(this.http, this.kod);
  final int http;
  final String kod;
}

/// `a.b.c.d` (baştaki sıfır yok) ve özel aralıkta mı: 10/8, 172.16/12,
/// 192.168/16, 169.254/16. Loopback, CGNAT ve genel adresler dışarıda.
bool ozelIpv4mu(String ip) {
  final m = RegExp(r'^(0|[1-9]\d{0,2})\.(0|[1-9]\d{0,2})\.(0|[1-9]\d{0,2})\.(0|[1-9]\d{0,2})$')
      .firstMatch(ip);
  if (m == null) return false;
  final o = [for (var i = 1; i <= 4; i++) int.parse(m.group(i)!)];
  if (o.any((x) => x > 255)) return false;
  return o[0] == 10 ||
      (o[0] == 172 && o[1] >= 16 && o[1] <= 31) ||
      (o[0] == 192 && o[1] == 168) ||
      (o[0] == 169 && o[1] == 254);
}

/// Gösterim adı: kontrol ve çift yönlü yazı karakterleri atılır, 40'a kesilir.
String adTemizle(String s) {
  final t = s
      .replaceAll(RegExp(r'[\u0000-\u001f\u007f-\u009f\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '')
      .trim();
  return t.length > adEnFazla ? t.substring(0, adEnFazla) : t;
}

String base64urlDolgusuz(List<int> b) => base64Url.encode(b).replaceAll('=', '');

/// Sabit zamanlı eşitlik (jeton/oturum karşılaştırması).
bool sabitZamanliEsit(String a, String b) {
  final x = utf8.encode(a), y = utf8.encode(b);
  var fark = x.length ^ y.length;
  for (var i = 0; i < x.length; i++) {
    fark |= x[i] ^ y[i < y.length ? i : 0];
  }
  return fark == 0 && y.isNotEmpty;
}

/// QR metninin içeriği (A2).
class QrBaglanti {
  const QrBaglanti({
    required this.adresler,
    required this.port,
    required this.parmakIzi,
    required this.jeton,
    required this.bitis,
    required this.ad,
    this.surum = wifiProtokolSurumu,
  });

  final int surum;
  final List<String> adresler;
  final int port;
  final String parmakIzi;
  final String jeton;
  final int bitis; // unix saniyesi (UTC), yalnız arayüz ipucu
  final String ad;

  String kodla() => Uri(
        scheme: 'habitsync',
        host: 'p',
        queryParameters: {
          'v': '$surum',
          'a': adresler.join(','),
          'p': '$port',
          'f': parmakIzi,
          't': jeton,
          'e': '$bitis',
          'n': ad,
        },
      ).toString();

  /// Geçersizse null. Aynı anahtarın iki kez geçmesi, genel IP, kötü biçim: ret.
  static QrBaglanti? coz(String metin) {
    if (metin.length > qrEnFazlaUzunluk) return null;
    final Uri u;
    try {
      u = Uri.parse(metin.trim());
    } catch (_) {
      return null;
    }
    if (u.scheme != 'habitsync' || u.host != 'p' || u.userInfo.isNotEmpty) return null;
    if (u.hasFragment || (u.path.isNotEmpty && u.path != '/') || u.hasPort) return null;
    final q = <String, String>{};
    for (final kv in u.query.split('&')) {
      final i = kv.indexOf('=');
      if (i <= 0) return null;
      final k = kv.substring(0, i);
      final String v;
      try {
        v = Uri.decodeQueryComponent(kv.substring(i + 1));
      } catch (_) {
        return null;
      }
      if (q.containsKey(k)) return null;
      q[k] = v;
    }
    final v = q['v'], a = q['a'], p = q['p'], f = q['f'], t = q['t'], e = q['e'];
    if (v == null || a == null || p == null || f == null || t == null || e == null) return null;
    if (!RegExp(r'^[1-9]\d{0,3}$').hasMatch(v)) return null;
    if (!RegExp(r'^[1-9]\d{4}$').hasMatch(p)) return null;
    final port = int.parse(p);
    if (port < portEnAz || port > portEnCok) return null;
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(f)) return null;
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(t)) return null;
    if (!RegExp(r'^\d{1,12}$').hasMatch(e)) return null;
    final adresler = a.split(',');
    if (adresler.isEmpty ||
        adresler.length > adresEnFazla ||
        adresler.toSet().length != adresler.length ||
        !adresler.every(ozelIpv4mu)) {
      return null;
    }
    return QrBaglanti(
      surum: int.parse(v),
      adresler: adresler,
      port: port,
      parmakIzi: f,
      jeton: t,
      bitis: int.parse(e),
      ad: adTemizle(q['n'] ?? ''),
    );
  }
}

Uint8List utf8Bayt(String s) => Uint8List.fromList(utf8.encode(s));
