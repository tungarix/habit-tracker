import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../../core/enums.dart';
import '../database/database.dart';
import 'sync_format.dart';
import 'sync_parse.dart';

/// Merges a `.habitsync` file into [db] (docs/senkron.md §3).
///
/// Last writer wins per record; deletes travel as tombstones; a tie keeps the
/// local row. Stamps (`updated_at`, `deleted_at`) are copied from the file, never
/// set to "now", so importing the same file twice changes nothing.
///
/// All or nothing: the file is validated first and the merge runs in one
/// transaction, so any failure leaves the database as it was.
Future<SyncReport> importSyncBytes(AppDatabase db, Uint8List bytes) async {
  final file = parseSync(bytes);
  return db.transaction(() => _Merge(db, file).run());
}

/// Thrown inside the preview transaction to roll it back; carries the report.
class _PreviewRollback implements Exception {
  _PreviewRollback(this.report);
  final SyncReport report;
}

/// What [importSyncBytes] would do, without doing it: the same merge runs in a
/// transaction that is always rolled back (tombstone rows included), so the
/// counts come from the real code and the data stays as it was.
Future<SyncReport> previewSyncBytes(AppDatabase db, Uint8List bytes) async {
  final file = parseSync(bytes);
  try {
    await db.transaction<void>(() async {
      final report = await _Merge(db, file).run();
      throw _PreviewRollback(report);
    });
  } on _PreviewRollback catch (e) {
    return e.report;
  }
  throw StateError('preview transaction did not roll back');
}

/// Same as [importSyncBytes] for text already in memory.
Future<SyncReport> importSyncText(AppDatabase db, String text) =>
    importSyncBytes(db, Uint8List.fromList(utf8.encode(text)));

DateTime _dt(int secs) => DateTime.fromMillisecondsSinceEpoch(secs * 1000);

bool _sameSecond(DateTime a, DateTime b) =>
    a.millisecondsSinceEpoch ~/ 1000 == b.millisecondsSinceEpoch ~/ 1000;

/// Backup's session identity (kind + start + length + day); sync adopts the
/// file's uid for a local session that has it. Mirrors BackupRepository.
String _sessionKey(String kind, int startedSecs, int durationS, String day) =>
    '$kind|$startedSecs|$durationS|$day';

class _Merge {
  _Merge(this.db, this.f);
  final AppDatabase db;
  final SyncFile f;
  final report = SyncReport();

  // Local state, loaded once and kept current as the merge writes.
  final habitByUid = <String, Habit>{};
  final taskByUid = <String, Task>{};
  final sessionByUid = <String, FocusSession>{};
  final entryByKey = <String, HabitEntry>{}; // habitUid|date
  final moodByDate = <String, MoodEntry>{};
  final tombAt = <String, int>{}; // kind:key -> deleted_at

  String _tk(String kind, String key) => '$kind:$key';

  Future<SyncReport> run() async {
    await _load();
    await _settings();
    await _habits();
    await _tasks();
    await _entries();
    await _moods();
    await _sessions();
    await _deletions();
    return report;
  }

  Future<void> _load() async {
    final habits = await db.getAllHabits();
    for (final h in habits) {
      if (h.uid != null) habitByUid[h.uid!] = h;
    }
    for (final t in await db.getAllTasks()) {
      if (t.uid != null) taskByUid[t.uid!] = t;
    }
    for (final s in await db.getAllSessions()) {
      if (s.uid != null) sessionByUid[s.uid!] = s;
    }
    for (final m in await db.getAllMoods()) {
      moodByDate[m.date] = m;
    }
    for (final t in await db.select(db.silinenler).get()) {
      tombAt[_tk(t.kind, t.anahtar)] = t.deletedAt;
    }
  }

  // -- settings ---------------------------------------------------------------

