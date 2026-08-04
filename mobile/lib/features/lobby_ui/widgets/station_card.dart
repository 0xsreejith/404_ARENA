import 'package:arena_os/app/theme/arena_colors.dart';
import 'package:arena_os/features/lobby_ui/lobby_fonts.dart';
import 'package:arena_os/features/lobby_ui/widgets/lobby_anims.dart';
import 'package:flutter/widgets.dart';

enum LiveStationCardStatus {
  idle,
  live,
  ending,
  overtime,
  maintenance,
  paused,
  inactive,
}

class LiveStationCardData {
  const LiveStationCardData({
    required this.id,
    required this.typeLine,
    required this.seats,
    required this.status,
    this.players = const <String>[],
    this.gameName,
    this.timerText = 'READY',
    this.timerLabel = 'FREE NOW',
    this.progressFraction = 0,
    this.rateText = '—',
    this.amountLabel = '',
    this.amountText = '—',
    this.idleLine = 'Tap to start',
    this.maintenanceLine = 'Controller drift — logged',
  });

  final String id;
  final String typeLine;
  final int seats;
  final LiveStationCardStatus status;
  final List<String> players;
  final String? gameName;
  final String timerText;
  final String timerLabel;
  final double progressFraction;
  final String rateText;
  final String amountLabel;
  final String amountText;
  final String idleLine;
  final String maintenanceLine;

  bool get isBusy =>
      status == LiveStationCardStatus.live ||
      status == LiveStationCardStatus.ending ||
      status == LiveStationCardStatus.overtime ||
      status == LiveStationCardStatus.paused;
}

class StationCard extends StatefulWidget {
  const StationCard({required this.station, required this.onTap, super.key});

  final LiveStationCardData station;
  final VoidCallback onTap;

  @override
  State<StationCard> createState() => _StationCardState();
}

