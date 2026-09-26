import 'package:flutter/material.dart';

/// Presentation-only habit styling: the colour and icon palettes offered when
/// creating or editing a habit.
///
/// These live in `shared/` rather than `core/` because they are Flutter types
/// ([Color], [IconData]); `core/` must stay importable without a UI toolkit.
/// The database only ever stores the ARGB int and the icon codepoint.

/// Palette offered when creating / editing a habit.
const List<Color> kHabitColors = [
  Color(0xFF4CAF50), // green
  Color(0xFF2196F3), // blue
  Color(0xFF9C27B0), // purple
  Color(0xFFFF9800), // orange
  Color(0xFFF44336), // red
  Color(0xFF009688), // teal
  Color(0xFF3F51B5), // indigo
  Color(0xFFE91E63), // pink
  Color(0xFF795548), // brown
  Color(0xFF607D8B), // blue grey
];

/// Icons offered when creating / editing a habit.
///
/// We only ever reconstruct an [IconData] by looking it up in this constant
/// list (see [iconFromCodePoint]). That keeps every [IconData] const, which
/// lets Flutter tree-shake icon fonts normally instead of forcing
/// `--no-tree-shake-icons`.
const List<IconData> kHabitIcons = [
  Icons.fitness_center,
  Icons.self_improvement,
  Icons.menu_book,
  Icons.water_drop,
  Icons.directions_run,
  Icons.bedtime,
  Icons.code,
  Icons.brush,
  Icons.music_note,
  Icons.local_florist,
  Icons.restaurant,
  Icons.cleaning_services,
  Icons.savings,
  Icons.smoke_free,
  Icons.favorite,
  Icons.school,
  Icons.directions_bike,
  Icons.pets,
  Icons.spa,
  Icons.work,
];

/// Maps a stored codepoint back to a known const [IconData], falling back to a
/// default so imported data with unknown icons never crashes.
IconData iconFromCodePoint(int codePoint) {
  for (final icon in kHabitIcons) {
    if (icon.codePoint == codePoint) return icon;
  }
  return Icons.check_circle;
}
