/// Geçici HTTPS eşleştirme sunucusu + durum makinesi (docs/wifi-senkron.md A1-A5).
///
/// Arayüzden bağımsız: veri işlemleri ve onaylar dışarıdan verilir. Tek oturum
/// yaşar; jeton ilk `POST /v1/session`'da yanar; sunucu terminal durumda kapanır.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../../data/sync/sync_format.dart';
import 'ag_adresleri.dart';
import 'sertifika.dart';
import 'sozlesme.dart';

enum EslestirmeDurum {
  bekliyor,
  baglantiOnayi,
  hazir,
  birlesmeOnayi,
  isleniyor,
  tamam,
  reddedildi,
  iptal,
  sureDoldu,
  hata;

  bool get bitti => index >= tamam.index;
}

/// Testte süreleri kısaltmak için.
class EslestirmeAyar {
  const EslestirmeAyar({
    this.qrOmru = const Duration(seconds: qrOmruSn),
    this.onayBekleme = const Duration(seconds: onayBeklemeSn),
    this.oturumEnFazla = const Duration(seconds: oturumEnFazlaSn),
    this.govdeOkuma = const Duration(seconds: govdeOkumaSn),
    this.loopbackIzinli = false,
  });
  final Duration qrOmru, onayBekleme, oturumEnFazla, govdeOkuma;

  /// Yalnız testte true: üretim yalnız özel aralıktan gelen bağlantıyı alır.
  final bool loopbackIzinli;
}

class IstemciBilgisi {
  const IstemciBilgisi(this.ad, this.ip);
  final String ad, ip;
}

class EslestirmeSunucusu {
  EslestirmeSunucusu({
    required this.durumAl,
    required this.onizle,
    required this.uygula,
    required this.yedekAl,
    this.sunucuAdi = 'Bilgisayar',
    this.surum = '0.0.0',
    this.ayar = const EslestirmeAyar(),
    this.adresler,
    this._sertifika,
  });

  /// Bu cihazın tam durumu (`.habitsync` baytları).
  final Future<Uint8List> Function() durumAl;

  /// Telefonun dosyasını kuru çalıştırır; `SyncException` fırlatabilir.
  final Future<SyncReport> Function(Uint8List) onizle;
  final Future<SyncReport> Function(Uint8List) uygula;

  /// Birleştirmeden hemen önce; fırlatırsa birleştirme yapılmaz.
  final Future<void> Function() yedekAl;
  final String sunucuAdi, surum;
  final EslestirmeAyar ayar;

  /// Verilmezse ağ arayüzlerinden (yalnız özel IPv4) bulunur.
  final List<String>? adresler;
  OturumSertifikasi? _sertifika;

  // -- Dışarıya görünen durum --------------------------------------------------
  final _durumAkisi = StreamController<EslestirmeDurum>.broadcast();
  Stream<EslestirmeDurum> get durumlar => _durumAkisi.stream;
  EslestirmeDurum _durum = EslestirmeDurum.bekliyor;
  EslestirmeDurum get durum => _durum;
  QrBaglanti? qr;
  IstemciBilgisi? istemci;
  SyncReport? ozet;
  SyncReport? sonuc;
  DateTime? qrBitis;

  /// Bellekte olay listesi (jeton, oturum anahtarı, dosya içeriği yok).
  final olaylar = <String>[];
  final _bitti = Completer<EslestirmeDurum>();
  Future<EslestirmeDurum> get bitti => _bitti.future;

  // -- İç durum ----------------------------------------------------------------
  final _sunucular = <HttpServer>[];
  String? _jeton, _oturum, _oturumIp;
  final _ipHata = <String, int>{};
  final _ipAktif = <String, int>{};
  bool _stateAlindi = false;
  int _aktif = 0, _hataToplam = 0, _istek = 0, _stateGet = 0;
  Completer<bool>? _onay2, _onay4;
  Timer? _qrZaman, _genelZaman;

  void _olay(String s) {
    if (olaylar.length < 200) olaylar.add(s);
  }

  void _gec(EslestirmeDurum d) {
    if (_durum.bitti) return;
    _durum = d;
    if (!_durumAkisi.isClosed) _durumAkisi.add(d);
  }

