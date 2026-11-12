import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// windows/runner/main.cpp tek örnek korumasını yapar (C++ olduğu için
/// burada kaynak denetlenir; çalışma davranışı elle iki exe ile denenir).
/// Mobil depo bu testi eşitleme ile alır ama orada Windows runner yoktur.
void main() {
  final mainCpp = File('windows/runner/main.cpp');
  final uygula = File('lib/data/update/uygula.dart');
  final yok = !mainCpp.existsSync() || !uygula.existsSync();

  test('ikinci başlatma mutex ile engellenir ve mevcut pencere öne gelir', () {
    final cpp = mainCpp.readAsStringSync();
    expect(cpp, contains('CreateMutexW'));
    expect(cpp, contains('ERROR_ALREADY_EXISTS'));
    expect(cpp, contains('SetForegroundWindow'));
  }, skip: yok ? 'Windows runner yok' : null);

  test('güncelleme uygulayıcısı denetimden muaf: bayrak Dart ile aynı', () {
    final bayrak = RegExp(r"guncelleBayragi\s*=\s*'([^']+)'")
        .firstMatch(uygula.readAsStringSync())!
        .group(1)!;
    expect(mainCpp.readAsStringSync(), contains('L"$bayrak"'));
  }, skip: yok ? 'Windows runner yok' : null);
}
