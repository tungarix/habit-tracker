import 'package:flutter/material.dart';

/// App palette as a [ThemeExtension] so every widget can resolve the right
/// colours for the active brightness via `AppColors.of(context)`.
///
/// Single green accent + gold for "best" highlights; everything else stays in
/// calm neutral greys, per the design brief.
///
/// Lives in `shared/` (not `core/`) because it is pure presentation — `core/`
/// must stay free of Flutter imports so the logic layer travels to any UI.
class AppColors extends ThemeExtension<AppColors> {
  final Color bg; // page background
  final Color surface; // cards / bars
  final Color surfaceAlt; // header strips / selected chips
  final Color border;

  final Color done; // ✓ completed / accent
  final Color missed; // ✗ scheduled but failed
  final Color skipped; // – deliberately skipped
  final Color gold; // best streak / highlights
  final Color idle; // unscheduled / future / empty cell

  final Color text;
  final Color textDim;

  const AppColors({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.done,
    required this.missed,
    required this.skipped,
    required this.gold,
    required this.idle,
    required this.text,
    required this.textDim,
  });

  static const dark = AppColors(
    bg: Color(0xFF0E141B),
    surface: Color(0xFF161F2B),
    surfaceAlt: Color(0xFF1E2A3A),
    border: Color(0xFF263244),
    done: Color(0xFF22C55E),
    missed: Color(0xFFEF4444),
    skipped: Color(0xFF64748B),
    gold: Color(0xFFCBA135),
    idle: Color(0xFF222E3D),
    text: Color(0xFFE6ECF3),
    textDim: Color(0xFF8A97A8),
  );

  static const light = AppColors(
    bg: Color(0xFFF5F7FA),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEAEFF5),
    border: Color(0xFFD8E0EA),
    done: Color(0xFF16A34A),
    missed: Color(0xFFDC2626),
    skipped: Color(0xFF64748B),
    gold: Color(0xFFA8802A),
    idle: Color(0xFFE2E8F0),
    text: Color(0xFF17202B),
    textDim: Color(0xFF5C6B7E),
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? dark;

  @override
  AppColors copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceAlt,
    Color? border,
    Color? done,
    Color? missed,
    Color? skipped,
    Color? gold,
    Color? idle,
    Color? text,
    Color? textDim,
  }) {
    return AppColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      border: border ?? this.border,
      done: done ?? this.done,
      missed: missed ?? this.missed,
      skipped: skipped ?? this.skipped,
      gold: gold ?? this.gold,
      idle: idle ?? this.idle,
      text: text ?? this.text,
      textDim: textDim ?? this.textDim,
    );
  }

  @override
  AppColors lerp(covariant ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      border: Color.lerp(border, other.border, t)!,
      done: Color.lerp(done, other.done, t)!,
      missed: Color.lerp(missed, other.missed, t)!,
      skipped: Color.lerp(skipped, other.skipped, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      idle: Color.lerp(idle, other.idle, t)!,
      text: Color.lerp(text, other.text, t)!,
      textDim: Color.lerp(textDim, other.textDim, t)!,
    );
  }
}

/// Numbers (streaks, counters, percentages) use tabular figures so digits keep
/// a fixed width and stop jittering when a value changes.
const TextStyle kTabularNums = TextStyle(
  fontFeatures: [FontFeature.tabularFigures()],
);

/// Central theme builder. Dark is the default look; light mirrors the same
/// structure with airy neutrals.
class AppTheme {
  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);
  static ThemeData light() => _build(AppColors.light, Brightness.light);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: c.done,
      brightness: brightness,
    ).copyWith(
      surface: c.surface,
      onSurface: c.text,
      primary: c.done,
      error: c.missed,
      outline: c.textDim,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      dividerColor: c.border,
      extensions: [c],
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: c.border),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: c.text,
      ),
      dialogTheme: DialogThemeData(backgroundColor: c.surface),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surfaceAlt,
        contentTextStyle: TextStyle(color: c.text),
        behavior: SnackBarBehavior.floating,
      ),
      textTheme: const TextTheme().apply(
        bodyColor: c.text,
        displayColor: c.text,
      ),
    );
  }
}
