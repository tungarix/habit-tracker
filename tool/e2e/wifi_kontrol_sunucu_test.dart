// Uçtan uca denetim için masaüstü tarafı: GERÇEK EslestirmeSunucusu'nu geçici bir SQLite dosyasıyla
// 127.0.0.1'de açar ve mobil istemci testinin (habit-tracker-mobil/tool/e2e/wifi_e2e_test.dart)
// yönetebilmesi için küçük bir düz HTTP "kontrol" arayüzü sunar. Gerçek %APPDATA% verisine dokunmaz.
//
// Çalıştır (genelde mobil tool/e2e/wifi_calistir.ps1 başlatır):
//   E2E_KONTROL_PORT=48731 flutter test tool/e2e/wifi_kontrol_sunucu_test.dart
// Yalnız test içindir: loopbackIzinli, kontrol arayüzü, uydurma veri. Üretim koduna girmez.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aktenak_habit_tracker/core/wifi_sync/sunucu.dart';
import 'package:aktenak_habit_tracker/data/database/database.dart';
import 'package:aktenak_habit_tracker/data/sync/sync_export.dart';
import 'package:aktenak_habit_tracker/data/sync/sync_import.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const t0 = 1780000000;
int at(int n) => t0 + n;

late Directory tmp;
late AppDatabase db;
EslestirmeSunucusu? sunucu;
var yedekSayisi = 0;

Future<void> dbAc() async {
  await sunucu?.kapat();
  sunucu = null;
  try {
    await db.close();
  } catch (_) {}
  final f = File('${tmp.path}/masaustu.sqlite');
  if (f.existsSync()) f.deleteSync();
  db = AppDatabase.forTesting(NativeDatabase(f));
  yedekSayisi = 0;
}

Future<void> habit(String ad, int stamp) => db.insertHabit(
  HabitsCompanion.insert(
    name: ad,
    colorValue: 0xFF4CAF50,
    iconCodePoint: 0xe000,
    createdAt: Value(DateTime.fromMillisecondsSinceEpoch(at(0) * 1000)),
    updatedAt: Value(at(stamp)),
  ),
);

Future<Habit> bul(String ad) async =>
    (await db.getAllHabits()).firstWhere((h) => h.name == ad);

Future<Map<String, Object?>> durum() async => {
  'sunucu': sunucu?.durum.name,
  'olaylar': sunucu?.olaylar ?? <String>[],
  'sonuc': sunucu?.sonuc?.summary(),
  'istemci': sunucu?.istemci?.ad,
  'yedek': yedekSayisi,
  'habits': [
    for (final h in await db.getAllHabits()) {'name': h.name, 'uid': h.uid},
  ],
  'silinen': [
    for (final r in await db.customSelect('SELECT kind, anahtar FROM silinenler').get())
      '${r.read<String>('kind')}:${r.read<String>('anahtar')}',
  ],
};

Future<Map<String, Object?>> komut(String yol, Map<String, dynamic> g) async {
  switch (yol) {
    case '/sifirla':
      await dbAc();
    case '/habit':
      await habit(g['ad'] as String, g['damga'] as int);
    case '/yeniAd':
      final h = await bul(g['ad'] as String);
      await db.customStatement('UPDATE habits SET name = ?, updated_at = ? WHERE id = ?', [
        g['yeni'],
        at(g['damga'] as int),
        h.id,
      ]);
    case '/sil':
      final h = await bul(g['ad'] as String);
      await db.deleteHabit(h.id);
      await db.customStatement(
        "UPDATE silinenler SET deleted_at = ? WHERE kind = 'habit' AND anahtar = ?",
        [at(g['damga'] as int), h.uid],
      );
    case '/baslat':
      await sunucu?.kapat();
      final s = EslestirmeSunucusu(
        durumAl: () async => Uint8List.fromList(utf8.encode(await exportSync(db, deviceName: 'Masaustu'))),
        onizle: (b) => previewSyncBytes(db, b),
        uygula: (b) => importSyncBytes(db, b),
        yedekAl: () async {
          await File('${tmp.path}/yedek-${++yedekSayisi}.json').writeAsString(await exportSync(db));
        },
        sunucuAdi: 'E2E-PC',
        surum: 'e2e',
        adresler: const ['127.0.0.1'],
        ayar: EslestirmeAyar(
          loopbackIzinli: true,
          qrOmru: Duration(seconds: (g['qrOmruSn'] as int?) ?? 180),
        ),
      );
      sunucu = s;
      final o2 = (g['onay2'] as String?) ?? 'evet', o4 = (g['onay4'] as String?) ?? 'evet';
      s.durumlar.listen((d) {
        if (d == EslestirmeDurum.baglantiOnayi && o2 != 'yok') s.baglantiyiOnayla(o2 == 'evet');
        if (d == EslestirmeDurum.birlesmeOnayi && o4 != 'yok') s.birlesmeyiOnayla(o4 == 'evet');
      });
      final q = await s.baslat();
      return {
        'link': q.kodla(),
        'adresler': q.adresler,
        'port': q.port,
        'parmakIzi': q.parmakIzi,
        'jeton': q.jeton,
        'bitis': q.bitis,
        'ad': q.ad,
      };
    case '/bekle':
      final s = sunucu!;
      if (!s.durum.bitti) {
        await s.bitti.timeout(Duration(seconds: (g['sn'] as int?) ?? 30), onTimeout: () => s.durum);
      }
    case '/durum':
      break;
    default:
      throw ArgumentError('bilinmeyen komut $yol');
  }
  return durum();
}

void main() {
  test('wifi e2e kontrol sunucusu', () async {
    tmp = Directory.systemTemp.createTempSync('habit_e2e_masaustu_');
    db = AppDatabase.forTesting(NativeDatabase(File('${tmp.path}/masaustu.sqlite')));
    final port = int.parse(Platform.environment['E2E_KONTROL_PORT'] ?? '48731');
    final kontrol = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    final cik = Completer<void>();
    kontrol.listen((r) async {
      try {
        final govde = utf8.decode(await r.expand((e) => e).toList());
        final g = govde.isEmpty ? <String, dynamic>{} : jsonDecode(govde) as Map<String, dynamic>;
        if (r.uri.path == '/cik') {
          cik.complete();
          r.response.write('{}');
        } else {
          r.response.write(jsonEncode(await komut(r.uri.path, g)));
        }
      } catch (e) {
        r.response.statusCode = 500;
        r.response.write(jsonEncode({'hata': '$e'}));
      }
      await r.response.close();
    });
    stdout.writeln('KONTROL HAZIR $port');
    await cik.future.timeout(const Duration(minutes: 40));
    await sunucu?.kapat();
    await kontrol.close(force: true);
    await db.close();
    tmp.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 45)));
}
