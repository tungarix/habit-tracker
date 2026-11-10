import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aktenak_habit_tracker/core/sha256.dart';
import 'package:aktenak_habit_tracker/core/wifi_sync/sertifika.dart';
import 'package:aktenak_habit_tracker/core/wifi_sync/sozlesme.dart';
import 'package:aktenak_habit_tracker/data/sync/sync_export.dart';

import 'sync_harness.dart';

/// Gerçek HttpServer, 127.0.0.1 (yalnız testte loopback izinli), gerçek
/// pinleyen istemci. Gerçek LAN, güvenlik duvarı ve Android bunu kanıtlamaz.
class Yanit {
  Yanit(this.kod, this.govde);
  final int kod;
  final String govde;
  Map<String, dynamic> get json => jsonDecode(govde) as Map<String, dynamic>;
  String get hata => json['error'] as String;
}

late OturumSertifikasi testCert;
final tumYanitlar = <String>[];

Future<Yanit> istek(
  QrBaglanti q,
  String metot,
  String yol, {
  String? bearer,
  Object? govde,
  String? tip = 'application/json',
  String? pin,
}) async {
  final c = HttpClient(context: SecurityContext(withTrustedRoots: false))
    ..findProxy = ((_) => 'DIRECT')
    ..badCertificateCallback =
        (cert, host, port) => base64urlDolgusuz(sha256(cert.der)) == (pin ?? q.parmakIzi);
  try {
    final r = await c.openUrl(metot, Uri.parse('https://127.0.0.1:${q.port}$yol'));
    if (bearer != null) r.headers.set('Authorization', 'Bearer $bearer');
    if (tip != null) r.headers.set('Content-Type', tip);
    if (govde != null) {
      final b = govde is Uint8List ? govde : utf8.encode(govde is String ? govde : jsonEncode(govde));
      r.contentLength = b.length;
      r.add(b);
    }
    final res = await r.close();
    final text = await utf8.decodeStream(res);
    tumYanitlar.add(text);
    return Yanit(res.statusCode, text);
  } finally {
    c.close(force: true);
  }
}

/// Başlıkları elle yazılmış istek (Content-Length yok/yalan gibi durumlar için).
Future<String> ham(QrBaglanti q, String metin, {Duration bekle = Duration.zero}) async {
  final s = await SecureSocket.connect('127.0.0.1', q.port,
      onBadCertificate: (c) => base64urlDolgusuz(sha256(c.der)) == q.parmakIzi);
  s.write(metin);
  await s.flush();
  if (bekle > Duration.zero) await Future<void>.delayed(bekle);
  // Gövdesi eksik istekte Dart bağlantıyı hemen kapatmaz; yanıt gelince yeter.
  final tampon = <int>[];
  final sub = s.listen(tampon.addAll, onError: (_) {});
  await Future<void>.delayed(const Duration(milliseconds: 700));
  await sub.cancel();
  s.destroy();
  return utf8.decode(tampon, allowMalformed: true);
}

final oturumGovdesi = {
  'protocol': 1,
  'client': {'name': 'Pixel 7', 'app': 'habit-tracker-mobile', 'version': '0.3.0'},
  'sync_version': 1,
};

Future<Uint8List> telefonDosyasi() async {
  final phone = Dev('phone');
  await phone.habit('Kitap', stamp: 5);
  final b = Uint8List.fromList(utf8.encode(await exportSync(phone.db, deviceName: 'Pixel 7')));
  await phone.close();
  return b;
}