  Future<void> _settings() async {
    final s = f.dayStartHour;
    if (s == null) return;
    final localStamp =
        int.tryParse(await db.getSetting(AppConstants.dayStartHourStampKey) ?? '') ?? 0;
    if (s.updatedAt <= localStamp) return;
    final localValue =
        int.tryParse(await db.getSetting(AppConstants.dayStartHourKey) ?? '');
    if (localValue != s.value) {
      await db.setSetting(AppConstants.dayStartHourKey, '${s.value}');
      report.setting.updated++;
    }
    // The write above stamped "now"; the file's stamp is the truth.
    await db.setSetting(AppConstants.dayStartHourStampKey, '${s.updatedAt}');
  }

  // -- habits -----------------------------------------------------------------

  Future<void> _habits() async {
    final fileUids = {for (final h in f.habits) h.uid};
    final adopted = <int>{};
    for (final h in f.habits) {
      var local = habitByUid[h.uid];
      if (local == null) {
        final t = tombAt[_tk('habit', h.uid)];
        if (t != null && h.updatedAt < t) {
          report.habit.skipped++; // deleted here after this version was saved
          continue;
        }
        local = _adoptHabit(h, fileUids, adopted);
        if (local == null) {
          await _insertHabit(h);
          report.habit.added++;
          continue;
        }
        final oldUid = local.uid;
        await (db.update(db.habits)..where((r) => r.id.equals(local!.id)))
            .write(HabitsCompanion(uid: Value(h.uid)));
        habitByUid.remove(oldUid);
        await _rekeyCellTombstones(oldUid, h.uid);
        local = local.copyWith(uid: Value(h.uid));
        habitByUid[h.uid] = local;
        adopted.add(local.id);
        report.adopted++;
      }
      if (h.updatedAt > local.updatedAt) {
        final next = HabitsCompanion(
          name: Value(h.name),
          description: Value(h.description),
          colorValue: Value(h.colorValue),
          iconCodePoint: Value(h.iconCodePoint),
          category: Value(h.category),
          kind: Value(h.kind),
          target: Value(h.target),
          createdAt: Value(_dt(h.createdAt)),
          archivedAt: Value(h.archivedAt == null ? null : _dt(h.archivedAt!)),
          sortOrder: Value(h.sortOrder),
          scheduledWeekdays: Value(h.scheduledWeekdays),
          updatedAt: Value(h.updatedAt),
        );
        await (db.update(db.habits)..where((r) => r.id.equals(local!.id))).write(next);
        habitByUid[h.uid] = (await db.getHabit(local.id))!;
        report.habit.updated++;
      }
    }
  }

  /// A habit that takes a new uid keeps its cleared-cell tombstones, which are
  /// keyed `habitUid|date`.
  Future<void> _rekeyCellTombstones(String? oldUid, String newUid) async {
    if (oldUid == null) return;
    await db.customStatement(
      "UPDATE silinenler SET anahtar = ? || substr(anahtar, ?) "
      "WHERE kind = 'entry' AND substr(anahtar, 1, ?) = ?",
      [newUid, oldUid.length + 1, oldUid.length + 1, '$oldUid|'],
    );
    final moved = {
      for (final e in tombAt.entries)
        if (e.key.startsWith('entry:$oldUid|')) e.key: e.value,
    };
    for (final e in moved.entries) {
      tombAt.remove(e.key);
      tombAt['entry:$newUid|${e.key.substring('entry:$oldUid|'.length)}'] = e.value;
    }
  }

  /// First-match rule: a local habit without a counterpart by uid that has the
  /// file habit's name and creation second is the same habit; it takes the
  /// file's uid. Rows whose uid the file mentions are never taken.
  Habit? _adoptHabit(SHabit h, Set<String> fileUids, Set<int> adopted) {
    for (final l in habitByUid.values) {
      if (adopted.contains(l.id) || fileUids.contains(l.uid)) continue;
      if (l.name == h.name && _sameSecond(l.createdAt, _dt(h.createdAt))) return l;
    }
    return null;
  }

