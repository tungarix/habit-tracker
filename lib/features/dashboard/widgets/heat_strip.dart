import 'package:flutter/material.dart';

import '../../../core/date_utils.dart';
import '../../../core/stats.dart';
import '../../../shared/theme.dart';

/// The dashboard's signature element: a compact run of days, newest on the
/// right. Colour carries the data — the habit's own hue, light→dark by how
/// full the day was — so the strip reads at a glance without a legend.
class HeatStrip extends StatelessWidget {
  final List<HeatPoint> points;
  final DateTime endDay;
  final Color color;

  /// Square edge length; the strip wraps to fit whatever width it is given.
  final double cell;
  final double gap;

  const HeatStrip({
    super.key,
    required this.points,
    required this.endDay,
    required this.color,
    this.cell = 11,
    this.gap = 3,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final days = lastDays(endDay, points.length);

    return LayoutBuilder(builder: (context, c) {
      // Shrink the cells rather than clipping when space is tight.
      final perCell = cell + gap;
      final fits = ((c.maxWidth + gap) / perCell).floor();
      final scale = fits >= points.length
          ? 1.0
          : ((c.maxWidth + gap) / points.length - gap) / cell;
      final size = (cell * scale).clamp(3.0, cell);

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < points.length; i++) ...[
            _Cell(
              point: points[i],
              day: days[i],
              color: color,
              colors: colors,
              size: size,
            ),
            if (i < points.length - 1) SizedBox(width: gap * scale),
          ],
        ],
      );
    });
  }
}

class _Cell extends StatelessWidget {
  final HeatPoint point;
  final DateTime day;
  final Color color;
  final AppColors colors;
  final double size;

  const _Cell({
    required this.point,
    required this.day,
    required this.color,
    required this.colors,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final (fill, label) = switch (point.cell) {
      // 0.35..1.0 keeps even a barely-started day visible against the surface.
      HeatCell.done => (
          color.withValues(alpha: 0.35 + 0.65 * point.intensity),
          'yapıldı',
        ),
      HeatCell.missed when point.intensity > 0 => (
          color.withValues(alpha: 0.15 + 0.30 * point.intensity),
          'kısmi',
        ),
      HeatCell.missed => (colors.missed.withValues(alpha: 0.30), 'yapılmadı'),
      HeatCell.skipped => (colors.skipped.withValues(alpha: 0.30), 'atlandı'),
      HeatCell.inactive => (colors.idle.withValues(alpha: 0.6), '—'),
    };

    return Tooltip(
      message: '${formatYmd(day)} · $label',
      waitDuration: const Duration(milliseconds: 350),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(size * 0.25),
        ),
      ),
    );
  }
}
