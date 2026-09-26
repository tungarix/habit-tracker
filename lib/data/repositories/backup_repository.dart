import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../../core/enums.dart';
import '../database/database.dart';

/// Outcome of an import, for showing a confirmation to the user.
class ImportResult {
  final int habits;
  final int entries;
  final int moods;
  final int tasks;
  final int sessions;
  const ImportResult({
    required this.habits,
    required this.entries,
    required this.moods,
    required this.tasks,
    required this.sessions,
  });
}

/// JSON backup: export everything to a single string, import it back.
///
/// The format is intentionally flat and stable (see the blueprint). This is the
/// only way data moves between devices — a file, not a sync service.
///
/// Format v2 adds `category` on habits, tri-state `status` on entries
/// ('done' | 'missed' | 'skipped') and a top-level `moods` list. v1 files
/// (boolean `done` entries) can still be imported.
class BackupRepository {
  final AppDatabase db;
  BackupRepository(this.db);

  /// Serialises the whole database to a pretty-printed JSON string.
  Future<String> exportJson() async {
    final habits = await db.getAllHabits();
    final entries = await db.getAllEntries();
    final moods = await db.getAllMoods();
    final taskRows = await db.getAllTasks();
    final sessionRows = await db.getAllSessions();

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
            'category': h.category,
            'kind': h.kind,
            'target': h.target,
            'createdAt': h.createdAt.toUtc().toIso8601String(),
            'archivedAt': h.archivedAt?.toUtc().toIso8601String(),
            'sortOrder': h.sortOrder,
            'scheduledWeekdays': h.scheduledWeekdays,
          },
      ],
      'entries': [
        for (final e in entries)
          {
            'habitId': e.habitId,
            'date': e.date,
            'status': e.status.name,
            'value': e.value,
          },
      ],
      'moods': [
        for (final m in moods)
          {'date': m.date, 'mood': m.mood, 'note': m.note},
      ],
      'tasks': [
        for (final t in taskRows)
          {
            'id': t.id,
            'title': t.title,
            'status': t.status,
            'priority': t.priority,
            'dueDay': t.dueDay,
            'createdAt': t.createdAt.toUtc().toIso8601String(),
            'completedAt': t.completedAt?.toUtc().toIso8601String(),
          },
      ],
      'sessions': [
        for (final s in sessionRows)
          {
            'kind': s.kind,
            'startedAt': s.startedAt.toUtc().toIso8601String(),
            'endedAt': s.endedAt?.toUtc().toIso8601String(),
            'durationS': s.durationS,
            'day': s.day,
            'taskId': s.taskId,
          },
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

  /// Imports a backup string (format v1 or v2).
  ///
  /// When [replace] is true the existing data is wiped first. Otherwise the
  /// import is merged: habits are upserted by id, entries by (habitId, date)
  /// and moods by date, overwriting on conflict.
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
    final moodMaps = (decoded['moods'] as List? ?? const []).cast<Map<String, dynamic>>();
    final taskMaps = (decoded['tasks'] as List? ?? const []).cast<Map<String, dynamic>>();
    final sessionMaps =
        (decoded['sessions'] as List? ?? const []).cast<Map<String, dynamic>>();

    var importedEntries = 0;

    await db.transaction(() async {
      if (replace) {
        await db.delete(db.focusSessions).go();
        await db.delete(db.tasks).go();
        await db.delete(db.moodEntries).go();
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
          category: Value((h['category'] as String?) ?? ''),
          kind: Value((h['kind'] as String?) ?? 'bool'),
          target: Value((h['target'] as int?) ?? 1),
          createdAt: Value(_parseDate(h['createdAt']) ?? DateTime.now()),
          archivedAt: Value(_parseDate(h['archivedAt'])),
          sortOrder: Value((h['sortOrder'] as int?) ?? 0),
          scheduledWeekdays: Value((h['scheduledWeekdays'] as String?) ?? ''),
        );
        await db.into(db.habits).insertOnConflictUpdate(companion);
      }

      for (final e in entryMaps) {
        final status = _parseStatus(e);
        if (status == null) continue; // v1 "done: false" rows carry no mark
        await db.setEntryStatus(
          e['habitId'] as int,
          e['date'] as String,
          status,
          amount: e['value'] as int?, // absent in v1/v2 backups
        );
        importedEntries++;
      }

      for (final m in moodMaps) {
        final mood = m['mood'] as int?;
        if (mood == null || mood < 1 || mood > 5) continue;
        await db.setMood(m['date'] as String, mood, note: m['note'] as String?);
      }

      for (final t in taskMaps) {
        await db.into(db.tasks).insertOnConflictUpdate(
              TasksCompanion(
                id: Value(t['id'] as int),
                title: Value(t['title'] as String),
                status: Value((t['status'] as String?) ?? 'todo'),
                priority: Value((t['priority'] as int?) ?? 1),
                dueDay: Value(t['dueDay'] as String?),
                createdAt: Value(_parseDate(t['createdAt']) ?? DateTime.now()),
                completedAt: Value(_parseDate(t['completedAt'])),
              ),
            );
      }

      for (final s in sessionMaps) {
        final started = _parseDate(s['startedAt']);
        final day = s['day'] as String?;
        if (started == null || day == null) continue;
        await db.insertSession(
          kind: (s['kind'] as String?) ?? 'focus',
          startedAt: started,
          endedAt: _parseDate(s['endedAt']) ?? started,
          durationS: (s['durationS'] as int?) ?? 0,
          day: day,
          taskId: s['taskId'] as int?,
        );
      }
    });

    return ImportResult(
      habits: habitMaps.length,
      entries: importedEntries,
      moods: moodMaps.length,
      tasks: taskMaps.length,
      sessions: sessionMaps.length,
    );
  }

  /// Reads an entry's status from a v2 (`status` string) or v1 (`done` bool)
  /// entry map. Returns null when the row carries no mark.
  static EntryStatus? _parseStatus(Map<String, dynamic> entry) {
    final statusName = entry['status'] as String?;
    if (statusName != null) {
      for (final s in EntryStatus.values) {
        if (s.name == statusName) return s;
      }
      return null;
    }
    // v1 fallback: done: true -> ✓, done: false -> no mark.
    return (entry['done'] as bool?) == true ? EntryStatus.done : null;
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v as String)?.toLocal();
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}
