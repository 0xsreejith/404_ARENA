import 'package:flutter/widgets.dart';

/// CSS keyframe ports from `404 Lobby OS.dc.html`.
abstract final class LobbyAnims {
  static const otPulse = Duration(milliseconds: 1500);
  static const breatheLive = Duration(milliseconds: 2600);
  static const breatheSoon = Duration(milliseconds: 1100);
  static const blink = Duration(milliseconds: 800);
  static const syncBlink = Duration(milliseconds: 1600);
  static const sweep = Duration(milliseconds: 2600);
  static const sheetUp = Duration(milliseconds: 180);
  static const toastIn = Duration(milliseconds: 200);
  static const fadeIn = Duration(milliseconds: 180);
  static const alertGlow = Duration(milliseconds: 1500);
  static const bobArrow = Duration(milliseconds: 1400);
  static const bubbleIn = Duration(milliseconds: 340);
  static const hover = Duration(milliseconds: 140);
}

/// Step blink: opaque ↔ 0.2 (CSS `steps(1,end)`).
class BlinkOpacity extends StatefulWidget {
  const BlinkOpacity({
    required this.child,
    super.key,
    this.period = LobbyAnims.blink,
    this.enabled = true,
  });

  final Widget child;
  final Duration period;
  final bool enabled;

  @override
  State<BlinkOpacity> createState() => _BlinkOpacityState();
}

class _BlinkOpacityState extends State<BlinkOpacity> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.period)..repeat();

  @override
  void didUpdateWidget(covariant BlinkOpacity oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !_c.isAnimating) _c.repeat();
    if (!widget.enabled && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final on = _c.value < 0.5;
        return Opacity(opacity: on ? 1 : 0.2, child: child);
      },
      child: widget.child,
    );
  }
}

/// Breathe: opacity .45↔1 and scale .86↔1.
class Breathe extends StatefulWidget {
  const Breathe({
    required this.child,
    super.key,
    this.period = LobbyAnims.breatheLive,
    this.enabled = true,
  });

  final Widget child;
  final Duration period;
  final bool enabled;

  @override
  State<Breathe> createState() => _BreatheState();
}

class _BreatheState extends State<Breathe> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.period)..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        final opacity = 0.45 + 0.55 * t;
        final scale = 0.86 + 0.14 * t;
        return Opacity(
          opacity: opacity,
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: widget.child,
    );
  }
}

/// Horizontal sweep highlight over a progress fill.
class SweepHighlight extends StatefulWidget {
  const SweepHighlight({super.key, this.enabled = true, this.width = 34});

  final bool enabled;
  final double width;

  @override
  State<SweepHighlight> createState() => _SweepHighlightState();
}

class _SweepHighlightState extends State<SweepHighlight> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: LobbyAnims.sweep)..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final span = constraints.maxWidth + widget.width * 4;
        return AnimatedBuilder(
          animation: _c,
          builder: (context, child) {
            // 0→55%: -120% → 420% of bar; then hold
            final t = _c.value;
            final progress = t < 0.55 ? (t / 0.55) : 1.0;
            final dx = -widget.width * 1.2 + progress * span;
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Positioned(
                  left: dx,
                  top: 0,
                  bottom: 0,
                  width: widget.width,
                  child: child!,
                ),
              ],
            );
          },
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  Color(0x00FFFFFF),
                  Color(0x8CFFFFFF),
                  Color(0x00FFFFFF),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Overtime card pulse: inset ring intensity + outer glow.
class OtPulseBorder extends StatefulWidget {
  const OtPulseBorder({
    required this.child,
    required this.color,
    super.key,
    this.enabled = true,
    this.radius = 14,
  });

  final Widget child;
  final Color color;
  final bool enabled;
  final double radius;

  @override
  State<OtPulseBorder> createState() => _OtPulseBorderState();
}

class _OtPulseBorderState extends State<OtPulseBorder> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: LobbyAnims.otPulse)..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(color: widget.color.withValues(alpha: 0.6)),
        ),
        child: widget.child,
      );
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        final inset = 0.5 + 0.5 * t;
        final glow = 0.0 + 0.45 * t;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(color: widget.color.withValues(alpha: 0.5 + 0.5 * inset)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: widget.color.withValues(alpha: glow),
                blurRadius: 24,
                spreadRadius: -4,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// S5 panel inset ring + outer glow (`alertGlow` keyframe).
class AlertGlowPanel extends StatefulWidget {
  const AlertGlowPanel({required this.child, super.key, this.radius = 20});

  final Widget child;
  final double radius;

  @override
  State<AlertGlowPanel> createState() => _AlertGlowPanelState();
}

class _AlertGlowPanelState extends State<AlertGlowPanel> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: LobbyAnims.alertGlow)..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        final inset = 0.5 + 0.5 * t;
        final glow = 0.0 + 0.4 * t;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0xFF171208), Color(0xFF0E0B06)],
            ),
            border: Border.all(color: const Color(0xFFFFB020).withValues(alpha: 0.5 + 0.5 * inset), width: 2),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFFFFB020).withValues(alpha: glow),
                blurRadius: 90,
                spreadRadius: -10,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Minimise button chevron bob (`bobArrow` keyframe).
class BobArrow extends StatefulWidget {
  const BobArrow({super.key, this.color = const Color(0xFFFFB020), this.size = 9});

  final Color color;
  final double size;

  @override
  State<BobArrow> createState() => _BobArrowState();
}

class _BobArrowState extends State<BobArrow> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: LobbyAnims.bobArrow)..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final dy = -1.0 + 3.0 * Curves.easeInOut.transform(_c.value);
        return Transform.translate(offset: Offset(0, dy), child: child);
      },
      child: Transform.rotate(
        angle: 0.785398,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: widget.color, width: 2),
              bottom: BorderSide(color: widget.color, width: 2),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bubble entrance scale (`bubbleIn` keyframe).
class BubbleEntrance extends StatelessWidget {
  const BubbleEntrance({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: LobbyAnims.bubbleIn,
      curve: const Cubic(0.2, 1.25, 0.35, 1),
      builder: (context, t, child) {
        final scale = t < 0.62 ? 0.4 + 0.67 * (t / 0.62) : 1.07 - 0.07 * ((t - 0.62) / 0.38);
        final y = t < 0.62 ? 40 * (1 - t / 0.62) - 5 * (t / 0.62) : -5 * (1 - (t - 0.62) / 0.38);
        return Opacity(
          opacity: t.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, y),
            child: Transform.scale(scale: scale.clamp(0, 1.07), child: child),
          ),
        );
      },
      child: child,
    );
  }
}