  Future<void> _insertHabit(SHabit h) async {
    final id = await db.into(db.habits).insert(HabitsCompanion.insert(
          uid: Value(h.uid),
          updatedAt: Value(h.updatedAt),
          name: h.name,
          description: Value(h.description),
          colorValue: h.colorValue,
          iconCodePoint: h.iconCodePoint,
          category: Value(h.category),
          kind: Value(h.kind),
          target: Value(h.target),
          createdAt: Value(_dt(h.createdAt)),
          archivedAt: Value(h.archivedAt == null ? null : _dt(h.archivedAt!)),
          sortOrder: Value(h.sortOrder),
          scheduledWeekdays: Value(h.scheduledWeekdays),
        ));
    habitByUid[h.uid] = (await db.getHabit(id))!;
    tombAt.remove(_tk('habit', h.uid)); // the insert trigger cleared it
  }

  // -- tasks ------------------------------------------------------------------

  Future<void> _tasks() async {
    final fileUids = {for (final t in f.tasks) t.uid};
    final adopted = <int>{};
    for (final t in f.tasks) {
      var local = taskByUid[t.uid];
      if (local == null) {
        final tomb = tombAt[_tk('task', t.uid)];
        if (tomb != null && t.updatedAt < tomb) {
          report.task.skipped++;
          continue;
        }
        Task? match;
        for (final l in taskByUid.values) {
          if (adopted.contains(l.id) || fileUids.contains(l.uid)) continue;
          if (l.title == t.title && _sameSecond(l.createdAt, _dt(t.createdAt))) {
            match = l;
            break;
          }
        }
        if (match == null) {
          final id = await db.into(db.tasks).insert(TasksCompanion.insert(
                uid: Value(t.uid),
                updatedAt: Value(t.updatedAt),
                title: t.title,
                status: Value(t.status),
                priority: Value(t.priority),
                dueDay: Value(t.dueDay),
                createdAt: Value(_dt(t.createdAt)),
                completedAt: Value(t.completedAt == null ? null : _dt(t.completedAt!)),
              ));
          taskByUid[t.uid] = (await (db.select(db.tasks)..where((r) => r.id.equals(id)))
              .getSingle());
          tombAt.remove(_tk('task', t.uid));
          report.task.added++;
          continue;
        }
        await (db.update(db.tasks)..where((r) => r.id.equals(match!.id)))
            .write(TasksCompanion(uid: Value(t.uid)));
        local = match.copyWith(uid: Value(t.uid));
        taskByUid[t.uid] = local;
        adopted.add(local.id);
        report.adopted++;
      }
      if (t.updatedAt > local.updatedAt) {
        await (db.update(db.tasks)..where((r) => r.id.equals(local!.id))).write(
          TasksCompanion(
            title: Value(t.title),
            status: Value(t.status),
            priority: Value(t.priority),
            dueDay: Value(t.dueDay),
            createdAt: Value(_dt(t.createdAt)),
            completedAt: Value(t.completedAt == null ? null : _dt(t.completedAt!)),
            updatedAt: Value(t.updatedAt),
          ),
        );
        taskByUid[t.uid] = await (db.select(db.tasks)..where((r) => r.id.equals(local!.id)))
            .getSingle();
        report.task.updated++;
      }
    }
  }

  // -- entries ----------------------------------------------------------------

  EntryStatus _status(String name) =>
      EntryStatus.values.firstWhere((s) => s.name == name);

