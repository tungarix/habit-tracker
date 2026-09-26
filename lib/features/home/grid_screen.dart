import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/date_utils.dart';
import '../../core/enums.dart';
import '../../data/database/database.dart';
import '../../data/providers.dart';
import '../../shared/habit_actions.dart';
import '../../shared/habit_style.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/status_mark.dart';
import '../habits/habit_edit_dialog.dart';

const _monthsFullTr = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
];

/// Monthly grid, laid out like a classic paper tracker: rows are habits,
/// columns are the days of the month. Tap a cell to cycle ✓ → ✗ → – → boş.
/// Below the grid, the month's mood line is drawn on the same day axis.
///
/// Performance: the screen itself only watches the habit list; every cell
/// watches just its own (habit, day) status and the mood line has its own
/// consumer, so a tap repaints one cell instead of the whole grid.
class GridScreen extends ConsumerStatefulWidget {
  const GridScreen({super.key});

  @override
  ConsumerState<GridScreen> createState() => _GridScreenState();
}

class _GridScreenState extends ConsumerState<GridScreen> {
  static const double _labelW = 148;
  static const double _cellW = 44; // min touch target
  static const double _rowH = 44;
  static const double _headerH = 44;
  static const double _moodH = 120;

  DateTime _month = firstOfMonth(today());

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final habits = ref.watch(activeHabitsProvider).value;

