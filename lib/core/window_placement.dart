/// Pencerenin kayıtlı yeri ve boyutu — saf mantık, ekran/pencere API'si yok.
library;

/// Bir ekranın kullanılabilir alanı (görev çubuğu hariç), mantıksal piksel.
class ScreenArea {
  final double x, y, width, height;
  const ScreenArea(this.x, this.y, this.width, this.height);

  bool contains(double px, double py) =>
      px >= x && px < x + width && py >= y && py < y + height;
}

class WindowPlacement {
  final double x, y, width, height;
  final bool maximized;

  const WindowPlacement({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.maximized = false,
  });

  /// Bundan küçük kayıt bozuk sayılır; gizli/simge durumundaki pencereden
  /// okunan değerler böyle saçma boyutlar verebiliyor.
  static const minWidth = 400.0;
  static const minHeight = 300.0;

  /// `x,y,w,h,m` biçimi; bozuk ya da eksik metin null döner.
  static WindowPlacement? decode(String? raw) {
    if (raw == null) return null;
    final parts = raw.split(',');
    if (parts.length != 5) return null;
    final n = parts.take(4).map(double.tryParse).toList();
    if (n.any((v) => v == null || v.isNaN || v.isInfinite)) return null;
    final p = WindowPlacement(
      x: n[0]!,
      y: n[1]!,
      width: n[2]!,
      height: n[3]!,
      maximized: parts[4] == '1',
    );
    if (p.width < minWidth || p.height < minHeight) return null;
    return p;
  }

  String encode() => [
    x.round(),
    y.round(),
    width.round(),
    height.round(),
    maximized ? 1 : 0,
  ].join(',');

  /// Başlık çubuğu bir ekranda kalıyor mu? Kayıttan bu yana monitör
  /// çıkarıldıysa ya da çözünürlük değiştiyse pencere ulaşılamaz bir yere
  /// açılmasın diye bakılır. Ekran listesi boşsa (bilinmiyorsa) güvenme.
  bool isReachableOn(List<ScreenArea> screens) {
    final titleX = x + width / 2;
    final titleY = y + 16;
    return screens.any((s) => s.contains(titleX, titleY));
  }
}
