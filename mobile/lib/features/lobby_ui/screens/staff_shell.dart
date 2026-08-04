import 'package:arena_os/app/theme/arena_colors.dart';
import 'package:arena_os/features/lobby_ui/demo_data.dart';
import 'package:arena_os/features/lobby_ui/lobby_controller.dart';
import 'package:arena_os/features/lobby_ui/lobby_fonts.dart';
import 'package:arena_os/features/lobby_ui/screens/floor_screen.dart';
import 'package:arena_os/features/lobby_ui/screens/members_screen.dart';
import 'package:arena_os/features/lobby_ui/screens/session_sheet.dart';
import 'package:arena_os/features/lobby_ui/screens/shift_screen.dart';
import 'package:arena_os/features/lobby_ui/screens/stock_screen.dart';
import 'package:arena_os/features/lobby_ui/widgets/lobby_anims.dart';
import 'package:arena_os/features/lobby_ui/widgets/time_up_alert.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tablet counter shell matching `404 Lobby OS.dc.html` — custom sidebar + header.
///
/// No Material AppBar / NavigationBar / NavigationRail.
class StaffShell extends ConsumerStatefulWidget {
  const StaffShell({super.key});

  @override
  ConsumerState<StaffShell> createState() => _StaffShellState();
}

class _StaffShellState extends ConsumerState<StaffShell> {
  String? _openedStationId;

