import 'package:flutter/material.dart';

import '../../../core/date_utils.dart';
import '../../../core/enums.dart';
import '../../../data/database/database.dart';
import '../../../shared/theme.dart';

/// Compact 30-day mood line for the dashboard footer.
///
/// Deliberately small: with no mood history yet it must not dominate the
/// screen, and it grows in usefulness rather than size as days accumulate.
class MoodStrip extends StatelessWidget {
  final Map<String, MoodEntry> moodByDate;
  final DateTime endDay;
  final int days;
  final double height;

  const MoodStrip({
    super.key,
    required this.moodByDate,
    required this.endDay,
    this.days = 30,
    this.height = 60,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final series = [
      for (final day in lastDays(endDay, days)) moodByDate[formatYmd(day)]?.mood,
    ];
    final recorded = series.where((m) => m != null).length;

    if (recorded == 0) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Mood kaydı yok — bugünü işaretle, çizgi buradan başlasın.',
            style: TextStyle(fontSize: 12, color: colors.textDim),
          ),
        ),
      );
    }

    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _MoodStripPainter(
          series: series,
          line: colors.gold,
          grid: colors.border,
        ),
      ),
    );
  }
}

class _MoodStripPainter extends CustomPainter {
  final List<int?> series;
  final Color line;
  final Color grid;

  _MoodStripPainter({
    required this.series,
    required this.line,
    required this.grid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 6.0;
    final plotH = size.height - pad * 2;
    final n = series.length;
    if (n == 0) return;

    double xAt(int i) => n == 1 ? size.width / 2 : size.width * (i / (n - 1));
    double yAt(int mood) => pad + plotH * (1 - (mood - 1) / 4);

    // Faint rails at the extremes only — enough to read height, no clutter.
    final gridPaint = Paint()
      ..color = grid.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (final mood in [1, 5]) {
      final y = yAt(mood);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final stroke = Paint()
      ..color = line
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    // Gaps break the line: absent days are not interpolated into a story.
    final path = Path();
    var penDown = false;
    for (var i = 0; i < n; i++) {
      final mood = series[i];
      if (mood == null) {
        penDown = false;
        continue;
      }
      final p = Offset(xAt(i), yAt(mood));
      penDown ? path.lineTo(p.dx, p.dy) : path.moveTo(p.dx, p.dy);
      penDown = true;
    }
    canvas.drawPath(path, stroke);

    final dot = Paint()..color = line;
    for (var i = 0; i < n; i++) {
      final mood = series[i];
      if (mood == null) continue;
      canvas.drawCircle(Offset(xAt(i), yAt(mood)), 2.2, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _MoodStripPainter old) =>
      old.series != series || old.line != line || old.grid != grid;
}

/// Five one-tap mood buttons. Tapping the selected one clears it.
class MoodPicker extends StatelessWidget {
  final Mood? selected;
  final ValueChanged<Mood> onTap;
  final double height;

  const MoodPicker({
    super.key,
    required this.selected,
    required this.onTap,
    this.height = 44,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      children: [
        for (final mood in Mood.values) ...[
          Expanded(
            child: Tooltip(
              message: mood.label,
              child: Semantics(
                button: true,
                selected: mood == selected,
                label: mood.label,
                child: Material(
                  color: mood == selected
                      ? colors.surfaceAlt
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => onTap(mood),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      height: height,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: mood == selected
                              ? colors.done
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: AnimatedScale(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOutBack,
                          scale: mood == selected ? 1.2 : 1,
                          child: Text(mood.emoji,
                              style: const TextStyle(fontSize: 19)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (mood != Mood.values.last) const SizedBox(width: 6),
        ],
      ],
    );
  }
}
