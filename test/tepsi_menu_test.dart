import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// nativeapi'de sağ tık menüsü varsayılan olarak kapalıdır (ContextMenuTrigger.none);
/// açılmazsa tepsideki "Çıkış" hiç görünmez. Native taraf testte çalışmadığından kaynak denetlenir.
void main() {
  final kaynak = File('lib/shared/desktop_integration.dart');

  test('tepsi simgesi sağ tıkta menüyü açar (Çıkış erişilebilir)', () {
    expect(
      kaynak.readAsStringSync(),
      contains('setContextMenuTrigger(native.ContextMenuTrigger.rightClicked)'),
    );
  }, skip: kaynak.existsSync() ? null : 'masaüstü entegrasyonu yok');

  test('Çıkış beklemesiz sonlanır (menü döngüsünden gelen tıkta await takılır)', () {
    final s = kaynak.readAsStringSync();
    final govde = RegExp(r'Future<void> quit\(\) async \{(.*?)\n  \}', dotAll: true)
        .firstMatch(s)!
        .group(1)!;
    expect(govde, contains('Process.killPid(pid'));
    expect(govde, isNot(contains('await')));
  }, skip: kaynak.existsSync() ? null : 'masaüstü entegrasyonu yok');

  test('Çıkış, süreci öldürmeden önce tepsi simgesini kaldırır (hayalet simge kalmasın)', () {
    final s = kaynak.readAsStringSync();
    final govde = RegExp(r'Future<void> quit\(\) async \{(.*?)\n  \}', dotAll: true)
        .firstMatch(s)!
        .group(1)!;
    final kaldir = govde.indexOf('_trayIcon?.setVisible(false)');
    expect(kaldir, isNonNegative);
    expect(kaldir, lessThan(govde.indexOf('Process.killPid(pid')));
  }, skip: kaynak.existsSync() ? null : 'masaüstü entegrasyonu yok');
}
