import 'package:flutter/material.dart';

/// The palette from `UI_SPEC.md` §2.
///
/// Green means normal and live. Amber means ending or attention. Red means
/// overtime, error, or destructive.
///
/// `UI_SPEC.md` §2 also requires that **colour is never the only signal** —
/// every state carries a label as well, so the floor reads correctly for
/// colour-blind staff and in bright light. Widgets that use [live], [ending],
/// or [overtime] must pair them with text.
abstract final class ArenaColors {
  static const Color background = Color(0xFF07070A);
  static const Color surface = Color(0xFF101018);
  static const Color surfaceRaised = Color(0xFF171A20);
  static const Color textPrimary = Color(0xFFE8EAF0);

  /// Accent, live, success.
  static const Color accent = Color(0xFF7CFF4F);

  /// Warning, ending.
  static const Color warning = Color(0xFFFFB020);

  /// Danger, overtime, destructive.
  static const Color danger = Color(0xFFFF4444);

  /// Muted / unavailable: 45% opacity on primary text.
  static const Color textMuted = Color(0x73E8EAF0);

  /// Semantic aliases for station presentation state (`UI_SPEC.md` §3).
  ///
  /// These are derived states, never stored (D06). `idle` and `paused` are
  /// distinguished by more than hue in the widgets that use them.
  static const Color stateIdle = textMuted;
  static const Color stateLive = accent;
  static const Color stateEnding = warning;
  static const Color stateOvertime = danger;
  /// Idle / maintenance grey from `404 Lobby OS.dc.html` (`GREY`).
  static const Color grey = Color(0xFF6B7080);

  static const Color statePaused = Color(0xFF9AA3B8);
  static const Color stateMaintenance = grey;

  /// Stock / “on the way” accent (`BLUE` in the HTML prototype).
  static const Color info = Color(0xFF4A8CFF);

  static const Color divider = Color(0xFF23262F);
  static const Color onAccent = Color(0xFF07070A);

  /// App frame fill inside the tablet shell.
  static const Color frame = Color(0xFF0B0B0F);

  /// Sidebar fill.
  static const Color sidebar = Color(0xFF0E0F14);

  /// Station / panel surface.
  static const Color panel = Color(0xFF101117);

  /// Dialog / sheet surface.
  static const Color sheet = Color(0xFF12131A);

  /// Toast surface.
  static const Color toast = Color(0xFF171923);
}
