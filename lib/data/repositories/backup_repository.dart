import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../database/database.dart';

/// Outcome of an import, for showing a confirmation to the user.
class ImportResult {
  final int habits;
  final int entries;
  const ImportResult({required this.habits, required this.entries});
}

/// JSON backup: export everything to a single string, import it back.
///
/// The format is intentionally flat and stable (see the blueprint). This is the
/// only way data moves between devices — a file, not a sync service.
class BackupRepository {
  final AppDatabase db;
  BackupRepository(this.db);

  /// Serialises the whole database to a pretty-printed JSON string.
  Future<String> exportJson() async {
    final habits = await db.getAllHabits();
    final entries = await db.getAllEntries();

    final map = <String, dynamic>{
      'format': AppConstants.backupFormat,
      'version': AppConstants.backupVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'habits': [
        for (final h in habits)
          {
            'id': h.id,
            'name': h.name,
            'description': h.description,
            'colorValue': h.colorValue,
            'iconCodePoint': h.iconCodePoint,
            'createdAt': h.createdAt.toUtc().toIso8601String(),
            'archivedAt': h.archivedAt?.toUtc().toIso8601String(),
            'sortOrder': h.sortOrder,
            'scheduledWeekdays': h.scheduledWeekdays,
          },
      ],
      'entries': [
        for (final e in entries)
          {'habitId': e.habitId, 'date': e.date, 'done': e.done},
      ],
    };

    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// Suggested file name for an export.
  String suggestedFileName() {
    final now = DateTime.now();
    final stamp =
        '${now.year}${_two(now.month)}${_two(now.day)}-${_two(now.hour)}${_two(now.minute)}';
    return 'aktenak-backup-$stamp.json';
  }

  /// Imports a backup string.
  ///
  /// When [replace] is true the existing data is wiped first. Otherwise the
  /// import is merged: habits are upserted by id and entries are upserted by
  /// (habitId, date), overwriting on conflict.
  Future<ImportResult> importJson(String jsonStr, {required bool replace}) async {
    final dynamic decoded = jsonDecode(jsonStr);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Geçersiz yedek dosyası.');
    }
    if (decoded['format'] != AppConstants.backupFormat) {
      throw const FormatException('Tanınmayan yedek formatı.');
    }

    final habitMaps = (decoded['habits'] as List? ?? const []).cast<Map<String, dynamic>>();
    final entryMaps = (decoded['entries'] as List? ?? const []).cast<Map<String, dynamic>>();

    await db.transaction(() async {
      if (replace) {
        await db.delete(db.habitEntries).go();
        await db.delete(db.habits).go();
      }

      for (final h in habitMaps) {
        final companion = HabitsCompanion(
          id: Value(h['id'] as int),
          name: Value(h['name'] as String),
          description: Value(h['description'] as String?),
          colorValue: Value(h['colorValue'] as int),
          iconCodePoint: Value(h['iconCodePoint'] as int),
          createdAt: Value(_parseDate(h['createdAt']) ?? DateTime.now()),
          archivedAt: Value(_parseDate(h['archivedAt'])),
          sortOrder: Value((h['sortOrder'] as int?) ?? 0),
          scheduledWeekdays: Value((h['scheduledWeekdays'] as String?) ?? ''),
        );
        await db.into(db.habits).insertOnConflictUpdate(companion);
      }

      for (final e in entryMaps) {
        await db.setEntry(
          e['habitId'] as int,
          e['date'] as String,
          (e['done'] as bool?) ?? false,
        );
      }
    });

    return ImportResult(habits: habitMaps.length, entries: entryMaps.length);
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v as String)?.toLocal();
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}
