// Güncelleme mantığının SAF kısmı: sürüm karşılaştırma, release çözümleme, özet ayrıştırma.
// Ağ ve dosya yok; mobil güncelleyicinin (habit-tracker-mobil) masaüstü uyarlamasıdır.
// Güvenlik kararları (hangi adres, hangi ad, hangi boyut) burada.
import 'imza.dart';

/// Kabul edilen en büyük zip (gerçek yayın boyutu ölçülmedi; sınır bozuk/kötü niyetli dosyayı ayıklar).
/// `--dart-define=GUNCELLEME_MAKS_BAYT` yalnız geliştirme/uçtan uca denemede.
const zipEnFazlaBayt = int.fromEnvironment(
  'GUNCELLEME_MAKS_BAYT',
  defaultValue: 200 * 1024 * 1024,
);

/// Yayının GitHub deposu.
const guncellemeDeposu = 'tungarix/habit-tracker';

/// Yalnızca GitHub: API, release sayfası ve varlıkların yönlendirildiği depolama.
const izinliSunucular = {
  'api.github.com',
  'github.com',
  'objects.githubusercontent.com',
  'release-assets.githubusercontent.com',
};

final _surum = RegExp(r'^v?(\d{1,6})\.(\d{1,6})\.(\d{1,6})$');
final _hex64 = RegExp(r'^[0-9a-fA-F]{64}$');

