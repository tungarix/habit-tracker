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
}