  Future<void> _entries() async {
    // Loaded now, not at the start: adopting a uid changes the key of every
    // cell of that habit.
    final uidOfHabit = {for (final h in habitByUid.values) h.id: h.uid};
    for (final e in await db.getAllEntries()) {
      final hu = uidOfHabit[e.habitId];
      if (hu != null) entryByKey['$hu|${e.date}'] = e;
    }
    for (final e in f.entries) {
      final habit = habitByUid[e.habitUid];
      if (habit == null) {
        report.entry.skipped++; // its habit is unknown or was deleted here
        continue;
      }
      final local = entryByKey[e.key];
      if (local == null) {
        final tomb = tombAt[_tk('entry', e.key)];
        if (tomb != null && e.updatedAt < tomb) {
          report.entry.skipped++; // cleared here after this mark was made
          continue;
        }
        await db.into(db.habitEntries).insert(HabitEntriesCompanion.insert(
              habitId: habit.id,
              date: e.date,
              status: _status(e.status),
              value: Value(e.value),
              createdAt: Value(_dt(e.createdAt)),
              updatedAt: Value(e.updatedAt),
            ));
        entryByKey[e.key] = (await db.getEntry(habit.id, e.date))!;
        tombAt.remove(_tk('entry', e.key));
        report.entry.added++;
      } else if (e.updatedAt > local.updatedAt) {
        await (db.update(db.habitEntries)..where((r) => r.id.equals(local.id))).write(
          HabitEntriesCompanion(
            status: Value(_status(e.status)),
            value: Value(e.value),
            createdAt: Value(_dt(e.createdAt)),
            updatedAt: Value(e.updatedAt),
          ),
        );
        entryByKey[e.key] = (await db.getEntry(habit.id, e.date))!;
        report.entry.updated++;
      }
    }
  }

  // -- moods ------------------------------------------------------------------

  Future<void> _moods() async {
    for (final m in f.moods) {
      final local = moodByDate[m.date];
      if (local == null) {
        final tomb = tombAt[_tk('mood', m.date)];
        if (tomb != null && m.updatedAt < tomb) {
          report.mood.skipped++;
          continue;
        }
        await db.into(db.moodEntries).insert(MoodEntriesCompanion.insert(
              date: m.date,
              mood: m.mood,
              note: Value(m.note),
              createdAt: Value(_dt(m.createdAt)),
              updatedAt: Value(m.updatedAt),
            ));
        moodByDate[m.date] = (await db.getMood(m.date))!;
        tombAt.remove(_tk('mood', m.date));
        report.mood.added++;
      } else if (m.updatedAt > local.updatedAt) {
        await (db.update(db.moodEntries)..where((r) => r.id.equals(local.id))).write(
          MoodEntriesCompanion(
            mood: Value(m.mood),
            note: Value(m.note),
            createdAt: Value(_dt(m.createdAt)),
            updatedAt: Value(m.updatedAt),
          ),
        );
        moodByDate[m.date] = (await db.getMood(m.date))!;
        report.mood.updated++;
      }
    }
  }

  // -- sessions ---------------------------------------------------------------

  /// The file's task as a local id; null when it is unknown here or deleted
  /// (tasks were merged first, so every task the file has is already known).
  int? _taskId(String? taskUid) =>
      taskUid == null ? null : taskByUid[taskUid]?.id;

