import 'package:flutter/material.dart';

/// Small flame + N pill showing the current streak. Hidden when streak is 0.
class StreakBadge extends StatelessWidget {
  final int streak;
  const StreakBadge({super.key, required this.streak});

  @override
  Widget build(BuildContext context) {
    if (streak <= 0) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department_outlined,
              size: 14, color: scheme.onTertiaryContainer),
          const SizedBox(width: 4),
          Text(
            '$streak',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: scheme.onTertiaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
