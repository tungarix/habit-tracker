import 'package:flutter_test/flutter_test.dart';

import 'sync_harness.dart';

/// Sıralama ekranı tüm alışkanlıkların id'lerini yazar; yeri değişmeyen satırın
/// updated_at'i oynamamalı (aksi halde eşitlemede başka cihazdaki düzenlemeyi ezer).
void main() {
  test('reorderHabits yalnız yeri değişen alışkanlığın damgasını değiştirir', () async {
    final d = Dev('masaüstü');
    addTearDown(d.close);
    final a = await d.habit('A', stamp: 10);
    final b = await d.habit('B', stamp: 10);
    final c = await d.habit('C', stamp: 10);
    for (final (id, sira) in [(a, 0), (b, 1), (c, 2)]) {
      await d.sql('UPDATE habits SET sort_order = ? WHERE id = ?', [sira, id]);
    }
    await d.sql('UPDATE habits SET updated_at = ?', [at(10)]); // sıra kurulumu damga bırakmasın

    await d.db.reorderHabits([a, c, b]); // A yerinde, B ve C yer değiştirir

    final h = {for (final x in await d.db.getAllHabits()) x.id: x};
    expect(h[a]!.updatedAt, at(10), reason: 'yeri değişmeyen satır damgasını korur');
    expect(h[a]!.sortOrder, 0);
    expect(h[c]!.sortOrder, 1);
    expect(h[b]!.sortOrder, 2);
    expect(h[c]!.updatedAt, isNot(at(10)));
    expect(h[b]!.updatedAt, isNot(at(10)));
  });
}
