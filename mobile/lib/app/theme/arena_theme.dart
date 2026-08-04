import 'package:arena_os/app/theme/arena_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The application theme (`UI_SPEC.md` §1–2).
///
/// Counter UI is used while a customer is standing there, so the theme favours
/// large touch targets and high contrast over density. There is no light
/// theme: the product is a dark gaming-oriented interface.
///
/// Fonts match `404 Lobby OS.dc.html`: Chakra Petch, JetBrains Mono, Barlow.
abstract final class ArenaTheme {
  /// Minimum interactive size. Above the 48dp Material floor because staff tap
  /// these while looking at a customer, not at the screen.
  static const double minTouchTarget = 56;

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: ArenaColors.accent,
      onPrimary: ArenaColors.onAccent,
      secondary: ArenaColors.accent,
      onSecondary: ArenaColors.onAccent,
      surface: ArenaColors.surface,
      onSurface: ArenaColors.textPrimary,
      surfaceContainerHighest: ArenaColors.surfaceRaised,
      error: ArenaColors.danger,
      onError: ArenaColors.textPrimary,
      outline: ArenaColors.divider,
    );

    final barlow = GoogleFonts.barlowTextTheme();
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: ArenaColors.background,
      canvasColor: ArenaColors.background,
      dividerColor: ArenaColors.divider,
      // `UI_SPEC.md` §1: no decorative animation.
      splashFactory: NoSplash.splashFactory,
      textTheme: barlow,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: ArenaColors.background,
        foregroundColor: ArenaColors.textPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF0B0B0F),
        indicatorColor: ArenaColors.accent.withValues(alpha: 0.15),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.jetBrainsMono(
            fontSize: 10,
            letterSpacing: 0.6,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? ArenaColors.accent : ArenaColors.textMuted,
          );
        }),
      ),
      cardTheme: CardThemeData(
        color: ArenaColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: ArenaColors.divider),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(minTouchTarget, minTouchTarget),
          textStyle: GoogleFonts.barlow(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(minTouchTarget, minTouchTarget),
          foregroundColor: ArenaColors.textPrimary,
          side: const BorderSide(color: ArenaColors.divider),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(minTouchTarget, minTouchTarget),
          foregroundColor: ArenaColors.accent,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ArenaColors.surfaceRaised,
        contentTextStyle: GoogleFonts.barlow(color: ArenaColors.textPrimary),
        behavior: SnackBarBehavior.floating,
      ),
      textTheme: barlow.apply(
        bodyColor: ArenaColors.textPrimary,
        displayColor: ArenaColors.textPrimary,
      ),
      visualDensity: VisualDensity.comfortable,
    );
  }

  /// Monospaced, tabular style for timers and money.
  static TextStyle get numeric => GoogleFonts.jetBrainsMono(
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    fontWeight: FontWeight.w600,
  );
}
