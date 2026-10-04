import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/date_utils.dart';
import '../core/enums.dart';
import '../core/streak.dart';
import '../data/database/database.dart';
import '../data/providers.dart';
import 'widgets/count_entry_dialog.dart';

/// Marking a habit for a day, in one place so every screen behaves the same.
///
/// Bool habits cycle ✓ → ✗ → – → boş on tap. Count habits open an amount
/// entry instead, because a tick cannot express "7 500 of 10 000 steps".
Future<void> markHabit(
  BuildContext context,
  WidgetRef ref,
  Habit habit,
  DateTime day, {
  int currentValue = 0,
}) async {
  final dateStr = formatYmd(day);
  final repo = ref.read(habitRepositoryProvider);
  final isCount = habit.kind == HabitKind.count.storageName && habit.target > 1;

  EntryStatus? next;
  if (isCount) {
    final amount = await CountEntryDialog.show(
      context,
      habit: habit,
      current: currentValue,
    );
    if (amount == null) return; // cancelled
    await repo.setAmount(habit.id, dateStr, amount, habit.target);
    next = amount >= habit.target ? EntryStatus.done : null;
  } else {
    next = await repo.cycle(habit.id, dateStr);
  }

  if (next == EntryStatus.done && context.mounted) {
    _celebrateMilestone(context, ref, habit, day, dateStr);
  }
}

/// Quiet milestone note every 7th day of a streak — a nod, not confetti.
void _celebrateMilestone(
  BuildContext context,
  WidgetRef ref,
  Habit habit,
  DateTime day,
  String dateStr,
) {
  final statuses = {
    ...ref.read(habitStatusesProvider(habit.id)),
    dateStr: EntryStatus.done,
  };
  final streak = computeStreaks(
    habit,
    statuses,
    day,
    dayStartHour: ref.read(dayStartHourProvider),
  ).current;
  if (streak <= 0 || streak % 7 != 0) return;

  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      duration: const Duration(seconds: 2),
      content: Text('🔥 ${habit.name}: $streak gün seri — devam!'),
    ));
}
