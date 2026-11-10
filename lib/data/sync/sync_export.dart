import 'dart:convert';

import '../../core/constants.dart';
import '../database/database.dart';
import 'sync_format.dart';

int _secs(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

/// The whole state of [db] as a `.habitsync` document (UTF-8 JSON text).
///
/// Always the full state, never a delta: importing it anywhere is idempotent.
/// Device-only data (theme, reminder, window placement, ids) is left out.
Future<String> exportSync(
  AppDatabase db, {
  String deviceName = 'Masaüstü',
  DateTime? now,
}) async {
  final habits = await db.getAllHabits();
  final entries = await db.getAllEntries();
  final moods = await db.getAllMoods();
  final tasks = await db.getAllTasks();
  final sessions = await db.getAllSessions();
  final tombs = await db.select(db.silinenler).get();

  final habitUid = {for (final h in habits) h.id: h.uid};
  final taskUid = {for (final t in tasks) t.id: t.uid};

  final dayStart = await db.getSetting(AppConstants.dayStartHourKey);
  final dayStartStamp =
      int.tryParse(await db.getSetting(AppConstants.dayStartHourStampKey) ?? '');

  final doc = <String, dynamic>{
    'format': syncFormat,
    'version': syncVersion,
    'created_at': syncTime(_secs(now ?? DateTime.now())),
    'device': {'name': deviceName, 'app': 'habit-tracker-desktop'},
    'settings': {
      if (int.tryParse(dayStart ?? '') != null)
        'day_start_hour': {
          'value': int.parse(dayStart!),
          'updated_at': syncTime(dayStartStamp ?? 1),
        },
    },
    'habits': [
      for (final h in habits)
        if (h.uid != null)
          {
            'uid': h.uid,
            'name': h.name,
            'description': h.description,
            'color_value': h.colorValue,
            'icon_code_point': h.iconCodePoint,
            'category': h.category,
            'kind': h.kind,
            'target': h.target,
            'created_at': syncTime(_secs(h.createdAt)),
            'archived_at':
                h.archivedAt == null ? null : syncTime(_secs(h.archivedAt!)),
            'sort_order': h.sortOrder,
            'scheduled_weekdays': h.scheduledWeekdays,
            'updated_at': syncTime(h.updatedAt),
          },
    ],
    'entries': [
      for (final e in entries)
        if (habitUid[e.habitId] != null)
          {
            'habit_uid': habitUid[e.habitId],
            'date': e.date,
            'status': e.status.name,
            'value': e.value,
            'created_at': syncTime(_secs(e.createdAt)),
            'updated_at': syncTime(e.updatedAt),
          },
    ],
    'moods': [
      for (final m in moods)
        {
          'date': m.date,
          'mood': m.mood,
          'note': m.note,
          'created_at': syncTime(_secs(m.createdAt)),
          'updated_at': syncTime(m.updatedAt),
        },
    ],
    'tasks': [
      for (final t in tasks)
        if (t.uid != null)
          {
            'uid': t.uid,
            'title': t.title,
            'status': t.status,
            'priority': t.priority,
            'due_day': t.dueDay,
            'created_at': syncTime(_secs(t.createdAt)),
            'completed_at':
                t.completedAt == null ? null : syncTime(_secs(t.completedAt!)),
            'updated_at': syncTime(t.updatedAt),
          },
    ],
    'sessions': [
      for (final s in sessions)
        if (s.uid != null)
          {
            'uid': s.uid,
            'kind': s.kind,
            'started_at': syncTime(_secs(s.startedAt)),
            'ended_at': s.endedAt == null ? null : syncTime(_secs(s.endedAt!)),
            'duration_s': s.durationS,
            'day': s.day,
            'task_uid': s.taskId == null ? null : taskUid[s.taskId],
            'updated_at': syncTime(s.updatedAt),
          },
    ],
    'deleted': [
      for (final d in tombs)
        {
          'kind': d.kind,
          'key': d.anahtar,
          'deleted_at': syncTime(d.deletedAt),
        },
    ],
  };
  return jsonEncode(doc);
}

/// Suggested file name, e.g. `habit-20261110-0930.habitsync`.
String syncFileName([DateTime? now]) {
  final n = now ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return 'habit-${n.year}${two(n.month)}${two(n.day)}-${two(n.hour)}${two(n.minute)}'
      '.$syncExtension';
}
