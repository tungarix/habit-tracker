import 'package:flutter/material.dart';

/// Central theme. A single seed colour drives the whole Material 3 scheme.
class AppTheme {
  static const Color seed = Color(0xFF4CAF50);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      ),
      navigationRailTheme: NavigationRailThemeData(
        indicatorColor: scheme.secondaryContainer,
        labelType: NavigationRailLabelType.all,
      ),
    );
  }
}
