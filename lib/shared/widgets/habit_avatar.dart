import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../data/database/database.dart';

/// Round colour swatch with the habit's icon.
class HabitAvatar extends StatelessWidget {
  final Habit habit;
  final double size;
  const HabitAvatar({super.key, required this.habit, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final color = Color(habit.colorValue);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(iconFromCodePoint(habit.iconCodePoint), color: color, size: size * 0.55),
    );
  }
}