  Future<void> _sessions() async {
    final fileUids = {for (final s in f.sessions) s.uid};
    final byKey = <String, FocusSession>{
      for (final s in sessionByUid.values)
        if (!fileUids.contains(s.uid))
          _sessionKey(s.kind, s.startedAt.millisecondsSinceEpoch ~/ 1000,
              s.durationS ?? 0, s.day): s,
    };
    for (final s in f.sessions) {
      var local = sessionByUid[s.uid];
      if (local == null) {
        final tomb = tombAt[_tk('session', s.uid)];
        if (tomb != null && s.updatedAt < tomb) {
          report.session.skipped++;
          continue;
        }
        final match = byKey.remove(
            _sessionKey(s.kind, s.startedAt, s.durationS ?? 0, s.day));
        if (match == null) {
          final id = await db.into(db.focusSessions).insert(
                FocusSessionsCompanion.insert(
                  uid: Value(s.uid),
                  updatedAt: Value(s.updatedAt),
                  kind: Value(s.kind),
                  startedAt: _dt(s.startedAt),
                  endedAt: Value(s.endedAt == null ? null : _dt(s.endedAt!)),
                  durationS: Value(s.durationS),
                  day: s.day,
                  taskId: Value(_taskId(s.taskUid)),
                ),
              );
          sessionByUid[s.uid] = await (db.select(db.focusSessions)
                ..where((r) => r.id.equals(id)))
              .getSingle();
          tombAt.remove(_tk('session', s.uid));
          report.session.added++;
          continue;
        }
        await (db.update(db.focusSessions)..where((r) => r.id.equals(match.id)))
            .write(FocusSessionsCompanion(uid: Value(s.uid)));
        local = match.copyWith(uid: Value(s.uid));
        sessionByUid[s.uid] = local;
        report.adopted++;
      }
      if (s.updatedAt > local.updatedAt) {
        await (db.update(db.focusSessions)..where((r) => r.id.equals(local!.id))).write(
          FocusSessionsCompanion(
            kind: Value(s.kind),
            startedAt: Value(_dt(s.startedAt)),
            endedAt: Value(s.endedAt == null ? null : _dt(s.endedAt!)),
            durationS: Value(s.durationS),
            day: Value(s.day),
            taskId: Value(_taskId(s.taskUid)),
            updatedAt: Value(s.updatedAt),
          ),
        );
        sessionByUid[s.uid] = await (db.select(db.focusSessions)
              ..where((r) => r.id.equals(local!.id)))
            .getSingle();
        report.session.updated++;
      }
    }
  }

  // -- deletions --------------------------------------------------------------

  Future<void> _deletions() async {
    for (final d in f.deleted) {
      final tk = _tk(d.kind, d.key);
      final updatedAt = switch (d.kind) {
        'habit' => habitByUid[d.key]?.updatedAt,
        'task' => taskByUid[d.key]?.updatedAt,
        'session' => sessionByUid[d.key]?.updatedAt,
        'entry' => entryByKey[d.key]?.updatedAt,
        _ => moodByDate[d.key]?.updatedAt,
      };
      if (updatedAt != null) {
        if (d.deletedAt <= updatedAt) {
          // The record was saved after (or at) the delete: it stays.
          _counts(d.kind).skipped++;
          continue;
        }
        await _deleteLocal(d);
        _counts(d.kind).deleted++;
      } else {
        final known = tombAt[tk];
        if (known != null && known >= d.deletedAt) continue;
      }
      // Keep the file's time (not "now"), or a delete echoes between devices.
      await db.customStatement(
        'INSERT INTO silinenler (kind, anahtar, deleted_at) VALUES (?, ?, ?) '
        'ON CONFLICT (kind, anahtar) DO UPDATE SET deleted_at = excluded.deleted_at',
        [d.kind, d.key, d.deletedAt],
      );
      tombAt[tk] = d.deletedAt;
    }
  }

  SyncCounts _counts(String kind) => switch (kind) {
        'habit' => report.habit,
        'task' => report.task,
        'session' => report.session,
        'entry' => report.entry,
        _ => report.mood,
      };

  Future<void> _deleteLocal(STomb d) async {
    switch (d.kind) {
      case 'habit':
        final h = habitByUid.remove(d.key)!;
        await db.deleteHabit(h.id); // cascades to its cells
        entryByKey.removeWhere((k, _) => k.startsWith('${d.key}|'));
      case 'task':
        final t = taskByUid.remove(d.key)!;
        await db.deleteTask(t.id);
      case 'session':
        final s = sessionByUid.remove(d.key)!;
        await db.deleteSession(s.id);
      case 'entry':
        final e = entryByKey.remove(d.key)!;
        await (db.delete(db.habitEntries)..where((r) => r.id.equals(e.id))).go();
      default:
        final m = moodByDate.remove(d.key)!;
        await (db.delete(db.moodEntries)..where((r) => r.id.equals(m.id))).go();
    }
  }
}
