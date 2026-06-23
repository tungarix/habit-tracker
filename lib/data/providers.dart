import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/date_utils.dart';
import '../core/streak.dart';
import 'database/database.dart';
import 'models/habit_today_view.dart';
import 'repositories/backup_repository.dart';
import 'repositories/habit_repository.dart';

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

/// Raw reactive sources.
final activeHabitsProvider = StreamProvider<List<Habit>>(
  (ref) => ref.watch(habitRepositoryProvider).watchActiveHabits(),
);

final archivedHabitsProvider = StreamProvider<List<Habit>>(
  (ref) => ref.watch(habitRepositoryProvider).watchArchivedHabits(),
);

final allEntriesProvider = StreamProvider<List<HabitEntry>>(
  (ref) => ref.watch(habitRepositoryProvider).watchAllEntries(),
);

/// Maps habitId -> set of dates that are marked done.
final _doneDatesProvider = Provider<AsyncValue<Map<int, Set<String>>>>((ref) {
  final entriesAsync = ref.watch(allEntriesProvider);
  return entriesAsync.whenData((entries) {
    final map = <int, Set<String>>{};
    for (final e in entries) {
      if (e.done) (map[e.habitId] ??= <String>{}).add(e.date);
    }
    return map;
  });
});

/// Active habits decorated with today's status + current streak.
final todayViewsProvider = Provider<AsyncValue<List<HabitTodayView>>>((ref) {
  final habitsAsync = ref.watch(activeHabitsProvider);
  final doneAsync = ref.watch(_doneDatesProvider);

  if (habitsAsync.isLoading || doneAsync.isLoading) {
    return const AsyncValue.loading();
  }
  if (habitsAsync.hasError) {
    return AsyncValue.error(habitsAsync.error!, habitsAsync.stackTrace!);
  }
  if (doneAsync.hasError) {
    return AsyncValue.error(doneAsync.error!, doneAsync.stackTrace!);
  }

  final habits = habitsAsync.value!;
  final doneByHabit = doneAsync.value!;
  final t = today();
  final tStr = formatYmd(t);

  final views = [
    for (final h in habits)
      HabitTodayView(
        habit: h,
        doneToday: (doneByHabit[h.id] ?? const <String>{}).contains(tStr),
        scheduledToday: isScheduledOn(h.scheduledWeekdays, t),
        streak: computeStreaks(h, doneByHabit[h.id] ?? const <String>{}, t),
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

/// Done-dates for a single habit (for stats / heatmap).
final habitDoneDatesProvider = Provider.family<Set<String>, int>((ref, habitId) {
  final map = ref.watch(_doneDatesProvider).value ?? const {};
  return map[habitId] ?? const <String>{};
});

/// Lifetime stats for a single habit.
final habitStatsProvider = Provider.family<AsyncValue<HabitStats>, int>((ref, habitId) {
  final habitsAsync = ref.watch(activeHabitsProvider);
  final archivedAsync = ref.watch(archivedHabitsProvider);
  final doneAsync = ref.watch(_doneDatesProvider);

  if (doneAsync.isLoading) return const AsyncValue.loading();

  final all = <Habit>[
    ...?habitsAsync.value,
    ...?archivedAsync.value,
  ];
  Habit? habit;
  for (final h in all) {
    if (h.id == habitId) {
      habit = h;
      break;
    }
  }
  if (habit == null) return const AsyncValue.loading();

  final done = doneAsync.value![habitId] ?? const <String>{};
  return AsyncValue.data(computeStats(habit, done, today()));
});
