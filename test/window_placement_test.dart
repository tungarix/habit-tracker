import 'package:aktenak_habit_tracker/core/window_placement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const primary = ScreenArea(0, 0, 1920, 1040);
  const leftMonitor = ScreenArea(-1920, 0, 1920, 1040);

  test('kaydet / geri oku gidiş-dönüş', () {
    const p = WindowPlacement(
      x: 100,
      y: 50,
      width: 1280,
      height: 720,
      maximized: true,
    );
    final back = WindowPlacement.decode(p.encode())!;
    expect(back.x, 100);
    expect(back.y, 50);
    expect(back.width, 1280);
    expect(back.height, 720);
    expect(back.maximized, isTrue);
  });

  test('bozuk ya da saçma kayıt null', () {
    expect(WindowPlacement.decode(null), isNull);
    expect(WindowPlacement.decode(''), isNull);
    expect(WindowPlacement.decode('1,2,3'), isNull);
    expect(WindowPlacement.decode('a,b,c,d,0'), isNull);
    // Simge durumundaki pencereden okunan değerler (-32000, 160x28 gibi).
    expect(WindowPlacement.decode('-32000,-32000,160,28,0'), isNull);
  });

  test('ana ekrandaki pencere ulaşılabilir', () {
    const p = WindowPlacement(x: 100, y: 50, width: 1280, height: 720);
    expect(p.isReachableOn([primary]), isTrue);
  });

  test('sol monitör çıkarıldıysa oradaki pencere ulaşılamaz', () {
    const p = WindowPlacement(x: -1500, y: 100, width: 1200, height: 700);
    expect(p.isReachableOn([leftMonitor, primary]), isTrue);
    expect(p.isReachableOn([primary]), isFalse);
  });

  test('başlık çubuğu ekranın altına düşmüşse ulaşılamaz', () {
    const p = WindowPlacement(x: 100, y: 1100, width: 800, height: 600);
    expect(p.isReachableOn([primary]), isFalse);
  });

  test('ekran listesi bilinmiyorsa güvenme', () {
    const p = WindowPlacement(x: 100, y: 50, width: 1280, height: 720);
    expect(p.isReachableOn(const []), isFalse);
  });
}
