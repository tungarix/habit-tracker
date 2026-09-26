import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../core/date_utils.dart';
import '../core/enums.dart';
import '../core/sessions.dart';
import '../core/stats.dart';
import '../core/streak.dart';
import '../core/tasks.dart' as task_logic;
import 'database/database.dart';
import 'models/habit_today_view.dart';
import 'repositories/backup_repository.dart';
import 'repositories/habit_repository.dart';
import 'repositories/session_repository.dart';
import 'repositories/task_repository.dart';

/// Single database instance for the whole app.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final habitRepositoryProvider = Provider<HabitRepository>(
  (ref) => HabitRepository(ref.watch(databaseProvider)),
);

final backupRepositoryProvider = Provider<BackupRepository>(
  (ref) => BackupRepository(ref.watch(databaseProvider)),
);

final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => TaskRepository(ref.watch(databaseProvider)),
);

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => SessionRepository(ref.watch(databaseProvider)),
);

// -----------------------------------------------------------------------------
// Theme
// -----------------------------------------------------------------------------

/// Theme preference, persisted in the settings table. Dark is the default.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _load();
    return ThemeMode.dark;
  }

  Future<void> _load() async {
    final stored = await ref
        .read(databaseProvider)
        .getSetting(AppConstants.themeModeKey);
    if (stored == 'light') state = ThemeMode.light;
  }

  Future<void> toggle() async {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await ref
        .read(databaseProvider)
        .setSetting(
          AppConstants.themeModeKey,
          state == ThemeMode.light ? 'light' : 'dark',
        );
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

// -----------------------------------------------------------------------------
// The tracking day
// -----------------------------------------------------------------------------

/// Hour at which a new tracking day starts, persisted in settings.
///
/// Default 4: a habit ticked at 01:30 belongs to the day that is ending, not
/// the one just begun. (Two thirds of this user's marks are written after
/// midnight or backfilled, so this is not a theoretical concern.)
class DayStartHourNotifier extends Notifier<int> {
  @override
  int build() {
    _load();
    return AppConstants.defaultDayStartHour;
  }

  Future<void> _load() async {
    final stored = await ref
        .read(databaseProvider)
        .getSetting(AppConstants.dayStartHourKey);
    final parsed = int.tryParse(stored ?? '');
    if (parsed != null && parsed >= 0 && parsed <= 12) state = parsed;
  }

  Future<void> set(int hour) async {
    state = hour.clamp(0, 12);
    await ref
        .read(databaseProvider)
        .setSetting(AppConstants.dayStartHourKey, '$state');
  }
}

final dayStartHourProvider = NotifierProvider<DayStartHourNotifier, int>(
  DayStartHourNotifier.new,
);

// -----------------------------------------------------------------------------
// Evening reminder
// -----------------------------------------------------------------------------

/// Hour (0-23) the evening reminder notification fires at; null = off.
/// [TrayService] reads this to decide when to nudge.
class ReminderHourNotifier extends Notifier<int?> {
  @override
  int? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    final stored = await ref
        .read(databaseProvider)
        .getSetting(AppConstants.reminderHourKey);
    final parsed = int.tryParse(stored ?? '');
    if (parsed != null && parsed >= 0 && parsed <= 23) state = parsed;
  }

  Future<void> set(int? hour) async {
    state = hour;
    await ref
        .read(databaseProvider)
        .setSetting(AppConstants.reminderHourKey, hour == null ? '' : '$hour');
  }
}

final reminderHourProvider = NotifierProvider<ReminderHourNotifier, int?>(
  ReminderHourNotifier.new,
);

/// The current tracking day. **Every screen must read the day from here** so
/// the day-start rule stays in one place — and so an app left open overnight
/// rolls over on its own instead of showing yesterday.
final todayProvider = Provider<DateTime>((ref) {
  final hour = ref.watch(dayStartHourProvider);
  final now = DateTime.now();
  final boundary = nextDayBoundary(now, dayStartHour: hour);
  final timer = Timer(
    boundary.difference(now) + const Duration(seconds: 1),
    ref.invalidateSelf,
  );
  ref.onDispose(timer.cancel);
  return dayOf(now, dayStartHour: hour);
});

// -----------------------------------------------------------------------------
// Raw reactive sources
// -----------------------------------------------------------------------------

final activeHabitsProvider = StreamProvider<List<Habit>>(
  (ref) => ref.watch(habitRepositoryProvider).watchActiveHabits(),
);

final archivedHabitsProvider = StreamProvider<List<Habit>>(
  (ref) => ref.watch(habitRepositoryProvider).watchArchivedHabits(),
);

