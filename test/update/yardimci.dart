import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aktenak_habit_tracker/core/sha256.dart';
import 'package:aktenak_habit_tracker/data/update/paket.dart';
import 'package:archive/archive.dart';
import 'package:pinenacl/ed25519.dart';

/// Geçerli bir sahte paket: zorunlu dosyalar + [ek] girdiler.
List<int> zipUret({Map<String, List<int>> ek = const {}, bool zorunlu = true}) {
  final a = Archive();
  if (zorunlu) {
    for (final z in paketZorunluDosyalar) {
      a.add(ArchiveFile.bytes(z, utf8.encode('icerik:$z')));
    }
  }
  ek.forEach((ad, v) => a.add(ArchiveFile.bytes(ad, v)));
  return ZipEncoder().encode(a);
}

String ozet(List<int> b) => onaltilik(sha256(b));

/// Yerel sahte GitHub: `releases/latest`, zip ve SHA256SUMS.txt. Davranış alanları testte değiştirilir.
class SahteGithub {
  SahteGithub(this.zip, {this.surum = '9.9.9'});

  final List<int> zip;
  final String surum;
  late HttpServer sunucu;
  final istekler = <String>[];

  /// SHA256SUMS'a yazılacak özet; null = doğru özet.
  String? yanlisOzet;
  int? beyanEdilenBoyut;
  int durum = 200;
  String? yonlendir;
  Duration yavasla = Duration.zero;
  List<int>?
  zipGovdesi; // sunucunun gerçekte gönderdiği (zip'ten farklı olabilir)

  /// TEST anahtarı (gerçek yayın anahtarı DEĞİL): her sahte sunucu kendi çiftini üretir.
  final imzaAnahtari = SigningKey.generate();
  List<int> get acikAnahtar => imzaAnahtari.verifyKey.asTypedList;

  /// Release'te .sig varlığı listelenir mi / sunucuda 404 mü / imza gövdesi (null = SHA256SUMS'ın doğru imzası).
  bool imzaListede = true;
  bool imza404 = false;
  List<int>? imzaGovdesi;

  /// Sunulan SHA256SUMS metni (null = doğru metin). İmza hep doğru metne atılır: kurcalanmışı yakalamak için.
  String? ozetSunulan;
  String get ozetMetni => '${yanlisOzet ?? ozet(zip)}  $zipAdi\r\n';
  List<int> get dogruImza => imzaAnahtari
      .sign(Uint8List.fromList(utf8.encode(ozetMetni)))
      .signature
      .asTypedList;

  String get taban => 'http://127.0.0.1:${sunucu.port}';
  String get zipAdi => 'aktenak-habit-tracker-v$surum-windows.zip';

  Future<SahteGithub> baslat() async {
    sunucu = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    sunucu.listen((r) async {
      istekler.add(r.uri.path);
      final y = r.response;
      if (yonlendir != null) {
        y.statusCode = 302;
        y.headers.set('location', yonlendir!);
        await y.close();
        return;
      }
      if (r.uri.path.endsWith('/releases/latest')) {
        if (durum != 200) {
          y.statusCode = durum;
          await y.close();
          return;
        }
        y.headers.contentType = ContentType.json;
        y.write(
          jsonEncode({
            'tag_name': 'v$surum',
            'draft': false,
            'prerelease': false,
            'html_url': '$taban/sayfa',
            'assets': [
              {
                'name': zipAdi,
                'size': beyanEdilenBoyut ?? zip.length,
                'browser_download_url': '$taban/dl/$zipAdi',
              },
              {
                'name': 'SHA256SUMS.txt',
                'size': 100,
                'browser_download_url': '$taban/dl/SHA256SUMS.txt',
              },
              if (imzaListede)
                {
                  'name': 'SHA256SUMS.txt.sig',
                  'size': 64,
                  'browser_download_url': '$taban/dl/SHA256SUMS.txt.sig',
                },
            ],
          }),
        );
      } else if (r.uri.path == '/dl/SHA256SUMS.txt') {
        y.write(ozetSunulan ?? ozetMetni);
      } else if (r.uri.path == '/dl/SHA256SUMS.txt.sig') {
        if (imza404) {
          y.statusCode = 404;
        } else {
          y.add(imzaGovdesi ?? dogruImza);
        }
      } else if (r.uri.path == '/dl/$zipAdi') {
        final g = zipGovdesi ?? zip;
        if (yavasla > Duration.zero) {
          y.add(g.sublist(0, g.length ~/ 2));
          await y.flush();
          await Future<void>.delayed(yavasla);
          y.add(g.sublist(g.length ~/ 2));
        } else {
          y.add(g);
        }
      } else {
        y.statusCode = 404;
      }
      try {
        await y.close();
      } on Object {
        // istemci iptal edip koptu
      }
    });
    return this;
  }

  Future<void> kapat() => sunucu.close(force: true);
}
