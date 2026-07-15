import 'package:flutter/material.dart';

/// Dark palette adapted from the Lovable web design.
class AppColors {
  AppColors._();

  /// Page background (near-black).
  static const bg = Color(0xFF0A0A0B);

  /// Subtle lift used by the top of the radial background glow.
  static const bgGlow = Color(0xFF161618);

  /// Default card surface.
  static const card = Color(0xFF141416);

  /// Slightly raised surface (inner icon chips, nested rows).
  static const surface = Color(0xFF1C1C1F);

  /// Hairline borders around cards.
  static const border = Color(0xFF26262A);

  /// Primary text — warm champagne/beige instead of flat white, for a softer
  /// golden contrast against the near-black background.
  static const textPrimary = Color(0xFFE8D5B0);

  /// Secondary / supporting text — warm taupe grey.
  static const textSecondary = Color(0xFF9C9384);

  /// Muted eyebrow labels and timestamps — warm muted brown-grey.
  static const textMuted = Color(0xFF6E6458);

  /// Cream highlight used for the "Renders left" card.
  static const cream = Color(0xFFF6F4EC);

  /// Text on the cream highlight.
  static const onCream = Color(0xFF111112);
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: AppColors.cream,
      onPrimary: AppColors.onCream,
      surface: AppColors.card,
      onSurface: AppColors.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: scheme,
      fontFamily: 'Roboto',
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: const TextStyle(color: AppColors.textMuted),
      ),
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.0,
          height: 1.05,
        ),
        headlineSmall: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: TextStyle(color: AppColors.textSecondary, height: 1.4),
        labelLarge: TextStyle(
          color: AppColors.textMuted,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}