class _StationCardState extends State<StationCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final station = widget.station;
    final style = _StationVisual.of(station);

    Widget body = LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 300;
        final hasTightHeight =
            constraints.hasBoundedHeight && constraints.maxHeight.isFinite;
        final titleSize = narrow ? 18.0 : 27.0;
        final timerSize = narrow ? 26.0 : 36.0;
        final hPad = narrow ? 12.0 : 16.0;
        final vPad = narrow ? 10.0 : 14.0;
        // Fill tall grid cells; shrink-wrap in list / short cells (no overflow).
        final expand = hasTightHeight && constraints.maxHeight >= 230;

        return _CardShell(
          style: style,
          child: CustomPaint(
            painter: style.maintenance ? const _HatchPainter() : null,
            child: Stack(
              children: <Widget>[
                if (style.wash != null)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: RadialGradient(
                          center: const Alignment(0, 1.4),
                          radius: 1.15,
                          colors: <Color>[style.wash!, const Color(0x00000000)],
                          stops: const <double>[0.0, 0.65],
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
                  child: Column(
                    mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  station.id,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      LobbyFonts.display(
                                        size: titleSize,
                                        color: style.nameFg,
                                        height: 1,
                                      ).copyWith(
                                        decoration: style.strike
                                            ? TextDecoration.lineThrough
                                            : TextDecoration.none,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  station.typeLine,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: false,
                                  style: LobbyFonts.mono(
                                    size: narrow ? 8.5 : 9.5,
                                    letterSpacing: (narrow ? 8.5 : 9.5) * 0.06,
                                    color: ArenaColors.textPrimary.withValues(
                                      alpha: 0.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 9),
                          _StatusPill(
                            label: style.label,
                            color: style.pillFg,
                            bg: style.pillBg,
                            dotMode: style.dotMode,
                          ),
                        ],
                      ),
                      SizedBox(height: narrow ? 6 : 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: <Widget>[
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                style.timerText,
                                maxLines: 1,
                                softWrap: false,
                                style: LobbyFonts.mono(
                                  size: timerSize,
                                  weight: FontWeight.w700,
                                  color: style.timerFg,
                                  height: 1,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              style.timerLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: LobbyFonts.mono(
                                size: 9,
                                letterSpacing: 9 * 0.12,
                                color: style.timerLabelFg,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: narrow ? 6 : 8),
                      _ProgressBar(
                        fraction: style.barFraction,
                        color: style.barFg,
                        sweep: style.sweep,
                      ),
                      SizedBox(height: narrow ? 6 : 10),
                      _PlayerRow(station: station, style: style),
                      if (expand) const Spacer() else const SizedBox(height: 10),
                      if (expand) const SizedBox(height: 8),
                      _Footer(style: style),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (style.overtimePulse) {
      body = OtPulseBorder(
        color: ArenaColors.danger,
        enabled: true,
        radius: 14,
        child: body,
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: LobbyAnims.hover,
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
          transformAlignment: Alignment.center,
          child: ColorFiltered(
            colorFilter: _hovered
                ? _brighten
                : const ColorFilter.matrix(<double>[
                    1,
                    0,
                    0,
                    0,
                    0,
                    0,
                    1,
                    0,
                    0,
                    0,
                    0,
                    0,
                    1,
                    0,
                    0,
                    0,
                    0,
                    0,
                    1,
                    0,
                  ]),
            child: body,
          ),
        ),
      ),
    );
  }

  static const ColorFilter _brighten = ColorFilter.matrix(<double>[
    1.1,
    0,
    0,
    0,
    0,
    0,
    1.1,
    0,
    0,
    0,
    0,
    0,
    1.1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]);
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.style, required this.child});

  final _StationVisual style;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.maintenance
            ? const Color(0xFF0F1015)
            : const Color(0xFF101117),
        borderRadius: BorderRadius.circular(14),
        border: style.overtimePulse
            ? null
            : Border.all(color: style.ring, width: 1),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(14), child: child),
    );
  }
}

enum _DotMode { none, breatheLive, breatheSoon, blink }

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    required this.bg,
    required this.dotMode,
  });

  final String label;
  final Color color;
  final Color bg;
  final _DotMode dotMode;

  @override
  Widget build(BuildContext context) {
    Widget dot = Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    switch (dotMode) {
      case _DotMode.breatheLive:
        dot = Breathe(period: LobbyAnims.breatheLive, child: dot);
      case _DotMode.breatheSoon:
        dot = Breathe(period: LobbyAnims.breatheSoon, child: dot);
      case _DotMode.blink:
        dot = BlinkOpacity(period: LobbyAnims.blink, child: dot);
      case _DotMode.none:
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          dot,
          const SizedBox(width: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LobbyFonts.mono(
              size: 9,
              weight: FontWeight.w700,
              letterSpacing: 9 * 0.1,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.fraction,
    required this.color,
    required this.sweep,
  });

  final double fraction;
  final Color color;
  final bool sweep;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: ColoredBox(
          color: const Color(0x12FFFFFF),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fraction.clamp(0.0, 1.0),
              heightFactor: 1,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  ColoredBox(color: color),
                  SweepHighlight(enabled: sweep && fraction > 0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.station, required this.style});

  final LiveStationCardData station;
  final _StationVisual style;

  @override
  Widget build(BuildContext context) {
    final avatars = station.players.take(3).map(_initials).toList();
    return SizedBox(
      height: 24,
      child: Row(
        children: <Widget>[
          for (final ini in avatars) ...<Widget>[
            _Avatar(initials: ini),
            const SizedBox(width: 7),
          ],
          Flexible(
            child: Text(
              style.playerLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LobbyFonts.body(
                size: 13,
                weight: FontWeight.w600,
                color: style.playerFg,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            style.seatsText,
            style: LobbyFonts.mono(
              size: 10,
              color: ArenaColors.textPrimary.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .toList();
    if (parts.isEmpty) return '?';
    return parts.map((p) => p[0].toUpperCase()).join();
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0x247CFF4F),
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        style: LobbyFonts.mono(
          size: 9.5,
          weight: FontWeight.w700,
          color: ArenaColors.accent,
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.style});

  final _StationVisual style;

  @override
  Widget build(BuildContext context) {
    final showAmount =
        style.amountLabel.trim().isNotEmpty ||
        (style.amountText.trim().isNotEmpty && style.amountText.trim() != '—');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                style.gameLabel,
                style: LobbyFonts.mono(
                  size: 9,
                  letterSpacing: 9 * 0.1,
                  color: ArenaColors.textPrimary.withValues(alpha: 0.32),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                style.gameName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LobbyFonts.display(
                  size: 15,
                  weight: FontWeight.w600,
                  color: style.gameFg,
                ),
              ),
            ],
          ),
        ),
        if (showAmount) ...[
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(
              style.amountLabel,
              style: LobbyFonts.mono(
                size: 9,
                letterSpacing: 9 * 0.1,
                color: ArenaColors.textPrimary.withValues(alpha: 0.32),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              style.amountText,
              style: LobbyFonts.mono(
                size: 20,
                weight: FontWeight.w700,
                color: style.amountFg,
              ),
            ),
          ],
        ),
        ],
      ],
    );
  }
}

class _StationVisual {
  const _StationVisual({
    required this.label,
    required this.pillFg,
    required this.pillBg,
    required this.ring,
    required this.nameFg,
    required this.timerText,
    required this.timerLabel,
    required this.timerFg,
    required this.timerLabelFg,
    required this.barFraction,
    required this.barFg,
    required this.sweep,
    required this.playerLine,
    required this.playerFg,
    required this.seatsText,
    required this.gameLabel,
    required this.gameName,
    required this.gameFg,
    required this.amountLabel,
    required this.amountText,
    required this.amountFg,
    required this.strike,
    required this.maintenance,
    required this.overtimePulse,
    required this.dotMode,
    this.wash,
  });

  final String label;
  final Color pillFg;
  final Color pillBg;
  final Color ring;
  final Color? wash;
  final Color nameFg;
  final String timerText;
  final String timerLabel;
  final Color timerFg;
  final Color timerLabelFg;
  final double barFraction;
  final Color barFg;
  final bool sweep;
  final String playerLine;
  final Color playerFg;
  final String seatsText;
  final String gameLabel;
  final String gameName;
  final Color gameFg;
  final String amountLabel;
  final String amountText;
  final Color amountFg;
  final bool strike;
  final bool maintenance;
  final bool overtimePulse;
  final _DotMode dotMode;

  static const Color _grey = ArenaColors.grey;
  static const Color _idleRing = Color(0x12FFFFFF);
  static const Color _timerDim = Color(0x47E8EAF0);
  static const Color _labelDim = Color(0x52E8EAF0);

  static _StationVisual of(LiveStationCardData s) {
    final busy = s.isBusy;
    final seatsText = busy ? '${s.players.length}/${s.seats}' : '0/${s.seats}';
    final playerLine = busy
        ? (s.players.length > 3
              ? '${s.players.length} players'
              : s.players.map((p) => p.split(RegExp(r'\s+')).first).join(', '))
        : (s.status == LiveStationCardStatus.maintenance ||
                  s.status == LiveStationCardStatus.inactive
              ? s.maintenanceLine
              : s.idleLine);

    switch (s.status) {
      case LiveStationCardStatus.idle:
        return _StationVisual(
          label: 'IDLE',
          pillFg: _grey,
          pillBg: const Color(0x0FFFFFFF),
          ring: _idleRing,
          nameFg: ArenaColors.textPrimary.withValues(alpha: 0.55),
          timerText: 'READY',
          timerLabel: 'FREE NOW',
          timerFg: _timerDim,
          timerLabelFg: _labelDim,
          barFraction: 0,
          barFg: const Color(0x00000000),
          sweep: false,
          playerLine: playerLine,
          playerFg: ArenaColors.textPrimary.withValues(alpha: 0.45),
          seatsText: seatsText,
          gameLabel: 'RATE',
          gameName: _rateName(s),
          gameFg: ArenaColors.textPrimary.withValues(alpha: 0.5),
          amountLabel: '',
          amountText: '—',
          amountFg: ArenaColors.textPrimary.withValues(alpha: 0.25),
          strike: false,
          maintenance: false,
          overtimePulse: false,
          dotMode: _DotMode.none,
        );
      case LiveStationCardStatus.live:
        return _busy(
          s,
          label: 'LIVE',
          accent: ArenaColors.accent,
          ring: ArenaColors.accent.withValues(alpha: 0.3),
          wash: ArenaColors.accent.withValues(alpha: 0.09),
          pillBg: ArenaColors.accent.withValues(alpha: 0.15),
          dotMode: _DotMode.breatheLive,
          playerLine: playerLine,
          seatsText: seatsText,
        );
      case LiveStationCardStatus.ending:
        return _busy(
          s,
          label: 'LAST 5 MIN',
          accent: ArenaColors.warning,
          ring: ArenaColors.warning.withValues(alpha: 0.45),
          wash: ArenaColors.warning.withValues(alpha: 0.11),
          pillBg: ArenaColors.warning.withValues(alpha: 0.15),
          dotMode: _DotMode.breatheSoon,
          playerLine: playerLine,
          seatsText: seatsText,
        );
      case LiveStationCardStatus.overtime:
        return _busy(
          s,
          label: 'OVER TIME',
          accent: ArenaColors.danger,
          ring: ArenaColors.danger.withValues(alpha: 0.6),
          wash: ArenaColors.danger.withValues(alpha: 0.13),
          pillBg: ArenaColors.danger.withValues(alpha: 0.15),
          dotMode: _DotMode.blink,
          playerLine: playerLine,
          seatsText: seatsText,
          overtimePulse: true,
        );
      case LiveStationCardStatus.paused:
        return _StationVisual(
          label: 'PAUSED',
          pillFg: ArenaColors.statePaused,
          pillBg: ArenaColors.statePaused.withValues(alpha: 0.15),
          ring: ArenaColors.statePaused.withValues(alpha: 0.35),
          nameFg: ArenaColors.textPrimary.withValues(alpha: 0.7),
          timerText: 'PAUSED',
          timerLabel: 'ON HOLD',
          timerFg: ArenaColors.statePaused,
          timerLabelFg: ArenaColors.statePaused,
          barFraction: 0,
          barFg: const Color(0x00000000),
          sweep: false,
          playerLine: playerLine,
          playerFg: ArenaColors.textPrimary,
          seatsText: seatsText,
          gameLabel: 'PLAYING',
          gameName: s.gameName ?? '—',
          gameFg: ArenaColors.textPrimary,
          amountLabel: s.amountLabel,
          amountText: s.amountText,
          amountFg: ArenaColors.textPrimary,
          strike: false,
          maintenance: false,
          overtimePulse: false,
          dotMode: _DotMode.none,
        );
      case LiveStationCardStatus.maintenance:
      case LiveStationCardStatus.inactive:
        final inactive = s.status == LiveStationCardStatus.inactive;
        return _StationVisual(
          label: inactive ? 'INACTIVE' : 'MAINTENANCE',
          pillFg: _grey,
          pillBg: const Color(0x0FFFFFFF),
          ring: _idleRing,
          nameFg: ArenaColors.textPrimary.withValues(alpha: 0.55),
          timerText: 'DOWN',
          timerLabel: inactive ? 'DISABLED' : 'NOT BOOKABLE',
          timerFg: _timerDim,
          timerLabelFg: _labelDim,
          barFraction: 0,
          barFg: const Color(0x00000000),
          sweep: false,
          playerLine: playerLine,
          playerFg: ArenaColors.textPrimary.withValues(alpha: 0.45),
          seatsText: seatsText,
          gameLabel: 'RATE',
          gameName: _rateName(s),
          gameFg: ArenaColors.textPrimary.withValues(alpha: 0.5),
          amountLabel: '',
          amountText: '—',
          amountFg: ArenaColors.textPrimary.withValues(alpha: 0.25),
          strike: true,
          maintenance: !inactive,
          overtimePulse: false,
          dotMode: _DotMode.none,
        );
    }
  }

  static String _rateName(LiveStationCardData s) => s.rateText;

  static _StationVisual _busy(
    LiveStationCardData s, {
    required String label,
    required Color accent,
    required Color ring,
    required Color wash,
    required Color pillBg,
    required _DotMode dotMode,
    required String playerLine,
    required String seatsText,
    bool overtimePulse = false,
  }) {
    return _StationVisual(
      label: label,
      pillFg: accent,
      pillBg: pillBg,
      ring: ring,
      wash: wash,
      nameFg: ArenaColors.textPrimary,
      timerText: s.timerText,
      timerLabel: s.timerLabel,
      timerFg: accent,
      timerLabelFg: (label == 'LAST 5 MIN' || label == 'OVER TIME')
          ? accent
          : _labelDim,
      barFraction: s.progressFraction,
      barFg: accent,
      sweep: true,
      playerLine: playerLine,
      playerFg: ArenaColors.textPrimary,
      seatsText: seatsText,
      gameLabel: 'PLAYING',
      gameName: s.gameName ?? '—',
      gameFg: ArenaColors.textPrimary,
      amountLabel: s.amountLabel,
      amountText: s.amountText,
      amountFg: overtimePulse ? ArenaColors.danger : ArenaColors.textPrimary,
      strike: false,
      maintenance: false,
      overtimePulse: overtimePulse,
      dotMode: dotMode,
    );
  }
}

/// Diagonal hatch: `repeating-linear-gradient(135deg,#0F1015 0 9px,#121319 9px 18px)`.
class _HatchPainter extends CustomPainter {
  const _HatchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF0F1015),
    );
    final paint = Paint()
      ..color = const Color(0xFF121319)
      ..strokeWidth = 9
      ..style = PaintingStyle.stroke;
    const period = 18.0;
    for (double x = -size.height; x < size.width + size.height; x += period) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
