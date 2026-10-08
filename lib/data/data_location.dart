import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';
import 'database/database.dart';
import 'repositories/backup_repository.dart';

/// Where the database lives.
///
/// On Windows `getApplicationSupportDirectory()` derives the folder from the
/// exe's ProductName. v1.2.0 renamed that ("aktenak_habit_tracker" →
/// "Aktenak Habit Tracker") and silently moved every user onto a new, empty
/// database. The path is therefore pinned to the original folder here,
/// independent of anything in Runner.rc.
Future<Directory> appDataDirectory() async {
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    if (appData != null) {
      return Directory(p.join(appData, 'com.aktenak', 'aktenak_habit_tracker'));
    }
  }
  return getApplicationSupportDirectory();
}

/// The folder v1.2.0–v1.2.1 wrote to by accident (Windows only).
Directory? strayV12Directory() {
  if (!Platform.isWindows) return null;
  final appData = Platform.environment['APPDATA'];
  if (appData == null) return null;
  return Directory(p.join(appData, 'com.aktenak', 'Aktenak Habit Tracker'));
}

/// Brings data entered under v1.2.x back into [canonical], once.
///
/// - No stray database: nothing to do.
/// - Stray database without user data: renamed aside so it isn't checked
///   again.
/// - Stray database with data: merged into [canonical] (an empty canonical
///   simply receives everything; one that has data keeps it — the merge
///   import never overwrites a different habit). [canonical]'s previous file
///   is copied aside first, a JSON of the recovered data is kept in
///   `yedekler/`, and the stray file is renamed so this runs only once.
///
/// Settings (theme, reminder hour…) are not part of the backup format and
/// are not carried over. Returns the recovered-data JSON, or null.
Future<File?> recoverStrayV12Data({
  required Directory canonical,
  required Directory stray,
  required DateTime now,
}) async {
  final strayDb = File(p.join(stray.path, AppConstants.dbFileName));
  if (!await strayDb.exists()) return null;
  final stamp = _stamp(now);

  final source = AppDatabase.forTesting(NativeDatabase(strayDb));
  final String json;
  final bool hasData;
  try {
    hasData = await _hasUserData(source);
    json = hasData ? await BackupRepository(source).exportJson() : '';
  } finally {
    await source.close();
  }

  if (!hasData) {
    await strayDb.rename('${strayDb.path}.bos-$stamp');
    return null;
  }

  await canonical.create(recursive: true);
  final canonicalDb = File(p.join(canonical.path, AppConstants.dbFileName));
  if (await canonicalDb.exists()) {
    await canonicalDb.copy('${canonicalDb.path}.v12-oncesi-$stamp');
  }

  final target = AppDatabase.forTesting(NativeDatabase(canonicalDb));
  try {
    await BackupRepository(target).importJson(json, replace: false);
  } finally {
    await target.close();
  }

  final saved = File(
    p.join(canonical.path, 'yedekler', 'v12-kurtarilan-$stamp.json'),
  );
  await saved.parent.create(recursive: true);
  await saved.writeAsString(json, flush: true);

  await strayDb.rename('${strayDb.path}.tasindi-$stamp');
  return saved;
}

Future<bool> _hasUserData(AppDatabase db) async {
  return (await db.getAllHabits()).isNotEmpty ||
      (await db.getAllEntries()).isNotEmpty ||
      (await db.getAllMoods()).isNotEmpty ||
      (await db.getAllTasks()).isNotEmpty ||
      (await db.getAllSessions()).isNotEmpty;
}

String _stamp(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}${two(d.month)}${two(d.day)}-${two(d.hour)}${two(d.minute)}';
}
