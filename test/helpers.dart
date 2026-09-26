import 'package:aktenak_habit_tracker/core/date_utils.dart';
import 'package:aktenak_habit_tracker/core/enums.dart';
import 'package:aktenak_habit_tracker/data/database/database.dart';

/// Shared fixtures. Keeping the row constructors in one place means a schema
/// change touches one file instead of every test.

Habit testHabit({
  int id = 1,
  String name = 'Test',
  DateTime? createdAt,
  String scheduledWeekdays = '',
  String category = 'beden',
  String kind = 'bool',
  int target = 1,
  DateTime? archivedAt,
  int sortOrder = 0,
}) {
  return Habit(
    id: id,
    name: name,
    description: null,
    colorValue: 0xFF4CAF50,
    iconCodePoint: 0xe000,
    category: category,
    kind: kind,
    target: target,
    createdAt: createdAt ?? DateTime(2026, 1, 1),
    archivedAt: archivedAt,
    sortOrder: sortOrder,
    scheduledWeekdays: scheduledWeekdays,
  );
}

/// Builds a date -> status map: every date in [done] is ✓, [missed] ✗,
/// [skipped] –. Dates absent from all three stay untracked.
Map<String, EntryStatus> statusMap({
  Iterable<DateTime> done = const [],
  Iterable<DateTime> missed = const [],
  Iterable<DateTime> skipped = const [],
}) {
  return {
    for (final d in done) formatYmd(d): EntryStatus.done,
    for (final d in missed) formatYmd(d): EntryStatus.missed,
    for (final d in skipped) formatYmd(d): EntryStatus.skipped,
  };
}

Task testTask({
  int id = 1,
  String title = 'Görev',
  TaskStatus status = TaskStatus.todo,
  TaskPriority priority = TaskPriority.normal,
  DateTime? dueDay,
  DateTime? createdAt,
  DateTime? completedAt,
}) {
  return Task(
    id: id,
    title: title,
    status: status.storageName,
    priority: priority.value,
    dueDay: dueDay == null ? null : formatYmd(dueDay),
    createdAt: createdAt ?? DateTime(2026, 1, 1),
    completedAt: completedAt,
  );
}

FocusSession testSession({
  int id = 1,
  SessionKind kind = SessionKind.focus,
  required DateTime day,
  int durationS = 1500,
}) {
  return FocusSession(
    id: id,
    kind: kind.storageName,
    startedAt: day,
    endedAt: day.add(Duration(seconds: durationS)),
    durationS: durationS,
    taskId: null,
    day: formatYmd(day),
  );
}

MoodEntry testMood(DateTime day, int mood, {String? note}) {
  return MoodEntry(
    id: mood * 1000 + day.day,
    date: formatYmd(day),
    mood: mood,
    note: note,
    createdAt: day,
  );
}
