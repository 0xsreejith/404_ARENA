import 'package:arena_os/app/theme/arena_colors.dart';
import 'package:arena_os/features/lobby_ui/demo_data.dart';
import 'package:arena_os/features/lobby_ui/lobby_controller.dart';
import 'package:arena_os/features/lobby_ui/lobby_fonts.dart';
import 'package:arena_os/features/lobby_ui/widgets/lobby_anims.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _amber = Color(0xFFFFB020);
const _danger = Color(0xFFFF6B6B);
const _backdrop = Color(0xE6060402);

/// S5 Time-up alert overlay — full-screen backdrop + glowing panel.
class TimeUpAlertOverlay extends ConsumerWidget {
  const TimeUpAlertOverlay({required this.stationId, super.key});

  final String stationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(lobbyUiProvider.notifier);
    final state = ref.watch(lobbyUiProvider);
    final station = ctrl.station(stationId);
    final rem = station.remainingMinutes ?? 0;
    final heads = station.isPerHead ? (station.players.isEmpty ? 1 : station.players.length) : 1;
    final extend30 = DemoData.inr((30 / 60 * station.ratePaise * heads).round());
    final extend60 = DemoData.inr((station.ratePaise * heads).round());
    final due = DemoData.inr(station.runningAmountPaise);
    final booked = station.bookedMinutes;
    final headline = booked != null
        ? (booked == 60 ? '1 hour complete' : '$booked minutes complete')
        : 'Session complete';
    final players = station.players.map((p) => p.split(' ').first).join(' + ');
    final playersLine = station.players.length > 1 ? players : '$players · solo';
    final gameLine = '${station.game ?? ''} · ${station.type} · ${station.zone}';
    final alertMeta = state.soundOn
        ? 'CHIME PLAYED · OWNER NOTIFIED ON PHONE'
        : 'MUTED · OWNER NOTIFIED ON PHONE';

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: LobbyAnims.fadeIn,
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: ColoredBox(
        color: _backdrop,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(44),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1010),
              child: AlertGlowPanel(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(38, 34, 38, 34),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _header(alertMeta, ctrl.minimizeAlert),
                      const SizedBox(height: 22),
                      _stationRow(station.id, rem, due),
                      const SizedBox(height: 14),
                      _headlineRow(headline, playersLine, gameLine),
                      const SizedBox(height: 26),
                      _actionsGrid(
                        extend30: extend30,
                        extend60: extend60,
                        due: due,
                        onExtend30: () => ctrl.extendAlert(30),
                        onExtend60: () => ctrl.extendAlert(60),
                        onEndBill: ctrl.endAndBillFromAlert,
                        onSnooze: ctrl.snoozeAlert,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Over time is already billing per 15 minutes. Snoozing does not stop the meter.',
                        style: LobbyFonts.mono(
                          size: 10.5,
                          letterSpacing: 10.5 * 0.08,
                          color: ArenaColors.textPrimary.withValues(alpha: 0.32),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(String meta, VoidCallback onMinimize) {
    return Row(
      children: <Widget>[
        BlinkOpacity(
          period: const Duration(milliseconds: 1000),
          child: Container(
            width: 11,
            height: 11,
            decoration: const BoxDecoration(color: _amber, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 14),
        Text(
          'TIME UP',
          style: LobbyFonts.mono(
            size: 13,
            weight: FontWeight.w700,
            letterSpacing: 13 * 0.34,
            color: _amber,
          ),
        ),
        const Spacer(),
        Text(
          meta,
          style: LobbyFonts.mono(
            size: 11,
            letterSpacing: 11 * 0.1,
            color: ArenaColors.textPrimary.withValues(alpha: 0.4),
          ),
        ),
        const SizedBox(width: 14),
        _MinimiseButton(onTap: onMinimize),
      ],
    );
  }

  Widget _stationRow(String id, double rem, String due) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Flexible(
          child: Text(
            id,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LobbyFonts.display(
              size: 104,
              weight: FontWeight.w700,
              height: 0.86,
              letterSpacing: 104 * 0.01,
              color: _amber,
            ).copyWith(
              shadows: <Shadow>[
                Shadow(color: _amber.withValues(alpha: 0.35), blurRadius: 60),
              ],
            ),
          ),
        ),
        const Spacer(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(
              'OVER BY',
              style: LobbyFonts.mono(
                size: 10,
                letterSpacing: 10 * 0.13,
                color: ArenaColors.textPrimary.withValues(alpha: 0.35),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              DemoData.formatDuration(rem),
              style: LobbyFonts.mono(
                size: 46,
                weight: FontWeight.w700,
                height: 1,
                color: _danger,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '$due so far',
              style: LobbyFonts.mono(
                size: 12,
                color: ArenaColors.textPrimary.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ],
    );
  }

  Widget _headlineRow(String headline, String players, String game) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 18,
      runSpacing: 8,
      children: <Widget>[
        Text(
          headline,
          style: LobbyFonts.display(size: 36, weight: FontWeight.w600, height: 1.05),
        ),
        Text(
          players,
          style: LobbyFonts.body(
            size: 19,
            weight: FontWeight.w600,
            color: ArenaColors.textPrimary.withValues(alpha: 0.62),
          ),
        ),
        Text(
          game,
          style: LobbyFonts.mono(
            size: 13,
            letterSpacing: 13 * 0.06,
            color: ArenaColors.textPrimary.withValues(alpha: 0.4),
          ),
        ),
      ],
    );
  }

  Widget _actionsGrid({
    required String extend30,
    required String extend60,
    required String due,
    required VoidCallback onExtend30,
    required VoidCallback onExtend60,
    required VoidCallback onEndBill,
    required VoidCallback onSnooze,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 720;
        if (narrow) {
          return Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: _actionBtn('EXTEND 30', extend30, _ghostAction, onExtend30)),
                  const SizedBox(width: 12),
                  Expanded(child: _actionBtn('EXTEND 1 HR', extend60, _ghostAction, onExtend60)),
                ],
              ),
              const SizedBox(height: 12),
              _actionBtn('END AND BILL', '$due DUE', _amberAction, onEndBill, flex: false),
              const SizedBox(height: 12),
              _actionBtn('SNOOZE 5', 'FIRES AGAIN', _snoozeAction, onSnooze, flex: false),
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: _actionBtn('EXTEND 30', extend30, _ghostAction, onExtend30)),
              const SizedBox(width: 12),
              Expanded(child: _actionBtn('EXTEND 1 HR', extend60, _ghostAction, onExtend60)),
              const SizedBox(width: 12),
              Expanded(
                flex: 12,
                child: _actionBtn('END AND BILL', '$due DUE', _amberAction, onEndBill),
              ),
              const SizedBox(width: 12),
              Expanded(child: _actionBtn('SNOOZE 5', 'FIRES AGAIN', _snoozeAction, onSnooze)),
            ],
          ),
        );
      },
    );
  }

  static const _ghostAction = _ActionStyle(
    bg: Color(0x0FFFFFFF),
    fg: ArenaColors.textPrimary,
    subFg: Color(0x73E8EAF0),
    ring: Color(0x24FFFFFF),
  );

  static const _amberAction = _ActionStyle(
    bg: _amber,
    fg: Color(0xFF0B0B0F),
    subFg: Color(0x990B0B0F),
    ring: null,
  );

  static const _snoozeAction = _ActionStyle(
    bg: Color(0x00000000),
    fg: Color(0x99E8EAF0),
    subFg: Color(0x4DE8EAF0),
    ring: Color(0x24FFFFFF),
  );

  Widget _actionBtn(
    String label,
    String sub,
    _ActionStyle style,
    VoidCallback onTap, {
    bool flex = true,
  }) {
    final btn = _AlertActionButton(label: label, sub: sub, style: style, onTap: onTap);
    return flex ? btn : SizedBox(width: double.infinity, child: btn);
  }
}

