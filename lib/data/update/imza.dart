// SHA256SUMS.txt için Ed25519 ayrık imza doğrulaması (saf Dart, pinenacl).
// Zip ile özet dosyası aynı release'ten geldiği için yalnız SHA-256 hesap ele geçirilmesini yakalamaz;
// imza, özel anahtar olmadan üretilemez. Özel anahtar repoda YOK (bkz. docs/guncelleme-imzasi.md).
import 'dart:convert';

import 'package:pinenacl/ed25519.dart';

/// Release'e eklenen ayrık imza varlığının adı (ham 64 bayt).
const imzaVarlikAdi = 'SHA256SUMS.txt.sig';

/// Güncelleme imzasının AÇIK anahtarı (Ed25519, 32 bayt, base64). Gizli değildir.
/// Anahtar değişirse eski sürümler yeni imzayı kabul etmez: önce uygulamaya yeni anahtar girip yayımla.
const guncellemeAcikAnahtari = 'kfIcoLqb+cjhkguHtzKFjn8pYWltOG2r/vF9+WbNX98=';

Uint8List acikAnahtarBayt([String b64 = guncellemeAcikAnahtari]) =>
    base64Decode(b64);

/// [imza] (64 bayt), [mesaj] üzerinde [acikAnahtar]'a göre geçerliyse true. Her bozukluk false döner, atmaz.
bool imzaGecerli(List<int> mesaj, List<int> imza, List<int> acikAnahtar) {
  if (imza.length != 64 || acikAnahtar.length != 32) return false;
  try {
    return VerifyKey(Uint8List.fromList(acikAnahtar)).verify(
      signature: Signature(Uint8List.fromList(imza)),
      message: Uint8List.fromList(mesaj),
    );
  } on Object {
    return false; // pinenacl geçersiz imzada istisna atar
  }
}
