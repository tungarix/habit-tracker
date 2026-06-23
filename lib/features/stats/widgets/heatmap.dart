import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/date_utils.dart';
import '../../../data/database/database.dart';

/// GitHub-style contribution heatmap for one habit.
///
/// Columns are weeks (Mon..Sun top to bottom). A scheduled+done day shows the
/// habit colour; a scheduled+missed day is a faint grey; unscheduled / future
/// days are nearly blank.
class HabitHeatmap extends StatelessWidget {
  final Habit habit;
  final Set<String> doneDates;
  final int weeks;

  const HabitHeatmap({
    super.key,
    required this.habit,
    required this.doneDates,
    this.weeks = 26,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = Color(habit.colorValue);
    final t = today();

    // Last column ends this week; align start to the Monday `weeks-1` weeks ago.
    final mondayThisWeek = t.subtract(Duration(days: t.weekday - 1));
    final start = mondayThisWeek.subtract(Duration(days: (weeks - 1) * 7));
    final createdDay = dateOnly(habit.createdAt);

    final columns = <Widget>[];
    String? lastMonthLabel;

    for (var w = 0; w < weeks; w++) {
      final weekStart = start.add(Duration(days: w * 7));

      // Month label above the first column of each new month.
      final monthLabel = DateFormat('MMM', 'tr').format(weekStart);
      final showLabel = monthLabel != lastMonthLabel;
      lastMonthLabel = monthLabel;

      final cells = <Widget>[];
      for (var d = 0; d < 7; d++) {
        final day = weekStart.add(Duration(days: d));
        cells.add(_cell(context, day, t, createdDay, color, scheme));
      }

      columns.add(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 14,
            child: showLabel
                ? Text(monthLabel, style: TextStyle(fontSize: 9, color: scheme.outline))
                : null,
          ),
          ...cells,
        ],
      ));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: columns),
    );
  }

  Widget _cell(BuildContext context, DateTime day, DateTime t, DateTime created,
      Color color, ColorScheme scheme) {
    Color fill;
    if (day.isAfter(t) || day.isBefore(created)) {
      fill = scheme.surfaceContainerHighest.withValues(alpha: 0.3);
    } else if (!isScheduledOn(habit.scheduledWeekdays, day)) {
      fill = scheme.surfaceContainerHighest.withValues(alpha: 0.3);
    } else if (doneDates.contains(formatYmd(day))) {
      fill = color;
    } else {
      fill = scheme.surfaceContainerHighest;
    }

    return Container(
      width: 14,
      height: 14,
      margin: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(3)),
    );
  }
}
