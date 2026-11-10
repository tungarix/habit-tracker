/// Oturum başına bellekte kendinden imzalı sertifika. Özel anahtar diske yazılmaz.
/// `basic_utils`'i kullanan tek dosya (docs/wifi-senkron.md A3).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';

import '../sha256.dart';
import 'sozlesme.dart';

class OturumSertifikasi {
  OturumSertifikasi._(this.certPem, this.keyPem, this.der);
  final String certPem;
  final String keyPem;
  final Uint8List der;

  /// DER'in SHA-256'sı, base64url dolgusuz (43 karakter).
  String get parmakIzi => base64urlDolgusuz(sha256(der));

  SecurityContext baglam() => SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(utf8.encode(certPem))
    ..usePrivateKeyBytes(utf8.encode(keyPem));

  /// ECDSA P-256 anahtar + 24 saat geçerli sertifika; SAN = [ipler].
  static Future<OturumSertifikasi> uret(List<String> ipler) =>
      Isolate.run(() => _uret(ipler));
}

OturumSertifikasi _uret(List<String> ipler) {
  final pair = CryptoUtils.generateEcKeyPair();
  final priv = pair.privateKey as ECPrivateKey;
  final pub = pair.publicKey as ECPublicKey;
  final csr = X509Utils.generateEccCsrPem({'CN': 'habit-sync'}, priv, pub, san: ipler);
  final rnd = Random.secure();
  // basic_utils seri numarasını onluk metin olarak ister; 63 bit, sıfırdan büyük.
  final seri = (BigInt.from(rnd.nextInt(1 << 31)) * BigInt.from(1 << 31) + BigInt.from(rnd.nextInt(1 << 31)) + BigInt.one).toString();
  // CRLF temizliği: spike'ta ilk hata buydu.
  final cert = X509Utils.generateSelfSignedCertificate(priv, csr, 1,
          sans: ipler, serialNumber: seri)
      .replaceAll('\r', '');
  final key = CryptoUtils.encodeEcPrivateKeyToPem(priv).replaceAll('\r', '');
  final der = base64.decode(cert
      .split('\n')
      .where((l) => l.isNotEmpty && !l.startsWith('-----'))
      .join());
  return OturumSertifikasi._(cert, key, der);
}
