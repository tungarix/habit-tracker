import 'dart:io';

import 'package:path/path.dart' as p;

import 'repositories/backup_repository.dart';

/// Günde bir kez, veri klasörünün altındaki `yedekler/` içine tam JSON yedeği
/// yazar ve en yeni [keep] otomatik yedeği tutar.
///
/// Elle alınan "Dışa aktar" dosyalarına dokunmaz: budama yalnızca
/// [filePrefix] ile başlayan, kendi yazdığı dosyaları siler.
class AutoBackup {
  AutoBackup({required this.repo, required this.dir, this.keep = 14});

  static const filePrefix = 'aktenak-auto-';

  final BackupRepository repo;

  /// Yedeklerin yazıldığı klasör (yoksa oluşturulur).
  final Directory dir;

  final int keep;

  /// Bugünün yedeği yoksa alır; aldığı dosyayı, almadıysa null döner.
  Future<File?> runIfDue(DateTime now) async {
    await dir.create(recursive: true);
    final target = File(p.join(dir.path, '$filePrefix${_stamp(now)}.json'));
    if (await target.exists()) return null;

    // Önce geçici ada yaz, sonra taşı: yarıda kesilen bir yazım "yedek"
    // görünümlü bozuk bir dosya bırakmasın.
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(await repo.exportJson(), flush: true);
    await temp.rename(target.path);

    await _prune(target);
    return target;
  }

  /// En yeni otomatik yedeğin zamanı (yoksa null).
  Future<DateTime?> latest() async {
    final files = await _autoFiles();
    if (files.isEmpty) return null;
    return files.first.lastModified();
  }

  /// [fresh] yeni yazılan dosyadır ve asla silinmez: saat geri alınmışsa adı
  /// "eski" sıralanır, yoksa yazıldığı anda budanırdı.
  Future<void> _prune(File fresh) async {
    final others = [
      for (final f in await _autoFiles())
        if (p.basename(f.path) != p.basename(fresh.path)) f,
    ];
    for (final f in others.skip(keep > 0 ? keep - 1 : 0)) {
      await f.delete();
    }
  }

  /// Kendi yazdığımız yedekler, en yeni önce (ad tarih içerdiği için ad
  /// sıralaması = tarih sıralaması).
  Future<List<File>> _autoFiles() async {
    if (!await dir.exists()) return const [];
    final files = <File>[
      await for (final e in dir.list())
        if (e is File &&
            p.basename(e.path).startsWith(filePrefix) &&
            e.path.endsWith('.json'))
          e,
    ];
    files.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    return files;
  }

  static String _stamp(DateTime d) => '${d.year}${_two(d.month)}${_two(d.day)}';

  static String _two(int n) => n.toString().padLeft(2, '0');
}