  /// Sunucuyu açar, QR içeriğini hazırlar. Özel ağ yoksa [StateError].
  Future<QrBaglanti> baslat() async {
    final aday = adresler ?? await ozelAdaylar();
    if (aday.isEmpty) {
      throw StateError(
        'Özel bir ağa bağlı değilsin. Wi-Fi ağına bağlan ya da dosya ile senkronu kullan.',
      );
    }
    final cert = _sertifika ??= await OturumSertifikasi.uret(aday);
    final ctx = cert.baglam();
    var port = 0;
    final alinan = <String>[];
    for (final a in aday) {
      try {
        final s = await HttpServer.bindSecure(InternetAddress(a), port, ctx);
        port = s.port;
        _sunucular.add(s);
        alinan.add(a);
        s.listen(_istekGeldi, onError: (_) {});
      } on SocketException {
        // Aynı port bu adreste doluysa adres listeden düşer.
      }
    }
    if (alinan.isEmpty) throw StateError('Eşleştirme sunucusu açılamadı.');
    final rnd = Random.secure();
    _jeton = [
      for (var i = 0; i < jetonBayt; i++)
        rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    qrBitis = DateTime.now().add(ayar.qrOmru);
    qr = QrBaglanti(
      adresler: alinan,
      port: port,
      parmakIzi: cert.parmakIzi,
      jeton: _jeton!,
      bitis: qrBitis!.millisecondsSinceEpoch ~/ 1000,
      ad: adTemizle(sunucuAdi),
    );
    _qrZaman = Timer(ayar.qrOmru, () {
      if (_durum == EslestirmeDurum.bekliyor) _bitir(EslestirmeDurum.sureDoldu);
    });
    _genelZaman = Timer(ayar.oturumEnFazla, () => _bitir(EslestirmeDurum.sureDoldu));
    _olay('Oturum açıldı (${alinan.length} adres).');
    return qr!;
  }

  // -- Arayüzün çağırdıkları ---------------------------------------------------

  /// Onay 2: "bu senin telefonun mu?"
  void baglantiyiOnayla(bool evet) {
    final c = _onay2;
    if (c != null && !c.isCompleted) c.complete(evet);
  }

  /// Onay 4: "telefondan gelen veri uygulansın mı?"
  void birlesmeyiOnayla(bool evet) {
    final c = _onay4;
    if (c != null && !c.isCompleted) c.complete(evet);
  }

  /// Masaüstü İptal. Birleştirme sürüyorsa yok sayılır (veri yarım kalmasın).
  void iptalEt() {
    if (_durum == EslestirmeDurum.isleniyor) return;
    _bitir(EslestirmeDurum.iptal);
  }

  /// Hemen kapatır (pencere/uygulama kapanırken).
  Future<void> kapat() async {
    if (_durum != EslestirmeDurum.isleniyor) _bitir(EslestirmeDurum.iptal);
    _kapatZaman?.cancel();
    await _kapatSunuculari(zorla: true);
  }

  Timer? _kapatZaman;

  void _bitir(EslestirmeDurum d) {
    if (_durum.bitti) return;
    _jeton = _oturum = _oturumIp = null;
    _qrZaman?.cancel();
    _genelZaman?.cancel();
    _gec(d);
    _olay('Oturum bitti: ${d.name}.');
    // Bekleyen onaylar "hayır" ile uyanır; istek yanıtı kendi durumuna bakar.
    for (final c in [_onay2, _onay4]) {
      if (c != null && !c.isCompleted) c.complete(false);
    }
    // Bekleyen bir isteğin yanıtını yazabilmesi için sunucular önce yeni
    // bağlantı almayı bırakır, 2 sn sonra zorla kapanır.
    unawaited(_kapatSunuculari(zorla: false));
    _kapatZaman = Timer(const Duration(seconds: 2), () => _kapatSunuculari(zorla: true));
    if (!_bitti.isCompleted) _bitti.complete(d);
  }

  Future<void> _kapatSunuculari({required bool zorla}) async {
    final l = List.of(_sunucular);
    if (zorla) _sunucular.clear();
    await Future.wait([
      for (final s in l) s.close(force: zorla).then((_) => null).catchError((_) => null),
    ]);
    if (zorla && !_durumAkisi.isClosed) await _durumAkisi.close();
  }

  // -- İstek işleme ------------------------------------------------------------

  Future<void> _sessiz(HttpRequest r) async {
    try {
      (await r.response.detachSocket(writeHeaders: false)).destroy();
    } catch (_) {}
  }

  Future<void> _istekGeldi(HttpRequest r) async {
    final ip = r.connectionInfo?.remoteAddress.address ?? '';
    if (_durum.bitti ||
        (!ayar.loopbackIzinli && !ozelIpv4mu(ip)) ||
        (_ipHata[ip] ?? 0) >= ipBasinaHata) {
      return _sessiz(r);
    }
    if (++_istek > istekEnFazla) {
      await _sessiz(r);
      _bitir(EslestirmeDurum.hata);
      return;
    }
    if ((_ipAktif[ip] ?? 0) >= eszamanliIpBasina || _aktif >= eszamanliToplam) {
      return _hataYaz(r, WifiHata.cokIstek);
    }
    _aktif++;
    _ipAktif[ip] = (_ipAktif[ip] ?? 0) + 1;
    try {
      await _isle(r, ip);
    } catch (_) {
      try {
        await _hataYaz(r, WifiHata.icHata);
      } catch (_) {}
    } finally {
      _aktif--;
      _ipAktif[ip] = (_ipAktif[ip] ?? 1) - 1;
    }
  }

  Future<void> _yaz(HttpRequest r, int kod, Object? govde) async {
    final res = r.response;
    res.statusCode = kod;
    res.persistentConnection = false;
    res.headers
      ..set('Cache-Control', 'no-store')
      ..contentType = ContentType('application', 'json', charset: 'utf-8');
    res.add(govde is Uint8List ? govde : utf8.encode(jsonEncode(govde)));
    await res.close();
  }

  final _okundu = Expando<bool>();

  Future<void> _hataYaz(HttpRequest r, WifiHata h) async {
    final govdeVar = r.contentLength > 0 || r.headers.chunkedTransferEncoding;
    if (!govdeVar || _okundu[r] == true) return _yaz(r, h.http, {'error': h.kod});
    // Okunmamış gövde var (aşırı büyük/yarım): Dart yanıtı gövde bitene kadar
    // tutar. Bağlantıyı devralıp yanıtı elle yazar ve kapatırız; gövde okunmaz.
    final s = await r.response.detachSocket(writeHeaders: false);
    final b = utf8.encode(jsonEncode({'error': h.kod}));
    s.add(ascii.encode('HTTP/1.1 ${h.http} Hata\r\n'
        'Content-Type: application/json; charset=utf-8\r\n'
        'Cache-Control: no-store\r\nConnection: close\r\n'
        'Content-Length: ${b.length}\r\n\r\n'));
    s.add(b);
    await s.flush();
    s.destroy();
  }

  /// 'jeton' | 'oturum' | null
  String? _kimlik(HttpRequest r, String ip) {
    final h = r.headers.value('authorization') ?? '';
    if (!h.startsWith('Bearer ')) return null;
    final t = h.substring(7);
    final j = _jeton, o = _oturum;
    if (j != null && sabitZamanliEsit(t, j)) return 'jeton';
    if (o != null && ip == _oturumIp && sabitZamanliEsit(t, o)) return 'oturum';
    return null;
  }

  Future<void> _isle(HttpRequest r, String ip) async {
    // Kimlik, yola bakmadan önce: bilinmeyen yol da 401 alır.
    final kim = _kimlik(r, ip);
    if (kim == null) {
      _ipHata[ip] = (_ipHata[ip] ?? 0) + 1;
      _olay('Yetkisiz istek ($ip).');
      await _hataYaz(r, WifiHata.yetkisiz);
      if (++_hataToplam >= toplamHata) _bitir(EslestirmeDurum.hata);
      return;
    }
    final yol = r.uri.path, m = r.method;
    final metotlar = switch (yol) {
      '/v1/session' || '/v1/end' => const ['POST'],
      '/v1/state' => const ['GET', 'POST'],
      _ => null,
    };
    if (metotlar == null) return _hataYaz(r, WifiHata.yok);
    if (!metotlar.contains(m)) return _hataYaz(r, WifiHata.metot);

    Uint8List? govde;
    if (m == 'POST') {
      final tip = r.headers.contentType;
      if (tip == null || tip.mimeType != 'application/json') {
        return _hataYaz(r, WifiHata.turHatali);
      }
      final boy = r.contentLength;
      if (boy < 0 || r.headers.chunkedTransferEncoding == true) {
        return _hataYaz(r, WifiHata.uzunlukGerekli);
      }
      final sinir = yol == '/v1/state' ? stateGovdeEnFazla : sessionGovdeEnFazla;
      if (boy > sinir) return _hataYaz(r, WifiHata.cokBuyuk);
      // Sıra yanlışsa gövde okunmadan ret.
      if (!_sirayaUygun(yol, m, kim)) return _hataYaz(r, WifiHata.siraHatali);
      if (yol == '/v1/state') {
        if (_durum != EslestirmeDurum.hazir || _stateAlindi) {
          return _hataYaz(r, WifiHata.mesgul);
        }
        _stateAlindi = true; // eşzamanlı ikinci POST doğrulamaya girmez
      }
      govde = await _oku(r);
      if (govde == null) {
        if (yol == '/v1/state') _stateAlindi = false;
        return _hataYaz(r, WifiHata.sureDoldu);
      }
    } else if (!_sirayaUygun(yol, m, kim)) {
      return _hataYaz(r, WifiHata.siraHatali);
    }

    switch ('$m $yol') {
      case 'POST /v1/session':
        return _session(r, ip, govde!);
      case 'GET /v1/state':
        if (++_stateGet > 2) return _hataYaz(r, WifiHata.siraHatali);
        return _yaz(r, 200, await durumAl());
      case 'POST /v1/state':
        return _stateYukle(r, govde!);
      default: // POST /v1/end
        return _son(r, govde!);
    }
  }

  bool _sirayaUygun(String yol, String m, String kim) {
    switch (yol) {
      case '/v1/session':
        return kim == 'jeton' && _durum == EslestirmeDurum.bekliyor;
      case '/v1/state':
        if (kim != 'oturum') return false;
        return m == 'GET'
            ? _durum == EslestirmeDurum.hazir
            // Onay beklerken ikinci POST doğrulamaya girmeden `mesgul` alır.
            : _durum == EslestirmeDurum.hazir ||
                _durum == EslestirmeDurum.birlesmeOnayi ||
                _durum == EslestirmeDurum.isleniyor;
      default:
        return kim == 'oturum';
    }
  }

  /// Gövdeyi toplam [EslestirmeAyar.govdeOkuma] içinde okur; olmazsa null.
  Future<Uint8List?> _oku(HttpRequest r) async {
    _okundu[r] = true;
    final tampon = BytesBuilder(copy: false);
    final bitti = Completer<bool>();
    final zaman = Timer(ayar.govdeOkuma, () {
      if (!bitti.isCompleted) bitti.complete(false);
    });
    final abone = r.listen(
      tampon.add,
      onDone: () => bitti.isCompleted ? null : bitti.complete(true),
      onError: (_) => bitti.isCompleted ? null : bitti.complete(false),
      cancelOnError: true,
    );
    final tamam = await bitti.future;
    zaman.cancel();
    if (!tamam) {
      _okundu[r] = false; // yarım kaldı: yanıt elle yazılır, bağlantı kapanır
      abone.pause(); // cancel() bağlantıyı yok eder; yanıt elle yazılacak
      return null;
    }
    return tampon.takeBytes();
  }

  Map<String, dynamic>? _json(Uint8List b) {
    try {
      final v = jsonDecode(utf8.decode(b));
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  /// Onayı bekler; süre dolarsa null.
  Future<bool?> _bekle(Completer<bool> c) =>
      c.future.then<bool?>((v) => v).timeout(ayar.onayBekleme, onTimeout: () => null);

  /// Onay sonrası ortak ret/süre/iptal yanıtı; devam edilecekse null döner.
  Future<bool> _onayReddi(HttpRequest r, bool? evet) async {
    if (_durum.bitti) {
      await _hataYaz(r, _durum == EslestirmeDurum.sureDoldu ? WifiHata.sureDoldu : WifiHata.iptal);
      return true;
    }
    if (evet == null) {
      await _hataYaz(r, WifiHata.sureDoldu);
      _bitir(EslestirmeDurum.sureDoldu);
      return true;
    }
    if (!evet) {
      await _hataYaz(r, WifiHata.reddedildi);
      _bitir(EslestirmeDurum.reddedildi);
      return true;
    }
    return false;
  }

  Future<void> _session(HttpRequest r, String ip, Uint8List govde) async {
    _jeton = null; // jeton tek kullanımlık: gövde geçerli olmasa da yanar
    final j = _json(govde);
    final c = j?['client'];
    final ad = c is Map ? c['name'] : null;
    if (j == null || ad is! String || c is! Map || c['app'] != 'habit-tracker-mobile') {
      await _hataYaz(r, WifiHata.istekBozuk);
      _bitir(EslestirmeDurum.hata);
      return;
    }
    if (j['protocol'] != wifiProtokolSurumu ||
        j['sync_version'] is! int ||
        (j['sync_version'] as int) > syncVersion) {
      await _hataYaz(r, WifiHata.protokolSurumu);
      _bitir(EslestirmeDurum.hata);
      return;
    }
    istemci = IstemciBilgisi(adTemizle(ad), ip);
    _onay2 = Completer<bool>();
    _gec(EslestirmeDurum.baglantiOnayi);
    _olay('Bağlantı geldi ($ip), onay bekleniyor.');
    if (await _onayReddi(r, await _bekle(_onay2!))) return;
    final rnd = Random.secure();
    _oturum = base64urlDolgusuz([for (var i = 0; i < oturumBayt; i++) rnd.nextInt(256)]);
    _oturumIp = ip;
    _gec(EslestirmeDurum.hazir);
    _olay('Bağlantı onaylandı.');
    await _yaz(r, 200, {
      'protocol': wifiProtokolSurumu,
      'session': _oturum,
      'server': {'name': adTemizle(sunucuAdi), 'app': 'habit-tracker-desktop', 'version': surum},
      'sync_version': syncVersion,
      'remaining_s': ayar.oturumEnFazla.inSeconds,
    });
  }

  Future<void> _stateYukle(HttpRequest r, Uint8List govde) async {
    final SyncReport onizleme;
    try {
      onizleme = await onizle(govde);
    } on SyncVersionException {
      _stateAlindi = false;
      return _hataYaz(r, WifiHata.senkronSurumu);
    } on SyncException {
      _stateAlindi = false;
      return _hataYaz(r, WifiHata.senkronBozuk);
    }
    if (_durum != EslestirmeDurum.hazir) return _hataYaz(r, WifiHata.iptal);
    ozet = onizleme;
    _onay4 = Completer<bool>();
    _gec(EslestirmeDurum.birlesmeOnayi);
    _olay('Telefondan veri geldi, onay bekleniyor.');
    if (await _onayReddi(r, await _bekle(_onay4!))) return;
    _gec(EslestirmeDurum.isleniyor);
    try {
      await yedekAl();
      sonuc = await uygula(govde);
    } catch (_) {
      await _hataYaz(r, WifiHata.icHata);
      _olay('Birleştirme yapılamadı.');
      return _bitir(EslestirmeDurum.hata);
    }
    await _yaz(r, 200, {'result': 'merged', 'report': raporJson(sonuc!)});
    _olay('Birleştirildi.');
    _bitir(EslestirmeDurum.tamam);
  }

  Future<void> _son(HttpRequest r, Uint8List govde) async {
    final neden = _json(govde)?['reason'];
    if (neden != 'cancel' && neden != 'done') return _hataYaz(r, WifiHata.istekBozuk);
    await _yaz(r, 200, <String, Object?>{});
    // Birleştirme sürerken telefonun vazgeçmesi de yok sayılır.
    if (_durum != EslestirmeDurum.isleniyor) _bitir(EslestirmeDurum.iptal);
  }
}

Map<String, Object> raporJson(SyncReport r) {
  Map<String, int> c(SyncCounts x) =>
      {'added': x.added, 'updated': x.updated, 'deleted': x.deleted, 'skipped': x.skipped};
  return {
    'habit': c(r.habit),
    'entry': c(r.entry),
    'mood': c(r.mood),
    'task': c(r.task),
    'session': c(r.session),
    'setting': c(r.setting),
    'adopted': r.adopted,
  };
}