final allEntriesProvider = StreamProvider<List<HabitEntry>>(
  (ref) => ref.watch(habitRepositoryProvider).watchAllEntries(),
);

final allMoodsProvider = StreamProvider<List<MoodEntry>>(
  (ref) => ref.watch(habitRepositoryProvider).watchAllMoods(),
);

final allTasksProvider = StreamProvider<List<Task>>(
  (ref) => ref.watch(taskRepositoryProvider).watchAll(),
);

final allSessionsProvider = StreamProvider<List<FocusSession>>(
  (ref) => ref.watch(sessionRepositoryProvider).watchAll(),
);

// -----------------------------------------------------------------------------
// Derived views
// -----------------------------------------------------------------------------

/// Maps habitId -> (date -> status).
final statusesByHabitProvider =
    Provider<AsyncValue<Map<int, Map<String, EntryStatus>>>>((ref) {
      final entriesAsync = ref.watch(allEntriesProvider);
      return entriesAsync.whenData((entries) {
        final map = <int, Map<String, EntryStatus>>{};
        for (final e in entries) {
          (map[e.habitId] ??= <String, EntryStatus>{})[e.date] = e.status;
        }
        return map;
      });
    });

/// Maps habitId -> (date -> recorded amount). Only meaningful for count habits.
final valuesByHabitProvider = Provider<Map<int, Map<String, int>>>((ref) {
  final entries = ref.watch(allEntriesProvider).value ?? const <HabitEntry>[];
  final map = <int, Map<String, int>>{};
  for (final e in entries) {
    (map[e.habitId] ??= <String, int>{})[e.date] = e.value;
  }
  return map;
});

/// Maps date -> mood entry.
final moodByDateProvider = Provider<Map<String, MoodEntry>>((ref) {
  final moods = ref.watch(allMoodsProvider).value ?? const <MoodEntry>[];
  return {for (final m in moods) m.date: m};
});

/// Today's mood, if recorded.
final todayMoodProvider = Provider<MoodEntry?>(
  (ref) => ref.watch(moodByDateProvider)[formatYmd(ref.watch(todayProvider))],
);

/// Active habits decorated with today's status + current streak.
final todayViewsProvider = Provider<AsyncValue<List<HabitTodayView>>>((ref) {
  final habitsAsync = ref.watch(activeHabitsProvider);
  final statusesAsync = ref.watch(statusesByHabitProvider);

  if (habitsAsync.isLoading || statusesAsync.isLoading) {
    return const AsyncValue.loading();
  }
  if (habitsAsync.hasError) {
    return AsyncValue.error(habitsAsync.error!, habitsAsync.stackTrace!);
  }
  if (statusesAsync.hasError) {
    return AsyncValue.error(statusesAsync.error!, statusesAsync.stackTrace!);
  }

  final habits = habitsAsync.value!;
  final byHabit = statusesAsync.value!;
  final t = ref.watch(todayProvider);
  final tStr = formatYmd(t);

  final views = [
    for (final h in habits)
      HabitTodayView(
        habit: h,
        status: (byHabit[h.id] ?? const <String, EntryStatus>{})[tStr],
        scheduledToday: isScheduledOn(h.scheduledWeekdays, t),
        streak: computeStreaks(
          h,
          byHabit[h.id] ?? const <String, EntryStatus>{},
          t,
        ),
      ),
  ];

  // Scheduled-today habits first, then the rest.
  views.sort((a, b) {
    if (a.scheduledToday == b.scheduledToday) {
      return a.habit.sortOrder.compareTo(b.habit.sortOrder);
    }
    return a.scheduledToday ? -1 : 1;
  });

  return AsyncValue.data(views);
});

/// Statuses for a single habit (for stats / grids).
final habitStatusesProvider = Provider.family<Map<String, EntryStatus>, int>((
  ref,
  habitId,
) {
  final map = ref.watch(statusesByHabitProvider).value ?? const {};
  return map[habitId] ?? const <String, EntryStatus>{};
});

/// Lifetime stats for a single habit.
final habitStatsProvider = Provider.family<AsyncValue<HabitStats>, int>((
  ref,
  habitId,
) {
  final habitsAsync = ref.watch(activeHabitsProvider);
  final archivedAsync = ref.watch(archivedHabitsProvider);
  final statusesAsync = ref.watch(statusesByHabitProvider);

  if (statusesAsync.isLoading) return const AsyncValue.loading();

  final all = <Habit>[...?habitsAsync.value, ...?archivedAsync.value];
  Habit? habit;
  for (final h in all) {
    if (h.id == habitId) {
      habit = h;
      break;
    }
  }
  if (habit == null) return const AsyncValue.loading();

  final statuses =
      statusesAsync.value![habitId] ?? const <String, EntryStatus>{};
  return AsyncValue.data(
    computeStats(habit, statuses, ref.watch(todayProvider)),
  );
});

