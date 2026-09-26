import 'package:flutter/material.dart';

import '../../core/enums.dart';
import '../theme.dart';

/// Colour for a day mark; [empty] is returned for untracked cells.
Color statusColor(AppColors colors, EntryStatus? status, {Color? empty}) {
  switch (status) {
    case EntryStatus.done:
      return colors.done;
    case EntryStatus.missed:
      return colors.missed;
    case EntryStatus.skipped:
      return colors.skipped;
    case null:
      return empty ?? colors.idle;
  }
}

/// Glyph for a day mark (✓ / ✗ / –); null for untracked.
IconData? statusIcon(EntryStatus? status) {
  switch (status) {
    case EntryStatus.done:
      return Icons.check;
    case EntryStatus.missed:
      return Icons.close;
    case EntryStatus.skipped:
      return Icons.remove;
    case null:
      return null;
  }
}

/// Round tri-state mark used on the Today screen. Pops (scale) when the
/// status changes for a light bit of tactile feedback.
class StatusMark extends StatelessWidget {
  final EntryStatus? status;
  final double size;
  const StatusMark({super.key, required this.status, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final filled = status != null;
    final color = statusColor(colors, status);
    final icon = statusIcon(status);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color.withValues(alpha: 0.18) : Colors.transparent,
        border: Border.all(
          color: filled ? color : colors.border,
          width: 2,
        ),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOutBack,
        transitionBuilder: (child, animation) =>
            ScaleTransition(scale: animation, child: child),
        child: icon == null
            ? const SizedBox.shrink(key: ValueKey('empty'))
            : Icon(icon, key: ValueKey(status), color: color, size: size * 0.5),
      ),
    );
  }
}