  static (String title, String subtitle) _headerCopy(LobbyTab tab, DemoStaff? staff) {
    return switch (tab) {
      LobbyTab.floor => (
          'Floor',
          'Live station state · tap a card to start or manage a session',
        ),
      LobbyTab.members => (
          'Look up a member',
          'Type a phone number — that is all staff need at the counter',
        ),
      LobbyTab.stock => (
          'Snack counter',
          'Sell onto a session bill · count what is left',
        ),
      LobbyTab.more => (
          'Shift close',
          '${staff?.name ?? 'Staff'} · since 14:00 · count the drawer before you hand over',
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lobbyUiProvider);
    final ctrl = ref.read(lobbyUiProvider.notifier);
    final staff = state.selectedStaff;

    ref.listen<LobbyUiState>(lobbyUiProvider, (prev, next) {
      final id = next.selectedStationId;
      if (id != null && id != _openedStationId && mounted) {
        _openedStationId = id;
        final station = ref.read(lobbyUiProvider.notifier).station(id);
        showSessionSheet(
          context,
          ref,
          station,
          kind: next.sheetKind,
        ).whenComplete(() {
          _openedStationId = null;
        });
      }
    });

    final body = switch (state.tab) {
      LobbyTab.floor => const FloorScreen(),
      LobbyTab.members => const MembersScreen(),
      LobbyTab.stock => const StockScreen(),
      LobbyTab.more => const ShiftScreen(),
    };

    final copy = _headerCopy(state.tab, staff);
    final live = DemoData.liveCount;
    final low = DemoData.lowStockCount;
    final snacksSub = low > 0 ? '$low LOW' : 'IN STOCK';

    return ColoredBox(
      color: ArenaColors.frame,
      child: Stack(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Sidebar(
                tab: state.tab,
                staff: staff,
                soundOn: state.soundOn,
                floorSub: '$live LIVE',
                snacksSub: snacksSub,
                shiftSub: DemoData.inr(DemoData.collectedPaise),
                onTab: ctrl.setTab,
                onSwitchMode: ctrl.switchMode,
                onToggleSound: ctrl.toggleSound,
                onSwitchStaff: ctrl.openSwitch,
                onLock: ctrl.lock,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _Header(
                      title: copy.$1,
                      subtitle: copy.$2,
                      showStats: state.tab == LobbyTab.floor,
                      collected: DemoData.inr(DemoData.collectedPaise),
                      busy: '$live/${DemoData.stations.length}',
                      onFloor: DemoData.inr(DemoData.runningFloorPaise),
                      clock: state.clockLabel,
                    ),
                    Expanded(
                      child: Scaffold(
                        backgroundColor: ArenaColors.frame,
                        body: DefaultTextStyle(
                          style: LobbyFonts.body(size: 14),
                          child: body,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (state.toast != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 28,
              child: Center(child: _ToastPill(toast: state.toast!)),
            ),
          if (state.alertStationId != null)
            Positioned.fill(
              child: TimeUpAlertOverlay(stationId: state.alertStationId!),
            ),
          const Positioned.fill(child: AlertBubbleLayer()),
        ],
      ),
    );
  }
}

class _Sidebar extends StatefulWidget {
  const _Sidebar({
    required this.tab,
    required this.staff,
    required this.soundOn,
    required this.floorSub,
    required this.snacksSub,
    required this.shiftSub,
    required this.onTab,
    required this.onSwitchMode,
    required this.onToggleSound,
    required this.onSwitchStaff,
    required this.onLock,
  });

  final LobbyTab tab;
  final DemoStaff? staff;
  final bool soundOn;
  final String floorSub;
  final String snacksSub;
  final String shiftSub;
  final ValueChanged<LobbyTab> onTab;
  final VoidCallback onSwitchMode;
  final VoidCallback onToggleSound;
  final VoidCallback onSwitchStaff;
  final VoidCallback onLock;

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  LobbyTab? _hover;

  @override
  Widget build(BuildContext context) {
    final activeCount = DemoData.staff.where((s) => s.active).length;
    final items = <(LobbyTab, String, String)>[
      (LobbyTab.floor, 'FLOOR', widget.floorSub),
      (LobbyTab.members, 'MEMBERS', 'LOOK UP'),
      (LobbyTab.stock, 'SNACKS', widget.snacksSub),
      (LobbyTab.more, 'SHIFT', widget.shiftSub),
    ];

    return Container(
      width: 172,
      decoration: BoxDecoration(
        color: ArenaColors.sidebar,
        border: Border(
          right: BorderSide(color: const Color(0xFFFFFFFF).withValues(alpha: 0.07)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  DemoData.arenaMark,
                  style: LobbyFonts.display(size: 21, height: 1),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: ArenaColors.accent.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    'FLOOR MODE',
                    style: LobbyFonts.mono(
                      size: 9.5,
                      weight: FontWeight.w700,
                      letterSpacing: 9.5 * 0.15,
                      color: ArenaColors.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final item in items) ...<Widget>[
            _NavItem(
              label: item.$2,
              sub: item.$3,
              active: widget.tab == item.$1,
              hovered: _hover == item.$1 && widget.tab != item.$1,
              onEnter: () => setState(() => _hover = item.$1),
              onExit: () => setState(() {
                if (_hover == item.$1) _hover = null;
              }),
              onTap: () => widget.onTab(item.$1),
            ),
            const SizedBox(height: 5),
          ],
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _GhostButton(
                label: 'SWITCH MODE',
                minHeight: 46,
                radius: 10,
                onTap: widget.onSwitchMode,
              ),
              const SizedBox(height: 6),
              _SoundToggle(on: widget.soundOn, onTap: widget.onToggleSound),
            ],
          ),
          const SizedBox(height: 5),
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: const Color(0xFFFFFFFF).withValues(alpha: 0.07)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onSwitchStaff,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 56),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      child: Row(
                        children: <Widget>[
                          _Avatar(initials: widget.staff?.initials ?? '?', size: 26),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  widget.staff?.name ?? 'Staff',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: LobbyFonts.body(
                                    size: 11.5,
                                    weight: FontWeight.w600,
                                    color: ArenaColors.textPrimary.withValues(alpha: 0.72),
                                  ),
                                ),
                                Text(
                                  'SWITCH · $activeCount',
                                  style: LobbyFonts.mono(
                                    size: 8.5,
                                    letterSpacing: 8.5 * 0.06,
                                    color: ArenaColors.accent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onLock,
                  child: Container(
                    alignment: Alignment.center,
                    constraints: const BoxConstraints(minHeight: 44),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: const Color(0xFFFFFFFF).withValues(alpha: 0.05),
                        ),
                      ),
                    ),
                    child: Text(
                      'LOCK',
                      style: LobbyFonts.mono(
                        size: 9,
                        letterSpacing: 9 * 0.14,
                        color: ArenaColors.textPrimary.withValues(alpha: 0.34),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.sub,
    required this.active,
    required this.hovered,
    required this.onEnter,
    required this.onExit,
    required this.onTap,
  });

  final String label;
  final String sub;
  final bool active;
  final bool hovered;
  final VoidCallback onEnter;
  final VoidCallback onExit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = active
        ? ArenaColors.accent.withValues(alpha: 0.08)
        : hovered
            ? const Color(0xFFFFFFFF).withValues(alpha: 0.06)
            : const Color(0x00000000);

    return MouseRegion(
      onEnter: (_) => onEnter(),
      onExit: (_) => onExit(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: LobbyAnims.hover,
          transform: Matrix4.translationValues(hovered && !active ? 2 : 0, 0, 0),
          constraints: const BoxConstraints(minHeight: 66),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: active
                ? Border.all(color: ArenaColors.accent.withValues(alpha: 0.26))
                : null,
          ),
          child: Stack(
            children: <Widget>[
              if (active)
                Positioned(
                  left: 0,
                  top: 16,
                  bottom: 16,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: ArenaColors.accent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      label,
                      style: LobbyFonts.display(
                        size: 15,
                        letterSpacing: 15 * 0.06,
                        color: active
                            ? ArenaColors.textPrimary
                            : ArenaColors.textPrimary.withValues(alpha: 0.62),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      sub,
                      style: LobbyFonts.mono(
                        size: 9.5,
                        letterSpacing: 9.5 * 0.07,
                        color: active
                            ? ArenaColors.accent
                            : ArenaColors.textPrimary.withValues(alpha: 0.32),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GhostButton extends StatefulWidget {
  const _GhostButton({
    required this.label,
    required this.minHeight,
    required this.radius,
    required this.onTap,
  });

  final String label;
  final double minHeight;
  final double radius;
  final VoidCallback onTap;

  @override
  State<_GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<_GhostButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          alignment: Alignment.center,
          constraints: BoxConstraints(minHeight: widget.minHeight),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(color: const Color(0xFFFFFFFF).withValues(alpha: 0.12)),
          ),
          child: Text(
            widget.label,
            style: LobbyFonts.display(
              size: 11.5,
              weight: FontWeight.w600,
              letterSpacing: 11.5 * 0.09,
              color: _hover
                  ? ArenaColors.accent
                  : ArenaColors.textPrimary.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }
}

class _SoundToggle extends StatelessWidget {
  const _SoundToggle({required this.on, required this.onTap});

  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 42),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: <Widget>[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? ArenaColors.accent : const Color(0xFFFFFFFF).withValues(alpha: 0.22),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              on ? 'CUES ON' : 'CUES OFF',
              style: LobbyFonts.mono(
                size: 9.5,
                letterSpacing: 9.5 * 0.08,
                color: ArenaColors.textPrimary.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.showStats,
    required this.collected,
    required this.busy,
    required this.onFloor,
    required this.clock,
  });

  final String title;
  final String subtitle;
  final bool showStats;
  final String collected;
  final String busy;
  final String onFloor;
  final String clock;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: const Color(0xFFFFFFFF).withValues(alpha: 0.07)),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LobbyFonts.display(size: 22, letterSpacing: 22 * 0.02),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LobbyFonts.body(
                    size: 12.5,
                    color: ArenaColors.textPrimary.withValues(alpha: 0.42),
                  ),
                ),
              ],
            ),
          ),
          if (showStats) ...<Widget>[
            _Stat(label: 'COLLECTED', value: collected, valueColor: ArenaColors.accent),
            const SizedBox(width: 16),
            _Stat(label: 'BUSY', value: busy),
            const SizedBox(width: 16),
            _Stat(label: 'ON FLOOR', value: onFloor, valueColor: ArenaColors.warning),
            const SizedBox(width: 16),
            const _SyncPill(),
            const SizedBox(width: 16),
          ],
          Text(
            clock,
            style: LobbyFonts.mono(
              size: 19,
              weight: FontWeight.w500,
              letterSpacing: 19 * 0.02,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(
          label,
          style: LobbyFonts.mono(
            size: 9.5,
            letterSpacing: 9.5 * 0.13,
            color: ArenaColors.textPrimary.withValues(alpha: 0.34),
          ),
        ),
        Text(
          value,
          style: LobbyFonts.mono(
            size: 23,
            weight: FontWeight.w700,
            height: 1,
            color: valueColor ?? ArenaColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _SyncPill extends StatelessWidget {
  const _SyncPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: ArenaColors.accent.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: ArenaColors.accent.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          BlinkOpacity(
            period: LobbyAnims.syncBlink,
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: ArenaColors.accent,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'SYNCED · 12s AGO',
            style: LobbyFonts.mono(
              size: 10,
              letterSpacing: 10 * 0.06,
              color: ArenaColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials, required this.size});

  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ArenaColors.accent.withValues(alpha: 0.15),
      ),
      child: Text(
        initials,
        style: LobbyFonts.mono(
          size: size < 30 ? 10 : 12,
          weight: FontWeight.w700,
          color: ArenaColors.accent,
        ),
      ),
    );
  }
}

class _ToastPill extends StatelessWidget {
  const _ToastPill({required this.toast});

  final LobbyToast toast;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: LobbyAnims.toastIn,
      curve: Curves.easeOut,
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - t)),
            child: child,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: ArenaColors.toast,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: const Color(0xFFFFFFFF).withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: ArenaColors.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Text(toast.message, style: LobbyFonts.body(size: 14, weight: FontWeight.w500)),
            if (toast.meta != null) ...<Widget>[
              const SizedBox(width: 12),
              Text(
                toast.meta!,
                style: LobbyFonts.mono(
                  size: 10,
                  letterSpacing: 10 * 0.06,
                  color: ArenaColors.textPrimary.withValues(alpha: 0.4),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