    if (habits == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (habits.isEmpty) {
      return _EmptyState(onAdd: () => HabitEditDialog.show(context));
    }

    final t = ref.watch(todayProvider);
    final days = daysInMonth(_month);
    final isCurrentMonth = _month.year == t.year && _month.month == t.month;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _monthHeader(colors, isCurrentMonth),
        const SizedBox(height: 4),
        Expanded(
          child: SingleChildScrollView(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _labelColumn(colors, habits),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: days * _cellW,
                      child: Column(
                        children: [
                          RepaintBoundary(
                            child: _dayHeaderRow(colors, days, t),
                          ),
                          for (final h in habits)
                            RepaintBoundary(
                              child: _HabitRow(
                                habit: h,
                                month: _month,
                                days: days,
                                todayDate: t,
                                cellW: _cellW,
                                rowH: _rowH,
                              ),
                            ),
                          const SizedBox(height: 8),
                          RepaintBoundary(
                            child: _MoodLine(
                              month: _month,
                              days: days,
                              cellW: _cellW,
                              height: _moodH,
                              todayIndex: isCurrentMonth ? t.day - 1 : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _monthHeader(AppColors colors, bool isCurrentMonth) {
    return Row(
      children: [
        Text(
          '${_monthsFullTr[_month.month - 1]} ${_month.year}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 8),
        if (!isCurrentMonth)
          TextButton(
            onPressed: () => setState(
                () => _month = firstOfMonth(ref.read(todayProvider))),
            child: const Text('Bugüne dön'),
          ),
        const Spacer(),
        IconButton(
          tooltip: 'Önceki ay',
          icon: const Icon(Icons.chevron_left),
          onPressed: () => _shiftMonth(-1),
        ),
        IconButton(
          tooltip: 'Sonraki ay',
          icon: const Icon(Icons.chevron_right),
          onPressed: () => _shiftMonth(1),
        ),
      ],
    );
  }

  /// Fixed left pane: spacer for the day header, one label per habit, mood label.
  Widget _labelColumn(AppColors colors, List<Habit> habits) {
    return SizedBox(
      width: _labelW,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: _headerH),
          for (final h in habits)
            SizedBox(
              height: _rowH,
              child: Row(
                children: [
                  Icon(iconFromCodePoint(h.iconCodePoint),
                      size: 16, color: Color(h.colorValue)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      h.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            height: _moodH,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Mood',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.textDim)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayHeaderRow(AppColors colors, int days, DateTime t) {
    return SizedBox(
      height: _headerH,
      child: Row(
        children: [
          for (var d = 1; d <= days; d++)
            _dayHeaderCell(colors, DateTime(_month.year, _month.month, d), t),
        ],
      ),
    );
  }

  Widget _dayHeaderCell(AppColors colors, DateTime day, DateTime t) {
    final isToday = day == t;
    return SizedBox(
      width: _cellW,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: isToday
                ? BoxDecoration(color: colors.done, shape: BoxShape.circle)
                : null,
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                color: isToday ? Colors.white : colors.text,
              ),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            kWeekdayShort[day.weekday - 1].substring(0, 1),
            style: TextStyle(fontSize: 10, color: colors.textDim),
          ),
        ],
      ),
    );
  }
}

/// One habit's row of day cells. Stateless w.r.t. entry data — each cell
/// subscribes to its own status.
class _HabitRow extends StatelessWidget {
  final Habit habit;
  final DateTime month;
  final int days;
  final DateTime todayDate;
  final double cellW;
  final double rowH;
  const _HabitRow({
    required this.habit,
    required this.month,
    required this.days,
    required this.todayDate,
    required this.cellW,
    required this.rowH,
  });

  @override
  Widget build(BuildContext context) {
    final created = dateOnly(habit.createdAt);
    return SizedBox(
      height: rowH,
      child: Row(
        children: [
          for (var d = 1; d <= days; d++)
            _GridCell(
              habit: habit,
              day: DateTime(month.year, month.month, d),
              created: created,
              todayDate: todayDate,
              cellW: cellW,
              rowH: rowH,
            ),
        ],
      ),
    );
  }
}

/// A single day cell. Watches only its own status, so taps anywhere in the
/// grid rebuild exactly one cell.
class _GridCell extends ConsumerWidget {
  final Habit habit;
  final DateTime day;
  final DateTime created;
  final DateTime todayDate;
  final double cellW;
  final double rowH;
  const _GridCell({
    required this.habit,
    required this.day,
    required this.created,
    required this.todayDate,
    required this.cellW,
    required this.rowH,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final dateStr = formatYmd(day);
    final status = ref.watch(
      habitStatusesProvider(habit.id).select((m) => m[dateStr]),
    );

    final isFuture = day.isAfter(todayDate);
    final beforeCreated = day.isBefore(created);
    final scheduled = isScheduledOn(habit.scheduledWeekdays, day);
    final tappable = !isFuture && !beforeCreated;

    final Color fill;
    final Color glyphColor;
    if (status != null) {
      final c = statusColor(colors, status);
      fill = c.withValues(alpha: status == EntryStatus.done ? 1 : 0.22);
      glyphColor = status == EntryStatus.done ? Colors.white : c;
    } else {
      fill = colors.idle.withValues(
          alpha: (isFuture || beforeCreated || !scheduled) ? 0.45 : 1);
      glyphColor = Colors.transparent;
    }

    final icon = statusIcon(status);

    // The InkWell spans the whole 44px cell (touch target); the coloured
    // box inside is inset 3px for the paper-grid look.
    return SizedBox(
      width: cellW,
      height: rowH,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: tappable
              ? () => markHabit(
                    context,
                    ref,
                    habit,
                    day,
                    currentValue:
                        ref.read(valuesByHabitProvider)[habit.id]?[dateStr] ?? 0,
                  )
              : null,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(8),
              ),
              child: icon == null
                  ? null
                  : Icon(icon, size: 18, color: glyphColor),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bullet-journal style mood line under the grid, sharing the day axis:
/// x = day column centre, y = mood 1..5. Watches moods itself, so habit
/// taps never repaint it (and mood taps never repaint the grid).
class _MoodLine extends ConsumerWidget {
  final DateTime month;
  final int days;
  final double cellW;
  final double height;
  final int? todayIndex;
  const _MoodLine({
    required this.month,
    required this.days,
    required this.cellW,
    required this.height,
    required this.todayIndex,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final moodByDate = ref.watch(moodByDateProvider);
    final moods = List<int?>.generate(days, (i) {
      final date = formatYmd(DateTime(month.year, month.month, i + 1));
      return moodByDate[date]?.mood;
    });
    final hasAny = moods.any((m) => m != null);

    return SizedBox(
      width: days * cellW,
      height: height,
      child: hasAny
          ? CustomPaint(
              painter: _MoodLinePainter(
                moods: moods,
                cellW: cellW,
                lineColor: colors.gold,
                gridColor: colors.border,
                labelColor: colors.textDim,
                todayIndex: todayIndex,
              ),
            )
          : Center(
              child: Text('Bu ay mood kaydı yok',
                  style: TextStyle(fontSize: 12, color: colors.textDim)),
            ),
    );
  }
}

class _MoodLinePainter extends CustomPainter {
  final List<int?> moods;
  final double cellW;
  final Color lineColor;
  final Color gridColor;
  final Color labelColor;
  final int? todayIndex;

  _MoodLinePainter({
    required this.moods,
    required this.cellW,
    required this.lineColor,
    required this.gridColor,
    required this.labelColor,
    required this.todayIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const top = 8.0;
    const bottom = 8.0;
    final plotH = size.height - top - bottom;

    double yFor(int mood) => top + plotH * (1 - (mood - 1) / 4);
    double xFor(int i) => i * cellW + cellW / 2;

    // Light horizontal guides for each mood level.
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (var m = 1; m <= 5; m++) {
      final y = yFor(m);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Today marker.
    if (todayIndex != null && todayIndex! < moods.length) {
      final x = xFor(todayIndex!);
      canvas.drawLine(
        Offset(x, top - 4),
        Offset(x, top + plotH + 4),
        Paint()
          ..color = lineColor.withValues(alpha: 0.35)
          ..strokeWidth = 1.5,
      );
    }

    // Connect consecutive recorded days; break the line over gaps.
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    bool penDown = false;
    for (var i = 0; i < moods.length; i++) {
      final mood = moods[i];
      if (mood == null) {
        penDown = false;
        continue;
      }
      final p = Offset(xFor(i), yFor(mood));
      if (penDown) {
        path.lineTo(p.dx, p.dy);
      } else {
        path.moveTo(p.dx, p.dy);
        penDown = true;
      }
    }
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = lineColor;
    for (var i = 0; i < moods.length; i++) {
      final mood = moods[i];
      if (mood == null) continue;
      canvas.drawCircle(Offset(xFor(i), yFor(mood)), 3.2, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MoodLinePainter old) =>
      old.moods != moods ||
      old.lineColor != lineColor ||
      old.gridColor != gridColor ||
      old.todayIndex != todayIndex;
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.grid_view_rounded, size: 64, color: colors.textDim),
          const SizedBox(height: 16),
          const Text('Henüz alışkanlık yok',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('İlk alışkanlığını ekleyerek ızgaranı doldurmaya başla.',
              style: TextStyle(color: colors.textDim)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Alışkanlık ekle'),
          ),
        ],
      ),
    );
  }
}
