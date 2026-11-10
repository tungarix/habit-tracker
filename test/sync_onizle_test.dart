import 'dart:convert';
import 'dart:typed_data';

import 'package:aktenak_habit_tracker/data/sync/sync_export.dart';
import 'package:aktenak_habit_tracker/data/sync/sync_import.dart';
import 'package:aktenak_habit_tracker/data/sync/sync_format.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sync_harness.dart';

/// `previewSyncBytes`: gerçek birleştirmeyle aynı sayılar, sıfır yan etki.
void main() {
  test('önizleme veriyi ve silinenler izini değiştirmez, rapor gerçekle aynı', () async {
    final pc = Dev('pc');
    final phone = Dev('phone');
    addTearDown(pc.close);
    addTearDown(phone.close);
    await pc.habit('Yürüyüş', stamp: 1);
    await phone.habit('Kitap', stamp: 5);
    await phone.habit('Su', stamp: 5);
    await phone.deleteHabit('Su', 9);
    await pc.habit('Su', stamp: 2, created: 0);
    final bytes = (await exportSyncBytes(phone));

    final before = await pc.state();
    final tombsBefore = await pc.count('silinenler');
    final habitEvents = <String>[];
    final sub = pc.db.select(pc.db.habits).watch().listen((r) => habitEvents.add(r.map((h) => h.name).join(',')));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final baseline = habitEvents.length;

    final preview = await previewSyncBytes(pc.db, bytes);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(await pc.state(), before);
    expect(await pc.count('silinenler'), tombsBefore);
    // drift, geri sarılan işlemden sonra da yeniden sorgular (aynı veriyle yeniden
    // yayar); önemli olan hiçbir izleyicinin önizleme verisini görmemesi.
    expect(habitEvents.skip(baseline).toSet().difference(habitEvents.take(baseline).toSet()), isEmpty,
        reason: 'olaylar: $habitEvents');
    await sub.cancel();

    final real = await importSyncBytes(pc.db, bytes);
    expect(preview.added, real.added);
    expect(preview.updated, real.updated);
    expect(preview.deleted, real.deleted);
    expect(preview.skipped, real.skipped);
    expect(real.changed, isTrue);
    expect(await pc.state(), isNot(before));
  });

  test('bozuk dosya SyncException fırlatır', () async {
    final pc = Dev('pc');
    addTearDown(pc.close);
    expect(() => previewSyncBytes(pc.db, Uint8List.fromList([1, 2, 3])),
        throwsA(isA<SyncException>()));
  });
}

Future<Uint8List> exportSyncBytes(Dev d) async =>
    Uint8List.fromList(utf8.encode(await exportSync(d.db, deviceName: d.name)));
