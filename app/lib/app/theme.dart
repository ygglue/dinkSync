import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Court-green "Rounded" box radius (inputs, buttons, cards). Pills/chips/avatar
/// are fully round instead. See the `dinksync-ui` skill.
const double kRadius = 24.0;

/// Court-green seed for the Material 3 palette. The brand green is taken from
/// the generated `colorScheme.primary`, which adapts per brightness (a deep
/// green in light mode, a pale green in dark mode) and pairs with
/// `colorScheme.onPrimary` on filled surfaces. Everything brand-green reads
/// from the colorScheme, so there is a single mode-correct green app-wide
/// rather than a fixed colour fighting the scheme.
const Color _kBrandSeed = Color(0xFF2E7D32);

/// Theme for dinkSync — the "Clean & Minimal, Rounded" design system: court
/// green accent on calm surfaces, Plus Jakarta Sans headlines + Inter body,
/// 24px rounded shapes. Color is used sparingly; layout leans on whitespace.
class AppTheme {
  static const _seed = _kBrandSeed; // court green

  /// Headline font (Plus Jakarta Sans) layered over the Inter body text theme.
  static TextTheme _textTheme(TextTheme base) {
    final body = GoogleFonts.interTextTheme(base);
    final headline = GoogleFonts.plusJakartaSans();
    TextStyle? jakarta(TextStyle? s) =>
        s?.copyWith(fontFamily: headline.fontFamily, letterSpacing: -0.2);
    return body.copyWith(
      displayLarge: jakarta(body.displayLarge),
      displayMedium: jakarta(body.displayMedium),
      displaySmall: jakarta(body.displaySmall),
      headlineLarge: jakarta(body.headlineLarge),
      headlineMedium: jakarta(body.headlineMedium),
      headlineSmall: jakarta(body.headlineSmall),
      titleLarge: jakarta(body.titleLarge),
    );
  }

  /// Shared component theming so light + dark stay in lockstep.
  static ThemeData _build(Brightness brightness) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: brightness,
      ),
    );
    final scheme = base.colorScheme;
    OutlineInputBorder border(Color c, [double w = 0]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadius),
          borderSide: w == 0 ? BorderSide.none : BorderSide(color: c, width: w),
        );

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: _textTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: border(scheme.outlineVariant),
        enabledBorder: border(scheme.outlineVariant),
        focusedBorder: border(scheme.primary, 2),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size.fromHeight(48),
          textStyle: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kRadius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kRadius),
          ),
        ),
      ),
    );
  }

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);
}
