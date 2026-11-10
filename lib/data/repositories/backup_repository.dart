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

  /// Sessions actually added (merging skips the ones already stored).
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
///
/// Format v5 adds the sync identity: `uid` + `updatedAt` on habits, tasks and
/// sessions, `updatedAt` on entries and moods, `habitUid` on entries,
/// `taskUid` on sessions, and a top-level `deleted` list (the delete log).
/// v1-v4 files are read by the same first-match rule sync uses, see
/// docs/senkron.md.
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
    final tombstones = await db.select(db.silinenler).get();
    final habitUid = {for (final h in habits) h.id: h.uid};
    final taskUid = {for (final t in taskRows) t.id: t.uid};

    final map = <String, dynamic>{
      'format': AppConstants.backupFormat,
      'version': AppConstants.backupVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'habits': [
        for (final h in habits)
          {
            'id': h.id,
            'uid': h.uid,
            'updatedAt': _isoSecs(h.updatedAt),
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
            'habitUid': habitUid[e.habitId],
            'updatedAt': _isoSecs(e.updatedAt),
            'date': e.date,
            'status': e.status.name,
            'value': e.value,
          },
      ],
      'moods': [
        for (final m in moods)
          {
            'date': m.date,
            'mood': m.mood,
            'note': m.note,
            'updatedAt': _isoSecs(m.updatedAt),
          },
      ],
      'tasks': [
        for (final t in taskRows)
          {
            'id': t.id,
            'uid': t.uid,
            'updatedAt': _isoSecs(t.updatedAt),
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
            'uid': s.uid,
            'updatedAt': _isoSecs(s.updatedAt),
            'kind': s.kind,
            'startedAt': s.startedAt.toUtc().toIso8601String(),
            'endedAt': s.endedAt?.toUtc().toIso8601String(),
            'durationS': s.durationS,
            'day': s.day,
            'taskId': s.taskId,
            'taskUid': taskUid[s.taskId],
          },
      ],
      'deleted': [
        for (final d in tombstones)
          {
            'kind': d.kind,
            'key': d.anahtar,
            'deletedAt': _isoSecs(d.deletedAt),
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

  /// Imports a backup string (format v1 to v5).
  ///
  /// When [replace] is true the existing data is wiped first and every row
  /// keeps the id it has in the file. Otherwise the import is merged:
  ///
  /// * A habit or task from the file *is* a local one when it has the same id
  ///   **and** the same creation time (to the second); files without a
  ///   creation time (v1) match by name/title instead. A match is updated in
  ///   place, so a renamed habit does not turn into a copy. So is a row that
  ///   an earlier merge of this same file had to renumber (same creation time
  ///   and name under another id). Anything else is added as a new row under a
  ///   fresh id, and the file's ids are translated through that mapping: ids
  ///   from another device mean nothing here.
  /// * Entries are upserted by (habit, date) and moods by date, overwriting on
  ///   conflict. An entry whose habit can be found neither in the file nor
  ///   here is skipped instead of aborting the whole import.
  /// * A focus session that is already stored (same kind, start, duration and
  ///   day) is not added again.
  Future<ImportResult> importJson(String jsonStr, {required bool replace}) async {
    final dynamic decoded = jsonDecode(jsonStr);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Geçersiz yedek dosyası.');
    }
    if (decoded['format'] != AppConstants.backupFormat) {
      throw const FormatException('Tanınmayan yedek formatı.');
    }
    final version = decoded['version'];
    if (version is int && version > AppConstants.backupVersion) {
      throw const FormatException(
        'Bu yedek daha yeni bir sürümle alınmış. Uygulamayı güncelle.',
      );
    }

    final habitMaps = (decoded['habits'] as List? ?? const []).cast<Map<String, dynamic>>();
    final entryMaps = (decoded['entries'] as List? ?? const []).cast<Map<String, dynamic>>();
    final moodMaps = (decoded['moods'] as List? ?? const []).cast<Map<String, dynamic>>();
    final taskMaps = (decoded['tasks'] as List? ?? const []).cast<Map<String, dynamic>>();
    final sessionMaps =
        (decoded['sessions'] as List? ?? const []).cast<Map<String, dynamic>>();
    final deletedMaps =
        (decoded['deleted'] as List? ?? const []).cast<Map<String, dynamic>>();

    var importedEntries = 0;
    var importedSessions = 0;

    await db.transaction(() async {
      if (replace) {
        await db.delete(db.focusSessions).go();
        await db.delete(db.tasks).go();
        await db.delete(db.moodEntries).go();
        await db.delete(db.habitEntries).go();
        await db.delete(db.habits).go();
        // The delete log is deliberately left alone: whatever the backup does
        // not bring back stays deleted for sync too, and rows it does bring
        // back clear their own tombstone when they are inserted.
      }

      // File id -> id the row has in this database. In replace mode that is
      // the same number (the tables were just emptied); in merge mode a row
      // whose id is taken by something else gets a new one.
      final habitIds = <int, int>{};
      final taskIds = <int, int>{};
      // File uid -> local id, for rows the file names by uid (v5).
      final habitIdByUid = <String, int>{};
      final taskIdByUid = <String, int>{};
      final seenUids = <String>{}; // a uid used twice in the file is dropped

      final knownHabits = replace
          ? <_KnownRow>[]
          : [
              for (final h in await db.getAllHabits())
                _KnownRow(h.id, h.name, h.createdAt, h.uid),
            ];
      for (final h in habitMaps) {
        final fileId = h['id'] as int;
        final name = h['name'] as String;
        final createdAt = _parseDate(h['createdAt']);
        final fileUid = _uid(h['uid'], seenUids);
        final stamp = _secs(h['updatedAt']);
        final match = replace
            ? null
            : _findByUid(knownHabits, fileUid) ??
                _findKnown(knownHabits, fileId: fileId, label: name, createdAt: createdAt);
        final targetId = replace ? fileId : match?.id;

        final companion = HabitsCompanion(
          id: targetId == null ? const Value.absent() : Value(targetId),
          // A match without the file's uid adopts it (first-match rule).
          uid: fileUid == null ? const Value.absent() : Value(fileUid),
          name: Value(name),
          description: Value(h['description'] as String?),
          colorValue: Value(h['colorValue'] as int),
          iconCodePoint: Value(h['iconCodePoint'] as int),
          category: Value((h['category'] as String?) ?? ''),
          kind: Value((h['kind'] as String?) ?? 'bool'),
          target: Value((h['target'] as int?) ?? 1),
          // Left out (not "now") when the file has none, so merging an old v1
          // file never rewrites the creation time of a habit that matched;
          // a brand-new row gets the column default, which is now.
          createdAt: createdAt == null ? const Value.absent() : Value(createdAt),
          archivedAt: Value(_parseDate(h['archivedAt'])),
          sortOrder: Value((h['sortOrder'] as int?) ?? 0),
          scheduledWeekdays: Value((h['scheduledWeekdays'] as String?) ?? ''),
        );
        final int rowId;
        if (targetId == null) {
          rowId = await db.into(db.habits).insert(companion);
          habitIds[fileId] = rowId;
          knownHabits.add(_KnownRow(rowId, name, createdAt ?? DateTime.now(), fileUid));
        } else {
          await db.into(db.habits).insertOnConflictUpdate(companion);
          rowId = targetId;
          habitIds[fileId] = targetId;
          match?.label = name;
          if (fileUid != null) match?.uid = fileUid;
        }
        if (fileUid != null) habitIdByUid[fileUid] = rowId;
        await _restoreStamp('habits', 'id = ?', [rowId], stamp);
      }

      for (final e in entryMaps) {
        final status = _parseStatus(e);
        if (status == null) continue; // v1 "done: false" rows carry no mark
        final fileHabitUid = e['habitUid'] as String?;
        final habitId = (fileHabitUid == null ? null : habitIdByUid[fileHabitUid]) ??
            await _resolveId(
              e['habitId'] as int?,
              habitIds,
              (id) async => await db.getHabit(id) != null,
            );
        if (habitId == null) continue; // no such habit: would break the foreign key
        final date = e['date'] as String;
        await db.setEntryStatus(
          habitId,
          date,
          status,
          amount: e['value'] as int?, // absent in v1/v2 backups
        );
        await _restoreStamp(
          'habit_entries',
          'habit_id = ? AND date = ?',
          [habitId, date],
          _secs(e['updatedAt']),
        );
        importedEntries++;
      }

      for (final m in moodMaps) {
        final mood = m['mood'] as int?;
        if (mood == null || mood < 1 || mood > 5) continue;
        final date = m['date'] as String;
        await db.setMood(date, mood, note: m['note'] as String?);
        await _restoreStamp('mood_entries', 'date = ?', [date], _secs(m['updatedAt']));
      }

      final knownTasks = replace
          ? <_KnownRow>[]
          : [
              for (final t in await db.getAllTasks())
                _KnownRow(t.id, t.title, t.createdAt, t.uid),
            ];
      for (final t in taskMaps) {
        final fileId = t['id'] as int;
        final title = t['title'] as String;
        final createdAt = _parseDate(t['createdAt']);
        final fileUid = _uid(t['uid'], seenUids);
        final match = replace
            ? null
            : _findByUid(knownTasks, fileUid) ??
                _findKnown(knownTasks, fileId: fileId, label: title, createdAt: createdAt);
        final targetId = replace ? fileId : match?.id;

        final companion = TasksCompanion(
          id: targetId == null ? const Value.absent() : Value(targetId),
          uid: fileUid == null ? const Value.absent() : Value(fileUid),
          title: Value(title),
          status: Value((t['status'] as String?) ?? 'todo'),
          priority: Value((t['priority'] as int?) ?? 1),
          dueDay: Value(t['dueDay'] as String?),
          createdAt: createdAt == null ? const Value.absent() : Value(createdAt),
          completedAt: Value(_parseDate(t['completedAt'])),
        );
        final int rowId;
        if (targetId == null) {
          rowId = await db.into(db.tasks).insert(companion);
          taskIds[fileId] = rowId;
          knownTasks.add(_KnownRow(rowId, title, createdAt ?? DateTime.now(), fileUid));
        } else {
          await db.into(db.tasks).insertOnConflictUpdate(companion);
          rowId = targetId;
          taskIds[fileId] = targetId;
          match?.label = title;
          if (fileUid != null) match?.uid = fileUid;
        }
        if (fileUid != null) taskIdByUid[fileUid] = rowId;
        await _restoreStamp('tasks', 'id = ?', [rowId], _secs(t['updatedAt']));
      }

      // Sessions have no identity of their own in old files, so "the same
      // session" means the same kind, started at the same moment, for the same
      // length, on the same day (a v5 file also has its uid). Replace mode
      // keeps every row of the file as it was.
      final storedSessions = replace ? const <FocusSession>[] : await db.getAllSessions();
      final sessionsByKey = {
        for (final s in storedSessions)
          _sessionKey(s.kind, s.startedAt, s.durationS ?? 0, s.day): s,
      };
      final sessionUids = {
        for (final s in storedSessions)
          if (s.uid != null) s.uid!,
      };
      for (final s in sessionMaps) {
        final started = _parseDate(s['startedAt']);
        final day = s['day'] as String?;
        if (started == null || day == null) continue;
        final kind = (s['kind'] as String?) ?? 'focus';
        final durationS = (s['durationS'] as int?) ?? 0;
        final fileUid = _uid(s['uid'], seenUids);
        final key = _sessionKey(kind, started, durationS, day);
        if (!replace) {
          final stored = sessionsByKey[key];
          if (stored != null ||
              (fileUid != null && sessionUids.contains(fileUid))) {
            // Already stored. Hand it the file's uid if it has none of ours.
            if (stored != null &&
                fileUid != null &&
                stored.uid != fileUid &&
                !sessionUids.contains(fileUid)) {
              await db.customStatement(
                'UPDATE focus_sessions SET uid = ? WHERE id = ?',
                [fileUid, stored.id],
              );
              sessionUids.add(fileUid);
            }
            continue;
          }
        }
        // A session whose task is gone is still worth keeping: the focus time
        // counts, it just has no task (what deleting the task does as well).
        final fileTaskUid = s['taskUid'] as String?;
        final taskId = (fileTaskUid == null ? null : taskIdByUid[fileTaskUid]) ??
            await _resolveId(
              s['taskId'] as int?,
              taskIds,
              (id) async =>
                  await (db.select(db.tasks)..where((t) => t.id.equals(id)))
                      .getSingleOrNull() !=
                  null,
            );
        final stamp = _secs(s['updatedAt']);
        await db.into(db.focusSessions).insert(
              FocusSessionsCompanion.insert(
                kind: Value(kind),
                startedAt: started,
                endedAt: Value(_parseDate(s['endedAt']) ?? started),
                durationS: Value(durationS),
                day: day,
                taskId: Value(taskId),
                uid: fileUid == null ? const Value.absent() : Value(fileUid),
                updatedAt: stamp == null ? const Value.absent() : Value(stamp),
              ),
            );
        if (fileUid != null) sessionUids.add(fileUid);
        sessionsByKey.putIfAbsent(
          key,
          () => FocusSession(
            id: -1,
            uid: fileUid,
            updatedAt: stamp ?? 0,
            kind: kind,
            startedAt: started,
            endedAt: started,
            durationS: durationS,
            taskId: taskId,
            day: day,
          ),
        );
        importedSessions++;
      }

      // Replacing from a v5 file also restores its delete log - except for
      // anything the file itself still has alive.
      if (replace) {
        final alive = <String>{
          for (final h in habitMaps) 'habit:${h['uid']}',
          for (final t in taskMaps) 'task:${t['uid']}',
          for (final s in sessionMaps) 'session:${s['uid']}',
          for (final e in entryMaps) 'entry:${e['habitUid']}|${e['date']}',
          for (final m in moodMaps) 'mood:${m['date']}',
        };
        for (final d in deletedMaps) {
          final kind = d['kind'] as String?;
          final key = d['key'] as String?;
          final at = _secs(d['deletedAt']);
          if (kind == null || key == null || at == null) continue;
          if (alive.contains('$kind:$key')) continue;
          await db.customStatement(
            'INSERT INTO silinenler (kind, anahtar, deleted_at) VALUES (?, ?, ?) '
            'ON CONFLICT (kind, anahtar) DO UPDATE SET deleted_at = excluded.deleted_at',
            [kind, key, at],
          );
        }
      }
    });

    return ImportResult(
      habits: habitMaps.length,
      entries: importedEntries,
      moods: moodMaps.length,
      tasks: taskMaps.length,
      sessions: importedSessions,
    );
  }

  /// Puts the file's `updatedAt` back on a row that was just written.
  ///
  /// Writing a row stamps it "now" (a trigger); a merge must instead keep the
  /// file's value, or an old backup would look like the newest edit and beat
  /// real changes made elsewhere. No-op for files without the field (v1-v4).
  Future<void> _restoreStamp(
    String table,
    String where,
    List<Object> args,
    int? stamp,
  ) async {
    if (stamp == null) return;
    await db.customStatement(
      'UPDATE $table SET updated_at = ? WHERE $where',
      [stamp, ...args],
    );
  }

  /// A usable uid from the file, or null when it is absent, silly, or already
  /// used earlier in the same file (the row then gets a fresh uid).
  static String? _uid(dynamic v, Set<String> seen) {
    if (v is! String || v.isEmpty || v.length > 64) return null;
    return seen.add(v) ? v : null;
  }

  /// File timestamp -> unix seconds (at least 1, since 0 means "unstamped").
  static int? _secs(dynamic v) {
    final d = _parseDate(v);
    if (d == null) return null;
    final s = d.millisecondsSinceEpoch ~/ 1000;
    return s < 1 ? 1 : s;
  }

  static String _isoSecs(int secs) => DateTime.fromMillisecondsSinceEpoch(
        secs * 1000,
        isUtc: true,
      ).toIso8601String();

  static _KnownRow? _findByUid(List<_KnownRow> known, String? uid) {
    if (uid == null) return null;
    for (final row in known) {
      if (row.uid == uid) return row;
    }
    return null;
  }

  /// Finds the local row a backup row stands for, or null when it is new.
  ///
  /// The same id wins, but only together with the same creation time (to the
  /// second), or the same [label] when the file carries no creation time.
  /// Failing that, a row with the same creation time *and* label under another
  /// id still counts (an earlier merge of this file renumbered it); with no
  /// creation time to go by, the label alone has to do.
  static _KnownRow? _findKnown(
    List<_KnownRow> known, {
    required int fileId,
    required String label,
    required DateTime? createdAt,
  }) {
    for (final row in known) {
      if (row.id != fileId) continue;
      final same = createdAt == null
          ? row.label == label
          : _sameSecond(row.createdAt, createdAt);
      if (same) return row;
    }
    for (final row in known) {
      if (row.label != label) continue;
      if (createdAt == null || _sameSecond(row.createdAt, createdAt)) return row;
    }
    return null;
  }

  /// Translates an id from the file: through [mapped] when the file defined
  /// that row itself, otherwise it can only mean a row already here under that
  /// id ([existsHere]). Null when it cannot be resolved at all.
  static Future<int?> _resolveId(
    int? fileId,
    Map<int, int> mapped,
    Future<bool> Function(int id) existsHere,
  ) async {
    if (fileId == null) return null;
    final translated = mapped[fileId];
    if (translated != null) return translated;
    return await existsHere(fileId) ? fileId : null;
  }

  static bool _sameSecond(DateTime a, DateTime b) =>
      a.millisecondsSinceEpoch ~/ 1000 == b.millisecondsSinceEpoch ~/ 1000;

  /// The database keeps times to the second, so sessions compare that way.
  static String _sessionKey(String kind, DateTime startedAt, int durationS, String day) =>
      '$kind|${startedAt.millisecondsSinceEpoch ~/ 1000}|$durationS|$day';

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

/// What merging needs to know about a habit or task that already exists here:
/// its id, its name/title and when it was created.
class _KnownRow {
  final int id;
  String label;
  final DateTime createdAt;
  String? uid;
  _KnownRow(this.id, this.label, this.createdAt, [this.uid]);
}
