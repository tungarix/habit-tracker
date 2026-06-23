import 'package:flutter/material.dart';

import '../../../core/date_utils.dart';
import '../../../data/database/database.dart';

/// Weekly completion-rate bars for the last [weeks] weeks. Hand-drawn so we
/// carry no chart dependency that could drift across Flutter versions.
class TrendChart extends StatelessWidget {
  final Habit habit;
  final Set<String> doneDates;
  final int weeks;

  const TrendChart({
    super.key,
    required this.habit,
    required this.doneDates,
    this.weeks = 12,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = Color(habit.colorValue);
    final t = today();
    final created = dateOnly(habit.createdAt);
    final mondayThisWeek = t.subtract(Duration(days: t.weekday - 1));

    final bars = <_WeekRate>[];
    for (var w = weeks - 1; w >= 0; w--) {
      final weekStart = mondayThisWeek.subtract(Duration(days: w * 7));
      int scheduled = 0;
      int done = 0;
      for (var i = 0; i < 7; i++) {
        final day = weekStart.add(Duration(days: i));
        if (day.isAfter(t) || day.isBefore(created)) continue;
        if (!isScheduledOn(habit.scheduledWeekdays, day)) continue;
        scheduled++;
        if (doneDates.contains(formatYmd(day))) done++;
      }
      final rate = scheduled == 0 ? null : done / scheduled;
      bars.add(_WeekRate(weekStart, rate));
    }

    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final b in bars)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: (b.rate ?? 0).clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: b.rate == null
                                  ? scheme.surfaceContainerHighest
                                  : color.withValues(alpha: 0.4 + 0.6 * b.rate!),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('${b.weekStart.day}/${b.weekStart.month}',
                        style: TextStyle(fontSize: 8, color: scheme.outline)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WeekRate {
  final DateTime weekStart;
  final double? rate; // null = nothing scheduled
  _WeekRate(this.weekStart, this.rate);
}
