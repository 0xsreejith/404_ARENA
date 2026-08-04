import 'package:arena_os/app/theme/arena_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography from `404 Lobby OS.dc.html`: Chakra Petch, JetBrains Mono, Barlow.
abstract final class LobbyFonts {
  static TextStyle display({
    double size = 27,
    FontWeight weight = FontWeight.w700,
    Color color = ArenaColors.textPrimary,
    double? height,
    double letterSpacing = 0,
  }) => GoogleFonts.chakraPetch(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
    decoration: TextDecoration.none,
  );

  static TextStyle mono({
    double size = 12,
    FontWeight weight = FontWeight.w500,
    Color color = ArenaColors.textPrimary,
    double? height,
    double letterSpacing = 0,
  }) => GoogleFonts.jetBrainsMono(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
    decoration: TextDecoration.none,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  static TextStyle body({
    double size = 15,
    FontWeight weight = FontWeight.w400,
    Color color = ArenaColors.textPrimary,
    double? height,
  }) => GoogleFonts.barlow(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    decoration: TextDecoration.none,
  );
}