// -----------------------------------------------------------------------------
// Tasks
// -----------------------------------------------------------------------------

/// All tasks in reading order (see `core/tasks.dart`).
final sortedTasksProvider = Provider<List<Task>>((ref) {
  final tasks = ref.watch(allTasksProvider).value ?? const <Task>[];
  return task_logic.sortTasks(tasks, ref.watch(todayProvider));
});

/// Open tasks due within the coming week — the dashboard block.
final thisWeekTasksProvider = Provider<List<Task>>((ref) {
  final tasks = ref.watch(allTasksProvider).value ?? const <Task>[];
  return task_logic.thisWeek(tasks, ref.watch(todayProvider));
});

final taskSummaryProvider = Provider<task_logic.TaskSummary>((ref) {
  final tasks = ref.watch(allTasksProvider).value ?? const <Task>[];
  return task_logic.summarise(
    tasks,
    ref.watch(todayProvider),
    dayStartHour: ref.watch(dayStartHourProvider),
  );
});

// -----------------------------------------------------------------------------
// Focus sessions
// -----------------------------------------------------------------------------

final focusSummaryProvider = Provider<FocusSummary>((ref) {
  final sessions =
      ref.watch(allSessionsProvider).value ?? const <FocusSession>[];
  return summariseFocus(sessions, ref.watch(todayProvider));
});

/// Focus seconds per day for the last 14 days (dashboard sparkline).
final focusSeriesProvider = Provider<List<int>>((ref) {
  final sessions =
      ref.watch(allSessionsProvider).value ?? const <FocusSession>[];
  return focusSecondsSeries(sessions, ref.watch(todayProvider), 14);
});

// -----------------------------------------------------------------------------
// Dashboard aggregates
// -----------------------------------------------------------------------------

/// Today's habit progress: how many of the scheduled habits are ✓.
class TodayProgress {
  final int done;
  final int total;
  const TodayProgress({required this.done, required this.total});
  double get ratio => total == 0 ? 0 : done / total;
  static const empty = TodayProgress(done: 0, total: 0);
}

final todayProgressProvider = Provider<TodayProgress>((ref) {
  final views = ref.watch(todayViewsProvider).value;
  if (views == null) return TodayProgress.empty;
  final scheduled = views.where((v) => v.scheduledToday).toList();
  return TodayProgress(
    done: scheduled.where((v) => v.doneToday).length,
    total: scheduled.length,
  );
});

/// Rolling 7-day completion across every active habit.
final weekCompletionProvider = Provider<double>((ref) {
  final habits = ref.watch(activeHabitsProvider).value ?? const <Habit>[];
  final byHabit =
      ref.watch(statusesByHabitProvider).value ??
      const <int, Map<String, EntryStatus>>{};
  return lastNDaysCompletion(habits, byHabit, ref.watch(todayProvider), 7);
});

/// Aggregate numbers shown on the Stats overview.
class OverviewStats {
  final int totalMarks;
  final int bestCurrent;
  final int bestLongest;
  final int thisMonth;
  const OverviewStats({
    required this.totalMarks,
    required this.bestCurrent,
    required this.bestLongest,
    required this.thisMonth,
  });
  static const empty = OverviewStats(
    totalMarks: 0,
    bestCurrent: 0,
    bestLongest: 0,
    thisMonth: 0,
  );
}

/// Overview across all (active + archived) habits. Counts only ✓ marks.
final overviewProvider = Provider<OverviewStats>((ref) {
  final habits = <Habit>[
    ...?ref.watch(activeHabitsProvider).value,
    ...?ref.watch(archivedHabitsProvider).value,
  ];
  final byHabit = ref.watch(statusesByHabitProvider).value ?? const {};
  final t = ref.watch(todayProvider);
  final monthPrefix = formatYmd(t).substring(0, 7); // YYYY-MM

  int total = 0, thisMonth = 0, bestCur = 0, bestLong = 0;
  for (final h in habits) {
    final statuses = byHabit[h.id] ?? const <String, EntryStatus>{};
    for (final entry in statuses.entries) {
      if (entry.value != EntryStatus.done) continue;
      total++;
      if (entry.key.startsWith(monthPrefix)) thisMonth++;
    }
    final s = computeStreaks(h, statuses, t);
    if (s.current > bestCur) bestCur = s.current;
    if (s.longest > bestLong) bestLong = s.longest;
  }
  return OverviewStats(
    totalMarks: total,
    bestCurrent: bestCur,
    bestLongest: bestLong,
    thisMonth: thisMonth,
  );
});