/// `v0.4.0` / `0.4.0` -> (0, 4, 0). Yalnız düz X.Y.Z: "0.4.0-beta" ya da "0.4" tanınmaz,
/// çünkü yalnızca kararlı sürüm teklif edilir.
(int, int, int)? surumCoz(Object? metin) {
  if (metin is! String) return null;
  final m = _surum.firstMatch(metin.trim());
  if (m == null) return null;
  return (int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

/// [aday] KESİN daha yüksekse true (sayısal: 0.10.0 > 0.9.0). Eşit/eski/çözülemeyen = false.
bool dahaYeniMi(String aday, String mevcut) {
  final a = surumCoz(aday), m = surumCoz(mevcut);
  if (a == null || m == null) return false;
  if (a.$1 != m.$1) return a.$1 > m.$1;
  if (a.$2 != m.$2) return a.$2 > m.$2;
  return a.$3 > m.$3;
}

/// GitHub'daki "Latest" sürümden uygulamanın ihtiyacı olan kısım.
class Yayin {
  const Yayin({
    required this.surum,
    required this.zipUrl,
    required this.zipBoyut,
    required this.ozetUrl,
    required this.sayfaUrl,
    this.imzaUrl,
  });

  final String surum; // "0.4.0" (başında v yok)
  final String zipUrl;
  final int zipBoyut;
  final String ozetUrl;
  final String sayfaUrl;

  /// `SHA256SUMS.txt.sig` adresi; null = sürümde imza yok (kurulum `imza_yok` ile reddedilir).
  final String? imzaUrl;

  /// Zip varlığının beklenen adı (release.yml sözleşmesi; etiket `v` ile).
  String get zipAdi => 'aktenak-habit-tracker-v$surum-windows.zip';

  Map<String, Object?> toJson() => {
    'surum': surum,
    'zip_url': zipUrl,
    'zip_boyut': zipBoyut,
    'ozet_url': ozetUrl,
    'sayfa_url': sayfaUrl,
    'imza_url': ?imzaUrl,
  };

  /// Saklı kayıt elle bozulmuş olabilir: tip ve alan denetimi, bozuksa null.
  static Yayin? fromJson(Object? j) {
    if (j is! Map) return null;
    final s = j['surum'],
        a = j['zip_url'],
        b = j['zip_boyut'],
        o = j['ozet_url'],
        p = j['sayfa_url'];
    if (s is! String ||
        a is! String ||
        b is! int ||
        o is! String ||
        p is! String) {
      return null;
    }
    if (surumCoz(s) == null || b <= 0 || b > zipEnFazlaBayt) return null;
    final i = j['imza_url'];
    return Yayin(
      surum: s,
      zipUrl: a,
      zipBoyut: b,
      ozetUrl: o,
      sayfaUrl: p,
      imzaUrl: i is String ? i : null,
    );
  }
}

/// https + izinli sunucu; github.com'da yol bu deponun release'i olmalı.
/// [ekSunucular] yalnız testler içindir (yerel sahte sunucu, http de olur); üretimde boş.
bool adresUygun(Object? url, String depo, Set<String> ekSunucular) {
  // Boşluk/kontrol karakteri/ters eğik çizgi/ASCII dışı: ayrıştırıcılar farklı yorumlayabilir.
  if (url is! String || url.runes.any((r) => r > 126 || r <= 32 || r == 0x5c)) {
    return false;
  }
  final Uri u;
  try {
    u = Uri.parse(url);
  } on FormatException {
    return false;
  }
  final sunucu = u.host.toLowerCase();
  if (ekSunucular.contains(sunucu)) {
    return u.scheme == 'http' || u.scheme == 'https';
  }
  if (u.scheme != 'https' ||
      !izinliSunucular.contains(sunucu) ||
      u.userInfo.isNotEmpty) {
    return false;
  }
  if (u.hasPort && u.port != 443) return false;
  // Ham metne bakılır: Uri.parse `%2e%2e` gibi dizileri çözüp normalleştirir, path üzerinde görünmez.
  // Sorgu dizisi hariç: imzalı indirme adreslerinin sorgusunda meşru %2F bulunur.
  final ham = url.split(RegExp(r'[?#]')).first.toLowerCase();
  if (u.pathSegments.contains('..') ||
      ham.contains('%2e') ||
      ham.contains('%5c') ||
      ham.contains('%2f')) {
    return false;
  }
  if (sunucu == 'github.com') return u.path.startsWith('/$depo/releases/');
  return true;
}

/// `releases/latest` JSON'unu doğrular; uygun değilse null (sessizce teklif yok).
/// Reddedilenler: sözlük olmayan gövde, taslak/ön sürüm, düz X.Y.Z olmayan etiket, beklenen adlı
/// zip (`aktenak-habit-tracker-v<sürüm>-windows.zip`) ya da `SHA256SUMS.txt` eksikliği, sıfır/aşırı büyük boyut, izinsiz adres.
Yayin? yayinCoz(
  Object? veri,
  String depo, {
  Set<String> ekSunucular = const {},
}) {
  if (veri is! Map || veri['draft'] == true || veri['prerelease'] == true) {
    return null;
  }
  final sayi = surumCoz(veri['tag_name']);
  if (sayi == null) return null;
  final surum = '${sayi.$1}.${sayi.$2}.${sayi.$3}';
  final varliklar = veri['assets'];
  if (varliklar is! List) return null;
  final zipAdi = 'aktenak-habit-tracker-v$surum-windows.zip';
  Map? zip, ozet, imza;
  for (final v in varliklar) {
    if (v is! Map) continue;
    // Aynı adlı ikinci varlık yok sayılır (ilk eşleşme).
    if (v['name'] == zipAdi) zip ??= v;
    if (v['name'] == 'SHA256SUMS.txt') ozet ??= v;
    if (v['name'] == imzaVarlikAdi) imza ??= v;
  }
  if (zip == null || ozet == null) return null;
  final boyut = zip['size'];
  if (boyut is! int || boyut <= 0 || boyut > zipEnFazlaBayt) return null;
  final zipUrl = zip['browser_download_url'],
      ozetUrl = ozet['browser_download_url'];
  if (!adresUygun(zipUrl, depo, ekSunucular) ||
      !adresUygun(ozetUrl, depo, ekSunucular)) {
    return null;
  }
  final sayfa = veri['html_url'];
  // İmza varlığı yok ya da adresi izinsizse null: sürüm yine teklif edilir, kurulum imza_yok ile reddedilir.
  final imzaUrl = imza?['browser_download_url'];
  return Yayin(
    surum: surum,
    zipUrl: zipUrl as String,
    zipBoyut: boyut,
    ozetUrl: ozetUrl as String,
    sayfaUrl: adresUygun(sayfa, depo, ekSunucular)
        ? sayfa as String
        : 'https://github.com/$depo/releases',
    imzaUrl: adresUygun(imzaUrl, depo, ekSunucular) ? imzaUrl as String : null,
  );
}

/// `SHA256SUMS.txt` içinden [ad] dosyasının küçük harfli SHA-256'sı. Biçim `sha256sum`'unki:
/// `<64 hex>  <ad>` (ikinci ayraç ` *` de olabilir). Aynı ad iki kez geçerse belirsizlik güvenli
/// değildir: null.
String? ozetCoz(String metin, String ad) {
  final bulunan = <String>[];
  for (final satir in metin.split('\n')) {
    final t = satir.trim();
    final bosluk = t.indexOf(RegExp(r'\s'));
    if (bosluk < 0) continue;
    final hash = t.substring(0, bosluk);
    var dosya = t.substring(bosluk).trim();
    if (dosya.startsWith('*')) dosya = dosya.substring(1).trim();
    if (dosya == ad && _hex64.hasMatch(hash)) bulunan.add(hash.toLowerCase());
  }
  return bulunan.length == 1 ? bulunan.first : null;
}
