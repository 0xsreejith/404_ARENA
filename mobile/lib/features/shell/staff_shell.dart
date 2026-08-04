import 'dart:async';

import 'package:arena_os/app/theme/arena_colors.dart';
import 'package:arena_os/core/permissions/can.dart';
import 'package:arena_os/features/auth/auth_controller.dart';
import 'package:arena_os/features/floor/floor_controller.dart';
import 'package:arena_os/features/lobby_ui/lobby_fonts.dart';
import 'package:arena_os/features/tenant/tenant_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Breakpoint: Lobby HTML chrome is tablet-first; below this use phone chrome.
const double _kTabletShellMinWidth = 900;

/// Production counter shell matching `404 Lobby OS.dc.html` chrome on tablet,
/// with a phone-safe SafeArea + bottom nav on narrow devices (Epic 7).
class StaffShell extends ConsumerStatefulWidget {
  const StaffShell({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<StaffShell> createState() => _StaffShellState();
}

class _StaffShellState extends ConsumerState<StaffShell> {
  Timer? _clock;
  String _clockLabel = '';

  @override
  void initState() {
    super.initState();
    _tickClock();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _tickClock());
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  void _tickClock() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    final label = '$h:$m:$s';
    if (label != _clockLabel && mounted) {
      setState(() => _clockLabel = label);
    }
  }

  (String title, String subtitle) _headerCopy(String location) {
    if (location.startsWith('/checkout')) {
      return ('Checkout', 'Server totals only · take payment and print');
    }
    if (location.startsWith('/shift')) {
      return (
        'Shift close',
        'Open the drawer · expected cash from payments · count before handover',
      );
    }
    return (
      'Floor',
      'Live station state · tap a card to start or manage a session',
    );
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(tenantControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final floor = ref.watch(floorControllerProvider);
    final canFloor =
        ref.watch(canProvider('session.view')) || ref.watch(canProvider('station.view'));
    final canShift = ref.watch(canProvider('shift.view'));
    final location = GoRouterState.of(context).matchedLocation;
    final copy = _headerCopy(location);

    final live = floor.stations
        .where(
          (s) =>
              s.derivedState == DerivedStationState.live ||
              s.derivedState == DerivedStationState.ending ||
              s.derivedState == DerivedStationState.overtime ||
              s.derivedState == DerivedStationState.paused,
        )
        .length;
    final totalStations = floor.stations.length;
    final unbilled = floor.unbilledSessions.length;
    final displayName =
        (auth.userContext?['user'] as Map?)?['display_name'] as String? ?? 'Staff';
    final initials = displayName.trim().isEmpty
        ? '?'
        : displayName
            .trim()
            .split(RegExp(r'\s+'))
            .take(2)
            .map((p) => p.isEmpty ? '' : p[0].toUpperCase())
            .join();

    final nav = <_NavDest>[
      if (canFloor)
        _NavDest(
          path: '/floor',
          label: 'FLOOR',
          sub: '$live LIVE',
          active: location.startsWith('/floor') || location.startsWith('/checkout'),
        ),
      if (canShift)
        _NavDest(
          path: '/shift',
          label: 'SHIFT',
          sub: 'CASH',
          active: location.startsWith('/shift'),
        ),
    ];

    return ColoredBox(
      color: ArenaColors.frame,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tablet = constraints.maxWidth >= _kTabletShellMinWidth;
          if (tablet) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Sidebar(
                  brandName: tenant.brandName,
                  branchName:
                      (tenant.selectedArena?['name'] as String? ?? 'BRANCH').toUpperCase(),
                  staffName: displayName,
                  staffInitials: initials.isEmpty ? '?' : initials,
                  items: nav,
                  onNavigate: (path) => context.go(path),
                  onSwitchBranch: () => context.go('/arenas'),
                  onSignOut: () async {
                    await ref.read(authControllerProvider.notifier).signOut();
                    if (context.mounted) context.go('/sign-in');
                  },
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(
                        title: copy.$1,
                        subtitle: copy.$2,
                        showStats:
                            location.startsWith('/floor') || location.startsWith('/checkout'),
                        compact: false,
                        busy: totalStations == 0 ? '—' : '$live/$totalStations',
                        unbilled: '$unbilled',
                        clock: _clockLabel,
                        onUnbilled: canFloor ? () => context.go('/floor') : null,
                      ),
                      Expanded(child: _MaterialBody(child: widget.child)),
                    ],
                  ),
                ),
              ],
            );
          }

          // Edge-to-edge chrome with guaranteed insets (some sims report 0
          // viewPadding.bottom even with a home indicator).
          final mq = MediaQuery.of(context);
          final topInset = mq.viewPadding.top > 0
              ? mq.viewPadding.top
              : (mq.padding.top > 0 ? mq.padding.top : 54.0);
          final bottomInset = mq.viewPadding.bottom > 0
              ? mq.viewPadding.bottom
              : (mq.padding.bottom > 0 ? mq.padding.bottom : 28.0);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PhoneTopBar(
                brandName: tenant.brandName,
                branchName:
                    (tenant.selectedArena?['name'] as String? ?? 'BRANCH').toUpperCase(),
                title: copy.$1,
                busy: totalStations == 0 ? '—' : '$live/$totalStations',
                unbilled: '$unbilled',
                clock: _clockLabel,
                topInset: topInset,
                onSwitchBranch: () => context.go('/arenas'),
                onSignOut: () async {
                  await ref.read(authControllerProvider.notifier).signOut();
                  if (context.mounted) context.go('/sign-in');
                },
                onUnbilled: canFloor ? () => context.go('/floor') : null,
              ),
              Expanded(child: _MaterialBody(child: widget.child)),
              if (nav.isNotEmpty)
                _PhoneBottomNav(
                  items: nav,
                  bottomInset: bottomInset,
                  onNavigate: (path) => context.go(path),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Scaffold body host — Lobby chrome has no root Scaffold, but TextField /
/// SegmentedButton / SnackBar need Material + ScaffoldMessenger ancestors.
class _MaterialBody extends StatelessWidget {
  const _MaterialBody({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ArenaColors.frame,
      body: DefaultTextStyle(
        style: LobbyFonts.body(size: 14),
        child: child,
      ),
    );
  }
}

class _NavDest {
  const _NavDest({
    required this.path,
    required this.label,
    required this.sub,
    required this.active,
  });

  final String path;
  final String label;
  final String sub;
  final bool active;
}

class _PhoneTopBar extends StatelessWidget {
  const _PhoneTopBar({
    required this.brandName,
    required this.branchName,
    required this.title,
    required this.busy,
    required this.unbilled,
    required this.clock,
    required this.topInset,
    required this.onSwitchBranch,
    required this.onSignOut,
    this.onUnbilled,
  });

  final String brandName;
  final String branchName;
  final String title;
  final String busy;
  final String unbilled;
  final String clock;
  final double topInset;
  final VoidCallback onSwitchBranch;
  final Future<void> Function() onSignOut;
  final VoidCallback? onUnbilled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, topInset + 10, 10, 12),
      decoration: BoxDecoration(
        color: ArenaColors.sidebar,
        border: Border(
          bottom: BorderSide(color: const Color(0xFFFFFFFF).withValues(alpha: 0.07)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Brand strip — matches Lobby sidebar brand + FLOOR MODE chip.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        brandName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LobbyFonts.display(
                          size: 18,
                          height: 1.15,
                          letterSpacing: 18 * 0.02,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: ArenaColors.accent.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        'FLOOR MODE',
                        style: LobbyFonts.mono(
                          size: 8.5,
                          weight: FontWeight.w700,
                          letterSpacing: 1.2,
                          height: 1.2,
                          color: ArenaColors.accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                clock,
                style: LobbyFonts.mono(
                  size: 13,
                  weight: FontWeight.w600,
                  height: 1.2,
                  letterSpacing: 0.4,
                  color: ArenaColors.textPrimary.withValues(alpha: 0.8),
                ),
              ),
              _IconAction(
                tooltip: 'Switch branch',
                icon: Icons.swap_horiz,
                onTap: onSwitchBranch,
              ),
              _IconAction(
                tooltip: 'Sign out',
                icon: Icons.logout,
                onTap: () => onSignOut(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Screen title — matches Lobby main header (`Floor` + subtitle).
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LobbyFonts.display(
              size: 22,
              height: 1.15,
              letterSpacing: 22 * 0.02,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            branchName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LobbyFonts.mono(
              size: 10,
              letterSpacing: 1.0,
              height: 1.3,
              color: ArenaColors.accent,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatChip(label: 'BUSY', value: busy, compact: true),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onUnbilled,
                child: _StatChip(
                  label: 'UNBILLED',
                  value: unbilled,
                  accent: true,
                  compact: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: ArenaColors.textMuted, size: 20),
        ),
      ),
    );
  }
}

class _PhoneBottomNav extends StatelessWidget {
  const _PhoneBottomNav({
    required this.items,
    required this.bottomInset,
    required this.onNavigate,
  });

  final List<_NavDest> items;
  final double bottomInset;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ArenaColors.sidebar,
      child: Container(
        padding: EdgeInsets.fromLTRB(10, 8, 10, 10 + bottomInset),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: const Color(0xFFFFFFFF).withValues(alpha: 0.07)),
          ),
        ),
        child: Row(
          children: [
            for (final item in items)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onNavigate(item.path),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: item.active
                            ? ArenaColors.accent.withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: item.active
                            ? Border.all(color: ArenaColors.accent.withValues(alpha: 0.35))
                            : null,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.label,
                            style: LobbyFonts.display(
                              size: 12,
                              color: item.active
                                  ? ArenaColors.accent
                                  : ArenaColors.textPrimary.withValues(alpha: 0.7),
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.sub,
                            style: LobbyFonts.mono(
                              size: 9,
                              color: item.active
                                  ? ArenaColors.accent.withValues(alpha: 0.85)
                                  : ArenaColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatefulWidget {
  const _Sidebar({
    required this.brandName,
    required this.branchName,
    required this.staffName,
    required this.staffInitials,
    required this.items,
    required this.onNavigate,
    required this.onSwitchBranch,
    required this.onSignOut,
  });

  final String brandName;
  final String branchName;
  final String staffName;
  final String staffInitials;
  final List<_NavDest> items;
  final ValueChanged<String> onNavigate;
  final VoidCallback onSwitchBranch;
  final Future<void> Function() onSignOut;

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  String? _hoverPath;

  @override
  Widget build(BuildContext context) {
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
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.brandName, style: LobbyFonts.display(size: 18, height: 1.05)),
                const SizedBox(height: 6),
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
                      letterSpacing: 1.4,
                      color: ArenaColors.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final item in widget.items) ...[
            _NavItem(
              label: item.label,
              sub: item.sub,
              active: item.active,
              hovered: _hoverPath == item.path && !item.active,
              onEnter: () => setState(() => _hoverPath = item.path),
              onExit: () => setState(() {
                if (_hoverPath == item.path) _hoverPath = null;
              }),
              onTap: () => widget.onNavigate(item.path),
            ),
            const SizedBox(height: 5),
          ],
          const Spacer(),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onSwitchBranch,
            child: Container(
              constraints: const BoxConstraints(minHeight: 46),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFFFFF).withValues(alpha: 0.12)),
              ),
              child: Text(
                'SWITCH BRANCH',
                style: LobbyFonts.mono(
                  size: 9,
                  letterSpacing: 1.2,
                  color: ArenaColors.textPrimary.withValues(alpha: 0.72),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.branchName,
            textAlign: TextAlign.center,
            style: LobbyFonts.mono(
              size: 9,
              color: ArenaColors.accent,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: const Color(0xFFFFFFFF).withValues(alpha: 0.07)),
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  child: Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: ArenaColors.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          widget.staffInitials,
                          style: LobbyFonts.mono(
                            size: 9,
                            weight: FontWeight.w700,
                            color: ArenaColors.accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.staffName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: LobbyFonts.body(
                            size: 11.5,
                            weight: FontWeight.w600,
                            color: ArenaColors.textPrimary.withValues(alpha: 0.72),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onSignOut(),
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
                      'SIGN OUT',
                      style: LobbyFonts.mono(
                        size: 9,
                        letterSpacing: 1.2,
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
            ? const Color(0xFFFFFFFF).withValues(alpha: 0.04)
            : Colors.transparent;
    final fg = active ? ArenaColors.accent : ArenaColors.textPrimary.withValues(alpha: 0.78);

    return MouseRegion(
      onEnter: (_) => onEnter(),
      onExit: (_) => onExit(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: active
                ? Border.all(color: ArenaColors.accent.withValues(alpha: 0.35))
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: LobbyFonts.display(size: 13, color: fg, letterSpacing: 1.0),
              ),
              const SizedBox(height: 2),
              Text(
                sub,
                style: LobbyFonts.mono(
                  size: 9,
                  letterSpacing: 0.8,
                  color: fg.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
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
    required this.compact,
    required this.busy,
    required this.unbilled,
    required this.clock,
    this.onUnbilled,
  });

  final String title;
  final String subtitle;
  final bool showStats;
  final bool compact;
  final String busy;
  final String unbilled;
  final String clock;
  final VoidCallback? onUnbilled;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 64 : 76,
      padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 22),
      decoration: BoxDecoration(
        color: ArenaColors.sidebar,
        border: Border(
          bottom: BorderSide(color: const Color(0xFFFFFFFF).withValues(alpha: 0.07)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LobbyFonts.display(size: compact ? 18 : 22, height: 1),
                ),
                if (!compact) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LobbyFonts.body(
                      size: 12.5,
                      color: ArenaColors.textPrimary.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (showStats) ...[
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StatChip(label: 'BUSY', value: busy, compact: compact),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: onUnbilled,
                        child: _StatChip(
                          label: 'UNBILLED',
                          value: unbilled,
                          accent: true,
                          compact: compact,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        clock,
                        style: LobbyFonts.mono(
                          size: compact ? 14 : 18,
                          weight: FontWeight.w700,
                          color: ArenaColors.textPrimary.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ] else
            Text(
              clock,
              style: LobbyFonts.mono(
                size: compact ? 14 : 18,
                weight: FontWeight.w700,
                color: ArenaColors.textPrimary.withValues(alpha: 0.85),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    this.accent = false,
    this.compact = false,
  });

  final String label;
  final String value;
  final bool accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = accent ? ArenaColors.warning : ArenaColors.accent;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: LobbyFonts.mono(
              size: 8.5,
              letterSpacing: 1.0,
              height: 1.25,
              color: color,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: LobbyFonts.mono(
              size: compact ? 13 : 14,
              weight: FontWeight.w700,
              height: 1.15,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
