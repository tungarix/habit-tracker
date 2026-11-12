import 'dart:io';

import 'package:aktenak_habit_tracker/data/update/uygula.dart';
import 'package:flutter_test/flutter_test.dart';

/// windows/runner/main.cpp tek örnek korumasını yapar (C++ olduğu için
/// burada kaynak denetlenir; çalışma davranışı elle iki exe ile denenir).
void main() {
  final cpp = File('windows/runner/main.cpp').readAsStringSync();

  test('ikinci başlatma mutex ile engellenir ve mevcut pencere öne gelir', () {
    expect(cpp, contains('CreateMutexW'));
    expect(cpp, contains('ERROR_ALREADY_EXISTS'));
    expect(cpp, contains('SetForegroundWindow'));
  });

  test('güncelleme uygulayıcısı denetimden muaf: bayrak Dart ile aynı', () {
    expect(cpp, contains('L"$guncelleBayragi"'));
  });
}
