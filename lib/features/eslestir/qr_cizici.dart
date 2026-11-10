import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

/// Metni QR olarak çizer. Renkler tema yerine sabit siyah/beyaz: tarayıcı
/// karşıtlığa bakar, koyu temada ters QR okunmayabilir. Çevresinde 4 modül
/// sessiz bölge bırakılır.
class QrCizici extends StatelessWidget {
  const QrCizici({super.key, required this.metin, this.boyut = 240});
  final String metin;
  final double boyut;

  @override
  Widget build(BuildContext context) {
    final img = QrImage(
      QrCode(payload: QrPayload.fromString(metin), errorCorrectLevel: QrErrorCorrectLevel.medium),
    );
    return Semantics(
      label: 'Eşleştirme QR kodu, telefonla tara; yazılı bağlantı aşağıdadır',
      image: true,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: boyut,
          child: CustomPaint(painter: _QrBoyaci(img)),
        ),
      ),
    );
  }
}

class _QrBoyaci extends CustomPainter {
  _QrBoyaci(this.img);
  final QrImage img;

  @override
  void paint(Canvas canvas, Size size) {
    const sessiz = 4;
    final n = img.moduleCount;
    final hucre = size.width / (n + 2 * sessiz);
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final kalem = Paint()..color = Colors.black;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (img.isDark(y, x)) {
          // +0.5 piksel taşma: ince beyaz çizgi oluşmasın.
          canvas.drawRect(
            Rect.fromLTWH((x + sessiz) * hucre, (y + sessiz) * hucre, hucre + 0.5, hucre + 0.5),
            kalem,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrBoyaci old) => old.img != img;
}
