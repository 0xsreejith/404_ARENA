import 'package:arena_os/app/theme/arena_colors.dart';
import 'package:arena_os/features/lobby_ui/lobby_fonts.dart';
import 'package:flutter/widgets.dart';

enum LobbyButtonTone { primary, ghost, danger }

/// Custom button matching `404 Lobby OS.dc.html` — no Material defaults.
class LobbyButton extends StatefulWidget {
  const LobbyButton({
    required this.label,
    required this.onTap,
    super.key,
    this.height = 52,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
    this.radius = 10,
    this.tone = LobbyButtonTone.primary,
    this.fontSize = 13.5,
    this.letterSpacingEm = 0.09,
    this.mono = false,
    this.expanded = false,
    this.enabled = true,
    this.background,
    this.foreground,
    this.borderColor,
  });

  final String label;
  final VoidCallback? onTap;
  final double height;
  final EdgeInsets padding;
  final double radius;
  final LobbyButtonTone tone;
  final double fontSize;
  final double letterSpacingEm;
  final bool mono;
  final bool expanded;
  final bool enabled;
  final Color? background;
  final Color? foreground;
  final Color? borderColor;

  @override
  State<LobbyButton> createState() => _LobbyButtonState();
}

class _LobbyButtonState extends State<LobbyButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && widget.onTap != null;
    late Color bg;
    late Color fg;
    Color? border = widget.borderColor;

    switch (widget.tone) {
      case LobbyButtonTone.primary:
        bg = widget.background ?? (enabled ? ArenaColors.accent : const Color(0xFF2A2D35));
        fg = widget.foreground ??
            (enabled ? ArenaColors.onAccent : ArenaColors.textPrimary.withValues(alpha: 0.35));
      case LobbyButtonTone.ghost:
        bg = widget.background ?? const Color(0x00000000);
        fg = widget.foreground ?? ArenaColors.textPrimary.withValues(alpha: 0.75);
        border ??= const Color(0x1FFFFFFF);
      case LobbyButtonTone.danger:
        bg = widget.background ?? ArenaColors.danger.withValues(alpha: 0.15);
        fg = widget.foreground ?? ArenaColors.danger;
        border ??= ArenaColors.danger.withValues(alpha: 0.35);
    }

    if (_hover && enabled) {
      bg = Color.lerp(bg, const Color(0xFFFFFFFF), 0.08) ?? bg;
      if (widget.tone == LobbyButtonTone.ghost) fg = ArenaColors.accent;
    }
    if (_down && enabled) {
      bg = Color.lerp(bg, const Color(0xFF000000), 0.08) ?? bg;
    }

    final style = widget.mono
        ? LobbyFonts.mono(
            size: widget.fontSize,
            weight: FontWeight.w700,
            letterSpacing: widget.letterSpacingEm * widget.fontSize,
            color: fg,
          )
        : LobbyFonts.display(
            size: widget.fontSize,
            weight: FontWeight.w700,
            letterSpacing: widget.letterSpacingEm * widget.fontSize,
            color: fg,
          );

    Widget child = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      height: widget.height,
      padding: widget.padding,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(widget.radius),
        border: border != null ? Border.all(color: border) : null,
      ),
      child: Text(widget.label, style: style, textAlign: TextAlign.center),
    );

    if (widget.expanded) child = SizedBox(width: double.infinity, child: child);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled
            ? (_) {
                setState(() => _down = false);
                widget.onTap?.call();
              }
            : null,
        onTapCancel: () => setState(() => _down = false),
        child: child,
      ),
    );
  }
}