class _ActionStyle {
  const _ActionStyle({
    required this.bg,
    required this.fg,
    required this.subFg,
    required this.ring,
  });

  final Color bg;
  final Color fg;
  final Color subFg;
  final Color? ring;
}

class _AlertActionButton extends StatefulWidget {
  const _AlertActionButton({
    required this.label,
    required this.sub,
    required this.style,
    required this.onTap,
  });

  final String label;
  final String sub;
  final _ActionStyle style;
  final VoidCallback onTap;

  @override
  State<_AlertActionButton> createState() => _AlertActionButtonState();
}

class _AlertActionButtonState extends State<_AlertActionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: LobbyAnims.hover,
          height: 78,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover
                ? Color.lerp(widget.style.bg, const Color(0xFFFFFFFF), 0.12)
                : widget.style.bg,
            borderRadius: BorderRadius.circular(12),
            border: widget.style.ring != null ? Border.all(color: widget.style.ring!) : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                widget.label,
                style: LobbyFonts.display(
                  size: 17,
                  weight: FontWeight.w700,
                  letterSpacing: 17 * 0.07,
                  color: widget.style.fg,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                widget.sub,
                style: LobbyFonts.mono(
                  size: 10,
                  letterSpacing: 10 * 0.08,
                  color: widget.style.subFg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MinimiseButton extends StatefulWidget {
  const _MinimiseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_MinimiseButton> createState() => _MinimiseButtonState();
}

class _MinimiseButtonState extends State<_MinimiseButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: LobbyAnims.hover,
          transform: Matrix4.translationValues(0, _hover ? 1 : 0, 0),
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: _hover ? _amber.withValues(alpha: 0.2) : _amber.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _amber.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: 22,
                height: 22,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: <Widget>[
                    const Positioned(top: 1, child: BobArrow()),
                    Container(
                      width: 20,
                      height: 3,
                      decoration: BoxDecoration(
                        color: _amber,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 11),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'MINIMISE',
                    style: LobbyFonts.display(
                      size: 13,
                      weight: FontWeight.w700,
                      letterSpacing: 13 * 0.09,
                      color: _amber,
                    ),
                  ),
                  Text(
                    'KEEP WORKING · COMES BACK AS A BUBBLE',
                    style: LobbyFonts.mono(
                      size: 8.5,
                      letterSpacing: 8.5 * 0.08,
                      color: _amber.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Minimised alert bubble — tap to restore full S5 overlay.
class AlertBubbleLayer extends ConsumerWidget {
  const AlertBubbleLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lobbyUiProvider);
    final ctrl = ref.read(lobbyUiProvider.notifier);
    if (state.alertBubbles.isEmpty) return const SizedBox.shrink();

    return Stack(
      children: <Widget>[
        for (final bubble in state.alertBubbles)
          _AlertBubbleChip(
            bubble: bubble,
            station: ctrl.station(bubble.stationId),
            onOpen: () => ctrl.restoreAlert(bubble.stationId),
            onDismiss: () => ctrl.dismissBubble(bubble.stationId),
            onMove: (x, y) => ctrl.moveBubble(bubble.stationId, x, y),
          ),
      ],
    );
  }
}

class _AlertBubbleChip extends StatefulWidget {
  const _AlertBubbleChip({
    required this.bubble,
    required this.station,
    required this.onOpen,
    required this.onDismiss,
    required this.onMove,
  });

  final AlertBubble bubble;
  final DemoStation station;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;
  final void Function(double x, double y) onMove;

  @override
  State<_AlertBubbleChip> createState() => _AlertBubbleChipState();
}

class _AlertBubbleChipState extends State<_AlertBubbleChip> {
  Offset? _dragOrigin;
  Offset? _pointerOrigin;

  @override
  Widget build(BuildContext context) {
    final rem = widget.station.remainingMinutes ?? 0;
    final over = rem < 0;
    final fg = over ? _danger : _amber;
    final ring = over ? const Color(0x8CFF4444) : const Color(0x80FFB020);
    final who = widget.station.players.isEmpty
        ? 'Walk-in'
        : '${widget.station.players.first.split(' ').first}${widget.station.players.length > 1 ? ' +${widget.station.players.length - 1}' : ''}';
    final due = DemoData.inr(widget.station.runningAmountPaise);
    final time = widget.station.bookedMinutes != null
        ? DemoData.formatDuration(rem)
        : '--:--';

    return Positioned(
      left: widget.bubble.x,
      top: widget.bubble.y,
      child: BubbleEntrance(
        child: GestureDetector(
          onPanStart: (d) {
            _dragOrigin = Offset(widget.bubble.x, widget.bubble.y);
            _pointerOrigin = d.globalPosition;
          },
          onPanUpdate: (d) {
            if (_dragOrigin == null || _pointerOrigin == null) return;
            final delta = d.globalPosition - _pointerOrigin!;
            widget.onMove(
              (_dragOrigin!.dx + delta.dx).clamp(10, 1090),
              (_dragOrigin!.dy + delta.dy).clamp(10, 700),
            );
          },
          onPanEnd: (_) {
            _dragOrigin = null;
            _pointerOrigin = null;
          },
          onTap: widget.onOpen,
          child: Container(
            padding: const EdgeInsets.fromLTRB(15, 12, 14, 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[Color(0xFF1D1609), Color(0xFF100D06)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: ring),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: const Color(0xEB000000),
                  blurRadius: 46,
                  offset: const Offset(0, 22),
                  spreadRadius: -16,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _amber.withValues(alpha: 0.12),
                    border: Border.all(color: _amber.withValues(alpha: 0.35), width: 1.5),
                  ),
                  child: Breathe(
                    period: const Duration(milliseconds: 1200),
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
                    ),
                  ),
                ),
                const SizedBox(width: 13),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          widget.station.id,
                          style: LobbyFonts.display(
                            size: 18,
                            weight: FontWeight.w700,
                            letterSpacing: 18 * 0.03,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Text(
                          time,
                          style: LobbyFonts.mono(
                            size: 17,
                            weight: FontWeight.w700,
                            color: fg,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '$who · $due DUE · TAP TO OPEN',
                      style: LobbyFonts.mono(
                        size: 9.5,
                        letterSpacing: 9.5 * 0.07,
                        color: ArenaColors.textPrimary.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 13),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List<Widget>.generate(
                    3,
                    (_) => Container(
                      width: 14,
                      height: 2,
                      margin: const EdgeInsets.symmetric(vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0x33FFFFFF),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: widget.onDismiss,
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(shape: BoxShape.circle),
                    child: Text(
                      '✕',
                      style: LobbyFonts.mono(
                        size: 13,
                        color: ArenaColors.textPrimary.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
