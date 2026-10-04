import '../data/database/database.dart';
import 'constants.dart';
import 'date_utils.dart';
import 'enums.dart';

/// Task grouping and ordering rules. Pure functions — no Flutter, no database
/// calls; the caller hands in the rows and the current tracking day.

/// A task's urgency relative to [todayDay], used for grouping and colouring.
enum DueBucket {
  /// Past its due date and not finished.
  overdue,
  today,
  tomorrow,

  /// Due within the next 7 days.
  thisWeek,

  /// Due further out.
  later,

  /// No due date at all.
  someday,
}

DueBucket bucketFor(Task task, DateTime todayDay) {
  final due = task.dueDay;
  if (due == null || due.isEmpty) return DueBucket.someday;

  final dueDay = parseYmd(due);
  // Calendar-day difference: `difference().inDays` counts 24-hour blocks, so
  // a 23-hour daylight-saving day would read one day too early.
  final diff = calendarDaysBetween(todayDay, dueDay);
  if (diff < 0) return DueBucket.overdue;
  if (diff == 0) return DueBucket.today;
  if (diff == 1) return DueBucket.tomorrow;
  if (diff <= 7) return DueBucket.thisWeek;
  return DueBucket.later;
}

/// Sorts open work the way it should be read: overdue first, then by due date,
/// then high priority, then oldest. Finished tasks always sink to the bottom.
int compareTasks(Task a, Task b, DateTime todayDay) {
  final aDone = TaskStatus.fromStorage(a.status) == TaskStatus.done;
  final bDone = TaskStatus.fromStorage(b.status) == TaskStatus.done;
  if (aDone != bDone) return aDone ? 1 : -1;

  // Doing beats todo — what you already started deserves finishing.
  final aDoing = TaskStatus.fromStorage(a.status) == TaskStatus.doing;
  final bDoing = TaskStatus.fromStorage(b.status) == TaskStatus.doing;
  if (aDoing != bDoing) return aDoing ? -1 : 1;

  final aBucket = bucketFor(a, todayDay).index;
  final bBucket = bucketFor(b, todayDay).index;
  if (aBucket != bBucket) return aBucket.compareTo(bBucket);

  if (a.priority != b.priority) return b.priority.compareTo(a.priority);
  return a.createdAt.compareTo(b.createdAt);
}

List<Task> sortTasks(List<Task> tasks, DateTime todayDay) {
  final copy = [...tasks];
  copy.sort((a, b) => compareTasks(a, b, todayDay));
  return copy;
}

/// Open (not done) tasks due on or before [todayDay] + 6 — the dashboard's
/// "this week" block. Undated tasks are excluded: they are not a commitment.
List<Task> thisWeek(List<Task> tasks, DateTime todayDay) {
  final result = tasks.where((t) {
    if (TaskStatus.fromStorage(t.status) == TaskStatus.done) return false;
    final bucket = bucketFor(t, todayDay);
    return bucket == DueBucket.overdue ||
        bucket == DueBucket.today ||
        bucket == DueBucket.tomorrow ||
        bucket == DueBucket.thisWeek;
  }).toList();
  return sortTasks(result, todayDay);
}

/// Counts for the dashboard header.
class TaskSummary {
  final int open;
  final int doing;
  final int overdue;
  final int dueToday;
  final int doneToday;

  const TaskSummary({
    required this.open,
    required this.doing,
    required this.overdue,
    required this.dueToday,
    required this.doneToday,
  });

  static const empty =
      TaskSummary(open: 0, doing: 0, overdue: 0, dueToday: 0, doneToday: 0);
}

TaskSummary summarise(
  List<Task> tasks,
  DateTime todayDay, {
  int dayStartHour = AppConstants.defaultDayStartHour,
}) {
  int open = 0, doing = 0, overdue = 0, dueToday = 0, doneToday = 0;
  final todayStr = formatYmd(todayDay);

  for (final t in tasks) {
    final status = TaskStatus.fromStorage(t.status);
    if (status == TaskStatus.done) {
      // "Done today" maps the completion stamp onto the tracking day, so a
      // task ticked at 01:00 counts for the day that is ending.
      final completed = t.completedAt;
      if (completed != null &&
          formatYmd(dayOf(completed, dayStartHour: dayStartHour)) == todayStr) {
        doneToday++;
      }
      continue;
    }
    open++;
    if (status == TaskStatus.doing) doing++;
    switch (bucketFor(t, todayDay)) {
      case DueBucket.overdue:
        overdue++;
      case DueBucket.today:
        dueToday++;
      default:
        break;
    }
  }

  return TaskSummary(
    open: open,
    doing: doing,
    overdue: overdue,
    dueToday: dueToday,
    doneToday: doneToday,
  );
}
