import 'dart:convert';

import 'package:aktenak_habit_tracker/core/constants.dart';
import 'package:aktenak_habit_tracker/core/enums.dart';
import 'package:aktenak_habit_tracker/data/database/database.dart';
import 'package:aktenak_habit_tracker/data/repositories/backup_repository.dart';
import 'package:aktenak_habit_tracker/data/sync/sync_export.dart';
import 'package:aktenak_habit_tracker/data/sync/sync_format.dart';
import 'package:aktenak_habit_tracker/data/sync/sync_import.dart';
import 'package:aktenak_habit_tracker/data/sync/sync_parse.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'sync_harness.dart';

/// `.habitsync` end to end: two devices, one file at a time (docs/senkron.md).
///
/// Scenarios a-f are the Takvim ones (docs of the other app) adapted to this
/// data; "ek 1-4" are this app's own (first match after separate upgrades,
/// cleared cells, restore from backup, different day-start hours).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Dev d; // desktop
  late Dev m; // mobile
  setUp(() {
    d = Dev('masaüstü');
    m = Dev('telefon');
  });
  tearDown(() async {
    await d.close();
    await m.close();
  });

  /// Both devices hold the same state.
  Future<void> expectEqual() async => expect(await m.state(), await d.state());

  /// Rich data: every kind of record on [dev].
  Future<void> seed(Dev dev, {int base = 0}) async {
    await dev.habit('Kitap', stamp: base + 10, created: base + 1);
    await dev.habit('Adım', stamp: base + 10, created: base + 2, kind: 'count', target: 10000);
    await dev.cell('Kitap', '2026-05-01', EntryStatus.done, base + 20);
    await dev.cell('Kitap', '2026-05-02', EntryStatus.missed, base + 20);
    await dev.cell('Adım', '2026-05-01', EntryStatus.done, base + 20, amount: 12000);
    await dev.mood('2026-05-01', 4, base + 20, note: 'iyi gün');
    await dev.task('Rapor', stamp: base + 10, created: base + 3);
    await dev.session(base + 100, 1500, taskTitle: 'Rapor', stamp: base + 30);
    await dev.session(base + 3000, 300, kind: 'break', stamp: base + 30);
  }

  // ===========================================================================
  group('biçim ve doğrulama', () {
    test('dışa aktar -> boş cihaza içe aktar: aynı durum, ikinci içe aktarma değişiklik yok',
        () async {
      await seed(d);
      final first = await sync(d, m);
      expect(first.added, greaterThan(0));
      expect(first.changed, isTrue);
      await expectEqual();

      final again = await sync(d, m);
      expect(again.changed, isFalse);
      expect(again.summary(), contains('zaten güncel'));
      await expectEqual();
    });

    test('dosya UTF-8 JSON, sabit genişlikli UTC zamanlar, cihaza özel ayar yok', () async {
      await seed(d);
      await d.db.setSetting(AppConstants.themeModeKey, 'dark');
      await d.db.setSetting(AppConstants.reminderHourKey, '21');
      await d.setDayStart(3, 50);
      final doc = jsonDecode(await exportSync(d.db)) as Map<String, dynamic>;
      expect(doc['format'], 'habit-sync');
      expect(doc['version'], 1);
      expect(doc['settings'].keys, ['day_start_hour']);
      final timeRe = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$');
      for (final h in doc['habits'] as List) {
        expect(timeRe.hasMatch(h['created_at']), isTrue);
        expect(timeRe.hasMatch(h['updated_at']), isTrue);
      }
      expect(jsonEncode(doc), isNot(contains('dark')));
    });

    Future<String> good() async {
      await seed(d);
      return exportSync(d.db);
    }

    Future<void> expectRejected(String text, {Matcher? message}) async {
      final before = await m.state();
      await expectLater(
        importSyncText(m.db, text),
        throwsA(isA<SyncException>().having((e) => e.message, 'message', message ?? isNotEmpty)),
      );
      expect(await m.state(), before, reason: 'a rejected file must change nothing');
    }

    test('bozuk dosyalar reddedilir ve veri değişmez', () async {
      await seed(m, base: 500); // there is something to protect
      final base = jsonDecode(await good()) as Map<String, dynamic>;

      Future<void> mutated(void Function(Map<String, dynamic>) edit, String why) async {
        final copy = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
        edit(copy);
        await expectRejected(jsonEncode(copy), message: contains('geçersiz'));
        // keep `why` visible in failures
        expect(why, isNotEmpty);
      }

      await expectRejected('{', message: contains('JSON'));
      await expectRejected('[]', message: contains('nesnesi'));
      await expectRejected('{"format":"baska","version":1}', message: contains('senkron dosyası değil'));
      await expectRejected('{"format":"habit-sync","version":"1"}');
      await expectRejected('{"format":"habit-sync","version":2}', message: contains('güncelle'));
      await mutated((j) => (j['habits'] as List)[0]['uid'] = 'a b', 'uid boşluk');
      await mutated((j) => (j['habits'] as List)[1]['uid'] = (j['habits'] as List)[0]['uid'], 'çift uid');
      await mutated((j) => (j['habits'] as List)[0]['name'] = '', 'boş ad');
      await mutated((j) => (j['habits'] as List)[0]['name'] = 'x' * 101, 'uzun ad');
      await mutated((j) => (j['habits'] as List)[0]['kind'] = 'sayac', 'tür');
      await mutated((j) => (j['habits'] as List)[0]['target'] = 0, 'hedef');
      await mutated((j) => (j['habits'] as List)[0]['color_value'] = -1, 'renk');
      await mutated((j) => (j['habits'] as List)[0]['scheduled_weekdays'] = '8', 'gün');
      await mutated((j) => (j['habits'] as List)[0]['updated_at'] = '2026-05-01 10:00:00', 'zaman biçimi');
      await mutated((j) => (j['habits'] as List)[0]['updated_at'] = '2026-02-31T10:00:00Z', 'olmayan gün');
      await mutated((j) => (j['habits'] as List)[0]['created_at'] = null, 'eksik zaman');
      await mutated((j) => (j['entries'] as List)[0]['date'] = '2026-13-01', 'ay');
      await mutated((j) => (j['entries'] as List)[0]['status'] = 'x', 'durum');
      await mutated((j) => (j['entries'] as List)[0]['value'] = 1.5, 'ondalık');
      await mutated((j) => (j['entries'] as List).add((j['entries'] as List)[0]), 'çift hücre');
      await mutated((j) => (j['moods'] as List)[0]['mood'] = 6, 'mood');
      await mutated((j) => (j['tasks'] as List)[0]['status'] = 'bitti', 'görev durumu');
      await mutated((j) => (j['tasks'] as List)[0]['priority'] = 3, 'öncelik');
      await mutated((j) => (j['sessions'] as List)[0]['duration_s'] = -1, 'süre');
      await mutated((j) => (j['sessions'] as List)[0]['task_uid'] = 'x y', 'task_uid');
      await mutated((j) => j['deleted'] = [{'kind': 'habit', 'key': '!', 'deleted_at': '2026-05-01T00:00:00Z'}], 'silinen anahtar');
      await mutated((j) => j['deleted'] = [{'kind': 'entry', 'key': 'abc', 'deleted_at': '2026-05-01T00:00:00Z'}], 'hücre anahtarı');
      await mutated((j) => j['habits'] = {'a': 1}, 'dizi değil');
      await mutated((j) => j['settings'] = {'day_start_hour': {'value': 13, 'updated_at': '2026-05-01T00:00:00Z'}}, 'gün başlangıcı');
      // The last record is the bad one: earlier good ones must not stick.
      await mutated((j) => (j['sessions'] as List).last['kind'] = 'x', 'sondaki kayıt');
    });

    test('sınırlar: dosya boyutu, kayıt sayısı, JSON derinliği, metin uzunluğu', () async {
      expect(
        () => importSyncBytes(m.db, Uint8List(syncMaxFileBytes + 1)),
        throwsA(isA<SyncException>().having((e) => e.message, 'm', contains('çok büyük'))),
      );
      final many = '{"format":"habit-sync","version":1,"moods":[${List.filled(syncMaxRecords + 1, '{}').join(',')}]}';
      await expectRejected(many, message: contains('en çok $syncMaxRecords kayıt'));
      // Exactly at the limit passes the count check (the records then fail on content).
      final atLimit = '{"format":"habit-sync","version":1,"moods":[${List.filled(syncMaxRecords, '{}').join(',')}]}';
      await expectRejected(atLimit, message: isNot(contains('kayıt olabilir')));

      final deep = '{"format":"habit-sync","version":1,"x":${'[' * (syncMaxJsonDepth + 1)}${']' * (syncMaxJsonDepth + 1)}}';
      await expectRejected(deep, message: contains('iç içe'));
      // A deep structure inside a string is just text.
      final text = jsonEncode({
        'format': 'habit-sync',
        'version': 1,
        'x': '[' * 500,
      });
      expect((await importSyncText(m.db, text)).changed, isFalse);

      final longNote = jsonDecode(await good()) as Map<String, dynamic>;
      (longNote['moods'] as List)[0]['note'] = 'n' * (syncMaxTextLength + 1);
      await expectRejected(jsonEncode(longNote));
      (longNote['moods'] as List)[0]['note'] = 'n' * syncMaxTextLength;
      expect((await importSyncText(m.db, jsonEncode(longNote))).added, greaterThan(0));
    });

    test('gelecek tarihli updated_at / deleted_at reddedilir, veri değişmez', () async {
      await seed(m, base: 500);
      final base = jsonDecode(await good()) as Map<String, dynamic>;
      Future<void> future(void Function(Map<String, dynamic>) edit) async {
        final copy = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
        edit(copy);
        await expectRejected(jsonEncode(copy), message: contains('gelecekte'));
      }

      const far = '2099-01-01T00:00:00Z';
      await future((j) => (j['habits'] as List)[0]['updated_at'] = far);
      await future((j) => (j['entries'] as List)[0]['updated_at'] = far);
      await future((j) => (j['moods'] as List)[0]['updated_at'] = far);
      await future((j) => (j['tasks'] as List)[0]['updated_at'] = far);
      await future((j) => (j['sessions'] as List)[0]['updated_at'] = far);
      await future((j) => j['settings'] = {'day_start_hour': {'value': 3, 'updated_at': far}});
      await future((j) => j['deleted'] = [
            {'kind': 'habit', 'key': 'abc', 'deleted_at': far},
          ]);
    });

    test('gelecek sınırı: şimdi + 1 gün kabul, bir saniye fazlası red', () async {
      final doc = jsonDecode(await good()) as Map<String, dynamic>;
      // The exported stamps are real "now" ones, so pin the clock to the present.
      final secs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final now = DateTime.fromMillisecondsSinceEpoch(secs * 1000, isUtc: true);
      (doc['habits'] as List)[0]['updated_at'] = syncTime(secs + syncMaxFutureSecs);
      final ok = Uint8List.fromList(utf8.encode(jsonEncode(doc)));
      expect(() => parseSync(ok, now: now), returnsNormally);
      (doc['habits'] as List)[0]['updated_at'] = syncTime(secs + syncMaxFutureSecs + 1);
      final bad = Uint8List.fromList(utf8.encode(jsonEncode(doc)));
      expect(() => parseSync(bad, now: now), throwsA(isA<SyncException>()));
    });

    test('tür başına sınır: alışkanlık ve görev', () async {
      String many(String key, int n) =>
          '{"format":"habit-sync","version":1,"$key":[${List.filled(n, '{}').join(',')}]}';
      await expectRejected(many('habits', syncMaxHabits + 1), message: contains('en çok $syncMaxHabits alışkanlık'));
      await expectRejected(many('tasks', syncMaxTasks + 1), message: contains('en çok $syncMaxTasks görev'));
      // At the cap the count check passes (the empty records then fail on content).
      await expectRejected(many('habits', syncMaxHabits), message: isNot(contains('alışkanlık olabilir')));
    });

    test('BOM ve bilinmeyen alanlar kabul edilir (ileri uyum)', () async {
      final doc = jsonDecode(await good()) as Map<String, dynamic>;
      doc['gelecek'] = {'x': 1};
      (doc['habits'] as List)[0]['yeni_alan'] = true;
      final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(jsonEncode(doc))]);
      final r = await importSyncBytes(m.db, bytes);
      expect(r.added, greaterThan(0));
    });
  });

  // ===========================================================================
  group('senaryo a: masaüstünde başla, telefonda değiştir, geri getir', () {
    test('iki yönlü, sonunda eşit', () async {
      await seed(d);
      await sync(d, m);
      await expectEqual();

      // On the phone: edit, delete, add.
      await m.editHabit('Kitap', 200, rename: 'Kitap okuma');
      await m.cell('Kitap okuma', '2026-05-02', EntryStatus.done, 210);
      await m.clearCell('Adım', '2026-05-01', 220);
      await m.deleteTask('Rapor', 230);
      await m.habit('Yürüyüş', stamp: 240, created: 240);
      await m.cell('Yürüyüş', '2026-05-03', EntryStatus.done, 250);
      await m.mood('2026-05-02', 2, 250);
      await m.session(9000, 600, stamp: 260);

      final back = await sync(m, d);
      expect(back.habit.added, 1);
      expect(back.habit.updated, 1);
      expect(back.task.deleted, 1);
      await expectEqual();
      expect(await d.count('tasks'), 0);
      // The session lost its task but is still there.
      expect(await d.count('focus_sessions'), 3);
      expect((await d.db.getAllSessions()).where((s) => s.taskId != null), isEmpty);
    });
  });

  // ===========================================================================
  group('senaryo b: son yazan kazanır', () {
    for (final mobileLast in [true, false]) {
      for (final order in ['dm', 'md']) {
        test('düzenle/düzenle: ${mobileLast ? 'telefon' : 'masaüstü'} sonra, sıra $order', () async {
          await seed(d);
          await sync(d, m);
          await d.editHabit('Kitap', mobileLast ? 100 : 200, rename: 'Kitap D');
          await m.editHabit('Kitap', mobileLast ? 200 : 100, rename: 'Kitap M');
          if (order == 'dm') {
            await sync(d, m);
            await sync(m, d);
          } else {
            await sync(m, d);
            await sync(d, m);
          }
          await settle(d, m);
          await expectEqual();
          expect((await d.db.getAllHabits()).map((h) => h.name),
              contains(mobileLast ? 'Kitap M' : 'Kitap D'));
          expect(await d.count('habits'), 2);
        });
      }
    }

    for (final deleteWins in [true, false]) {
      for (final mobileDeletes in [true, false]) {
        test('sil/düzenle: silme ${deleteWins ? 'yeni' : 'eski'}, silen ${mobileDeletes ? 'telefon' : 'masaüstü'}',
            () async {
          await seed(d);
          await sync(d, m);
          final deleter = mobileDeletes ? m : d;
          final editor = mobileDeletes ? d : m;
          await deleter.deleteTask('Rapor', deleteWins ? 300 : 100);
          await editor.editTask('Rapor', deleteWins ? 100 : 300, status: 'done');
          await settle(d, m);
          await expectEqual();
          expect(await d.count('tasks'), deleteWins ? 0 : 1);
        });
      }
    }

    test('eşit damga: kayıt silinmez (veri kaybetme)', () async {
      await seed(d);
      await sync(d, m);
      await d.deleteTask('Rapor', 500);
      await m.editTask('Rapor', 500, status: 'doing');
      await settle(d, m);
      await expectEqual();
      expect(await d.count('tasks'), 1);
    });

    test('alışkanlık silme hücreleri götürür, telefonda yeni hücre varsa alışkanlık canlanır', () async {
      await seed(d);
      await sync(d, m);
      await d.deleteHabit('Adım', 300);
      await m.cell('Adım', '2026-05-09', EntryStatus.done, 400);
      await settle(d, m);
      await expectEqual();
      // Cell is newer than the delete but the habit record itself is older:
      // the habit stays deleted, the orphan cell is dropped.
      expect(await d.count('habits'), 1);
      expect(await m.count('habit_entries'), await d.count('habit_entries'));

      // Habit edited after the delete: it comes back, with its cells.
      await d.deleteHabit('Kitap', 500);
      await m.editHabit('Kitap', 600, rename: 'Kitap geri');
      await settle(d, m);
      await expectEqual();
      expect(await d.count('habits'), 1);
      expect(await d.count('habit_entries'), 2);
    });

    test('görev silinince seansı kalır, görevi boşalır; iki tarafta da', () async {
      await seed(d);
      await sync(d, m);
      await m.deleteTask('Rapor', 300);
      await settle(d, m);
      await expectEqual();
      expect((await d.db.getAllSessions()).where((s) => s.taskId != null), isEmpty);
      expect(await d.count('focus_sessions'), 2);
    });
  });

  // ===========================================================================
  group('senaryo c: ilk eşleştirme (uid yoksa ad + oluşturma saniyesi)', () {
    test('aynı alışkanlık iki cihazda ayrı oluşturulmuş: ikilenmez', () async {
      await d.habit('Kitap', stamp: 10, created: 5);
      await m.habit('Kitap', stamp: 10, created: 5);
      await d.task('Rapor', stamp: 10, created: 6);
      await m.task('Rapor', stamp: 10, created: 6);
      await d.session(100, 1500, stamp: 10);
      await m.session(100, 1500, stamp: 10);
      expect(await d.uidOfHabit('Kitap'), isNot(await m.uidOfHabit('Kitap')));

      final r = await sync(d, m);
      expect(r.adopted, 3);
      expect(r.habit.added + r.task.added + r.session.added, 0);
      await settle(d, m);
      await expectEqual();
      expect(await m.count('habits'), 1);
      expect(await m.count('tasks'), 1);
      expect(await m.count('focus_sessions'), 1);
    });

    test('adı aynı ama oluşturma saati farklı: iki ayrı alışkanlık', () async {
      await d.habit('Kitap', stamp: 10, created: 5);
      await m.habit('Kitap', stamp: 10, created: 500);
      await settle(d, m);
      await expectEqual();
      expect(await d.count('habits'), 2);
    });

    test('benimsenen alışkanlığın hücreleri bağlı kalır, yeniden adlandırma sürer', () async {
      await d.habit('Kitap', stamp: 10, created: 5);
      await m.habit('Kitap', stamp: 10, created: 5);
      await d.cell('Kitap', '2026-05-01', EntryStatus.done, 20);
      await m.cell('Kitap', '2026-05-02', EntryStatus.done, 20);
      await settle(d, m);
      await expectEqual();
      expect(await d.count('habit_entries'), 2);
      await d.editHabit('Kitap', 100, rename: 'Okuma');
      await settle(d, m);
      await expectEqual();
      expect((await m.db.getAllHabits()).single.name, 'Okuma');
    });
  });

  // ===========================================================================
  group('senaryo d: idempotans, ping-pong, silme yankısı', () {
    test('aynı dosya iki kez, ping-pong sonrası da değişiklik yok', () async {
      await seed(d);
      await seed(m, base: 1000);
      final file = await exportSync(d.db);
      final r1 = await importSyncText(m.db, file);
      final stateAfter = await m.state();
      final r2 = await importSyncText(m.db, file);
      expect(r1.changed, isTrue);
      expect(r2.changed, isFalse);
      expect(await m.state(), stateAfter);

      await settle(d, m);
      final settled = await d.state();
      expect(await sync(d, m).then((r) => r.changed), isFalse);
      expect(await sync(m, d).then((r) => r.changed), isFalse);
      expect(await d.state(), settled);
      await expectEqual();
    });

    test('silme yankılanmaz: silinen kayıt geri gelmez, silme zamanı korunur', () async {
      await seed(d);
      await sync(d, m);
      await d.deleteTask('Rapor', 300);
      await d.clearCell('Kitap', '2026-05-02', 310);
      await d.clearMood('2026-05-01', 320);
      await settle(d, m);
      await expectEqual();
      final mTombs = await m.db.select(m.db.silinenler).get();
      expect(mTombs.map((t) => t.deletedAt).toSet(), {at(300), at(310), at(320)});
      // A third device that never saw the deleted rows ends up the same.
      final z = Dev('üçüncü');
      addTearDown(z.close);
      await settle(m, z);
      expect(await z.state(), await d.state());
    });
  });

  // ===========================================================================
  group('senaryo e: içerik', () {
    test('unicode, uzun metin, sayılabilir/arşivli/planlı alışkanlık, iki yönde', () async {
      const tr = "İstanbul’da Çarşamba — şğüöçı İĞÜŞÖÇ 😀🎉 👨‍👩‍👧 é ñ 漢字 \"tırnak\" \\ ters </script> 'a'";
      await d.habit(tr, stamp: 10, created: 1);
      await d.sql(
          'UPDATE habits SET description = ?, category = ?, scheduled_weekdays = ?, updated_at = ? WHERE name = ?',
          [('Açıklama ğüşiöç 😀 ' * 400).substring(0, 7000), 'zihin', '1,3,5', at(11), tr]);
      await d.habit('Arşiv', stamp: 10, created: 2);
      await d.editHabit('Arşiv', 20, archive: true);
      await d.habit('Say', stamp: 10, created: 3, kind: 'count', target: 90);
      await d.cell('Say', '2026-05-01', EntryStatus.missed, 20, amount: 45);
      await d.mood('2026-05-01', 5, 20, note: tr);
      await d.task(tr, stamp: 10, created: 4);
      await d.sql('UPDATE tasks SET due_day = ?, priority = 2, updated_at = ?', ['2026-12-31', at(11)]);
      await d.session(100, 1500, stamp: 10, day: '2026-05-01');

      await sync(d, m);
      await expectEqual();
      final h = (await m.db.getAllHabits()).firstWhere((h) => h.name == tr);
      expect(h.scheduledWeekdays, '1,3,5');
      expect(h.description!.length, 7000);
      expect(await m.db.getAllHabits().then((l) => l.where((h) => h.archivedAt != null)), hasLength(1));

      await m.sql("UPDATE tasks SET status = 'done', completed_at = ?, updated_at = ?", [at(50), at(50)]);
      await sync(m, d);
      await expectEqual();
      expect((await d.db.getAllTasks()).single.status, 'done');
    });
  });

  // ===========================================================================
  group('ek 1: JSON ile taşınmış veri iki tarafta ayrı v5\'e çıktı', () {
    /// A v4-style backup (no uids, no stamps), as the old app wrote it.
    Future<String> v4Backup() async {
      final src = Dev('kaynak');
      addTearDown(src.close);
      await seed(src);
      await src.mood('2026-05-02', 3, 30);
      final json = jsonDecode(await BackupRepository(src.db).exportJson()) as Map<String, dynamic>;
      json['version'] = 4;
      json.remove('deleted');
      for (final k in ['habits', 'entries', 'moods', 'tasks', 'sessions']) {
        for (final r in json[k] as List) {
          for (final f in ['uid', 'updatedAt', 'habitUid', 'taskUid']) {
            (r as Map).remove(f);
          }
        }
      }
      return jsonEncode(json);
    }

    test('ilk senkron hiçbir kaydı ikilemez, iki yönde de', () async {
      final backup = await v4Backup();
      await BackupRepository(d.db).importJson(backup, replace: true);
      await BackupRepository(m.db).importJson(backup, replace: true);
      // Separate "upgrades": the uids are different on both sides.
      expect(await d.uidOfHabit('Kitap'), isNot(await m.uidOfHabit('Kitap')));
      final before = {
        for (final t in ['habits', 'habit_entries', 'mood_entries', 'tasks', 'focus_sessions'])
          t: await d.count(t),
      };

      final r = await sync(d, m);
      expect(r.adopted, 5); // 2 habits + 1 task + 2 sessions
      expect(r.added, 0);
      await settle(d, m);
      await expectEqual();
      for (final e in before.entries) {
        expect(await d.count(e.key), e.value, reason: e.key);
        expect(await m.count(e.key), e.value, reason: e.key);
      }
      // The session still knows its task.
      expect((await m.db.getAllSessions()).where((s) => s.taskId != null), hasLength(1));
    });

    test('yalnız bir taraf yedekten geldi, öbürü sıfırdan: yine ikilenmez', () async {
      final backup = await v4Backup();
      await BackupRepository(d.db).importJson(backup, replace: true);
      final r = await sync(d, m); // phone empty
      expect(r.added, greaterThan(0));
      await BackupRepository(m.db).importJson(backup, replace: false); // merge the old file in
      await settle(d, m);
      await expectEqual();
      expect(await m.count('habits'), 2);
      expect(await m.count('focus_sessions'), 2);
    });
  });

  // ===========================================================================
  group('ek 2: boşa çekilen hücre geri gelmez', () {
    for (final mobileClears in [true, false]) {
      for (final order in ['önce temizle', 'önce dosya']) {
        test('${mobileClears ? 'telefon' : 'masaüstü'} temizler, $order', () async {
          await seed(d);
          await sync(d, m);
          final clearer = mobileClears ? m : d;
          final other = mobileClears ? d : m;
          if (order == 'önce dosya') {
            // The other side exports first, then the clear happens.
            final stale = await exportSync(other.db);
            await clearer.clearCell('Kitap', '2026-05-01', 300);
            await importSyncText(clearer.db, stale);
            expect(await clearer.count('habit_entries'), 2, reason: 'stale ✓ must not return');
          } else {
            await clearer.clearCell('Kitap', '2026-05-01', 300);
          }
          await settle(d, m);
          await expectEqual();
          expect(await d.count('habit_entries'), 2);
          expect(await m.count('habit_entries'), 2);
        });
      }
    }

    test('temizlenen hücre daha sonra yeniden işaretlenirse işaret kazanır', () async {
      await seed(d);
      await sync(d, m);
      await d.clearCell('Kitap', '2026-05-01', 300);
      await settle(d, m);
      await m.cell('Kitap', '2026-05-01', EntryStatus.skipped, 400);
      await settle(d, m);
      await expectEqual();
      expect((await d.db.getAllEntries()).where((e) => e.status == EntryStatus.skipped), hasLength(1));
    });
  });

  // ===========================================================================
  group('ek 3: yedekten geri dönüş sonrası senkron', () {
    test('v5 yedek: uid ve damgalar korunur, sonraki senkron ikilemez', () async {
      await seed(d);
      await sync(d, m);
      final backup = await BackupRepository(d.db).exportJson();
      final habitsBefore = (await d.db.getAllHabits()).map((h) => [h.uid, h.updatedAt]).toList();

      // Changes after the backup, on both sides; then desktop restores.
      await d.editHabit('Kitap', 500, rename: 'Sonradan');
      await d.habit('Yeni', stamp: 510, created: 510);
      await m.cell('Kitap', '2026-05-07', EntryStatus.done, 520);
      await BackupRepository(d.db).importJson(backup, replace: true);
      expect((await d.db.getAllHabits()).map((h) => [h.uid, h.updatedAt]).toList(), habitsBefore,
          reason: 'restore keeps uid and updatedAt');

      await settle(d, m);
      await expectEqual();
      expect(await d.count('habits'), 2); // "Yeni" was not in the backup: gone
      expect((await d.db.getAllHabits()).map((h) => h.name), isNot(contains('Sonradan')));
      // The mark made on the phone after the backup survives.
      expect((await d.db.getAllEntries()).where((e) => e.date == '2026-05-07'), hasLength(1));
    });

    test('eski (v4) yedekten tam geri dönüş: yeni uid alır ama ikilenmez', () async {
      await seed(d);
      await sync(d, m);
      final json = jsonDecode(await BackupRepository(d.db).exportJson()) as Map<String, dynamic>;
      json['version'] = 4;
      json.remove('deleted');
      for (final k in ['habits', 'entries', 'moods', 'tasks', 'sessions']) {
        for (final r in json[k] as List) {
          for (final f in ['uid', 'updatedAt', 'habitUid', 'taskUid']) {
            (r as Map).remove(f);
          }
        }
      }
      final oldUid = await d.uidOfHabit('Kitap');
      await BackupRepository(d.db).importJson(jsonEncode(json), replace: true);
      expect(await d.uidOfHabit('Kitap'), isNot(oldUid));

      await settle(d, m);
      await expectEqual();
      expect(await d.count('habits'), 2);
      expect(await d.count('habit_entries'), 3);
      expect(await d.count('tasks'), 1);
      expect(await d.count('focus_sessions'), 2);
    });

    test('birleştirerek içe aktarma updatedAt\'i dosyadaki değerde bırakır', () async {
      await seed(d);
      final backup = await BackupRepository(d.db).exportJson();
      await d.editHabit('Kitap', 900, rename: 'Yeni ad'); // newer than the file
      await BackupRepository(d.db).importJson(backup, replace: false);
      final h = (await d.db.getAllHabits()).firstWhere((h) => h.name == 'Kitap');
      expect(h.updatedAt, at(10), reason: 'file value, not "now"');

      // Importing the same file again changes no stamp.
      final stamps = await d.state();
      await BackupRepository(d.db).importJson(backup, replace: false);
      expect(await d.state(), stamps);
    });
  });

  // ===========================================================================
  group('ek 4: farklı gün başlangıç saati', () {
    test('son değiştiren kazanır, iki yönde', () async {
      await seed(d);
      await d.setDayStart(4, 10);
      await m.setDayStart(2, 20);
      await settle(d, m);
      expect(await d.dayStart(), 2);
      expect(await m.dayStart(), 2);

      await d.setDayStart(6, 30);
      await settle(d, m);
      expect(await m.dayStart(), 6);
      await expectEqual();
    });

    test('kayıtlar gün metniyle gider: gece işareti iki cihazda aynı güne düşer', () async {
      await d.setDayStart(4, 10);
      await m.setDayStart(2, 5);
      await d.habit('Gece', stamp: 10, created: 1);
      // 01:30 on the 2nd still counts as the 1st for the desktop (day starts at 4).
      await d.cell('Gece', '2026-05-01', EntryStatus.done, 20);
      await sync(d, m);
      expect((await m.db.getAllEntries()).single.date, '2026-05-01');
      expect(await m.dayStart(), 4, reason: 'the newer setting came along');
    });

    test('hiç ayarlanmamış taraf diğerinin ayarını ezmez', () async {
      await d.setDayStart(3, 10);
      await sync(m, d); // phone has nothing set
      expect(await d.dayStart(), 3);
      await sync(d, m);
      expect(await m.dayStart(), 3);
    });
  });

  // ===========================================================================
  group('ölçek', () {
    test('20 alışkanlık x 3 yıl, 2000 görev, 5000 seans: saniyeler içinde', () async {
      const habits = 20, days = 1095, tasks = 2000, sessions = 5000;
      final sw = Stopwatch()..start();
      final ids = <int>[];
      for (var i = 0; i < habits; i++) {
        ids.add(await d.habit('Alışkanlık $i', stamp: 10, created: i));
      }
      await d.db.batch((b) {
        for (final id in ids) {
          for (var k = 0; k < days; k++) {
            final date = DateTime.utc(2024, 1, 1).add(Duration(days: k));
            b.insert(
              d.db.habitEntries,
              HabitEntriesCompanion.insert(
                habitId: id,
                date: '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
                status: EntryStatus.values[k % 3],
                updatedAt: Value(at(20 + k)),
              ),
            );
          }
        }
        for (var i = 0; i < tasks; i++) {
          b.insert(d.db.tasks, TasksCompanion.insert(title: 'Görev $i', updatedAt: Value(at(30)), createdAt: Value(when(i))));
        }
        for (var i = 0; i < sessions; i++) {
          b.insert(
            d.db.focusSessions,
            FocusSessionsCompanion.insert(
              startedAt: when(i * 4000),
              durationS: const Value(1500),
              day: '2026-05-01',
              updatedAt: Value(at(40)),
            ),
          );
        }
      });
      final seedMs = sw.elapsedMilliseconds;
      final entries = await d.count('habit_entries');
      expect(entries, habits * days);

      sw
        ..reset()
        ..start();
      final file = await exportSync(d.db);
      final exportMs = sw.elapsedMilliseconds;
      sw
        ..reset()
        ..start();
      final r = await importSyncText(m.db, file);
      final importMs = sw.elapsedMilliseconds;
      sw
        ..reset()
        ..start();
      final r2 = await importSyncText(m.db, file);
      final againMs = sw.elapsedMilliseconds;

      // ignore: avoid_print
      print('ölçek: dosya ${(file.length / 1024 / 1024).toStringAsFixed(1)} MB; '
          'kayıt üretimi ${seedMs}ms, dışa aktarma ${exportMs}ms, '
          'içe aktarma (boş cihaz) ${importMs}ms, ikinci içe aktarma ${againMs}ms');
      expect(r.entry.added, habits * days);
      expect(r.task.added, tasks);
      expect(r.session.added, sessions);
      expect(r2.changed, isFalse);
      expect(exportMs, lessThan(30000));
      expect(importMs, lessThan(60000));
      expect(againMs, lessThan(30000));
      await expectEqual();
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
