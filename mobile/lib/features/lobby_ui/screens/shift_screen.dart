import 'package:arena_os/app/theme/arena_colors.dart';
import 'package:arena_os/features/lobby_ui/demo_data.dart';
import 'package:arena_os/features/lobby_ui/lobby_fonts.dart';
import 'package:arena_os/features/lobby_ui/widgets/lobby_button.dart';
import 'package:flutter/widgets.dart';

/// S16 Shift close — shell owns the page title.
class ShiftScreen extends StatelessWidget {
  const ShiftScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final shift = DemoData.shift;
    final busy = DemoData.stations.where((s) => s.isBusy).toList();
    final busyCount = busy.length;
    final snacksPaise = DemoData.products.fold<int>(
      0,
      (sum, p) => sum + p.soldToday * p.pricePaise,
    );
    final snacksItems = DemoData.products.fold<int>(0, (sum, p) => sum + p.soldToday);
    final coinsRedeemed = 380;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 720
                  ? 4
                  : c.maxWidth >= 480
                      ? 2
                      : 1;
              final stats = <(String, String, String, Color)>[
                (
                  'COLLECTED THIS SHIFT',
                  DemoData.inr(DemoData.collectedPaise),
                  'Play sales · ${DemoData.inr(shift.playSalesPaise)}',
                  ArenaColors.accent,
                ),
                (
                  'STILL ON THE FLOOR',
                  DemoData.inr(DemoData.runningFloorPaise),
                  '$busyCount open ${busyCount == 1 ? 'session' : 'sessions'}',
                  busyCount > 0
                      ? ArenaColors.warning
                      : ArenaColors.textPrimary.withValues(alpha: 0.4),
                ),
                (
                  'SNACKS SOLD',
                  DemoData.inr(snacksPaise),
                  '$snacksItems items onto session bills',
                  ArenaColors.textPrimary,
                ),
                (
                  'COINS REDEEMED',
                  '$coinsRedeemed',
                  'Worth ${DemoData.inr(19000)} off bills',
                  ArenaColors.textPrimary,
                ),
              ];
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: cols == 1 ? 3.4 : 1.55,
                children: <Widget>[
                  for (final s in stats)
                    _KpiCard(label: s.$1, value: s.$2, sub: s.$3, valueColor: s.$4),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 720;
              final running = _StillRunningPanel(busy: busy, busyCount: busyCount);
              final drawer = _DrawerPanel(shift: shift, busyCount: busyCount);
              if (!wide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    running,
                    const SizedBox(height: 14),
                    drawer,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: running),
                  const SizedBox(width: 14),
                  SizedBox(width: 340, child: drawer),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.valueColor,
  });

  final String label;
  final String value;
  final String sub;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(17, 15, 17, 15),
      decoration: BoxDecoration(
        color: ArenaColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x12FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            label,
            style: LobbyFonts.mono(
              size: 9.5,
              letterSpacing: 9.5 * 0.12,
              color: ArenaColors.textPrimary.withValues(alpha: 0.38),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: LobbyFonts.mono(
              size: 28,
              weight: FontWeight.w700,
              height: 1,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            sub,
            style: LobbyFonts.body(
              size: 11.5,
              color: ArenaColors.textPrimary.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _StillRunningPanel extends StatelessWidget {
  const _StillRunningPanel({required this.busy, required this.busyCount});

  final List<DemoStation> busy;
  final int busyCount;

  Color _timeFg(DemoStation s) {
    return switch (s.status) {
      DemoStationStatus.overtime => ArenaColors.danger,
      DemoStationStatus.ending => ArenaColors.warning,
      _ => ArenaColors.textPrimary.withValues(alpha: 0.6),
    };
  }

  String _timeLabel(DemoStation s) {
    if (s.bookedMinutes != null && s.remainingMinutes != null) {
      final rem = s.remainingMinutes!;
      if (rem < 0) return '+${DemoData.formatDuration(rem)} OVER';
      return '${DemoData.formatDuration(rem)} LEFT';
    }
    return '${DemoData.formatDuration(s.elapsedMinutes ?? 0)} OPEN';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: ArenaColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x12FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                'STILL RUNNING',
                style: LobbyFonts.display(
                  size: 12,
                  weight: FontWeight.w600,
                  letterSpacing: 12 * 0.15,
                  color: ArenaColors.textPrimary.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(height: 1, color: const Color(0x12FFFFFF)),
              ),
              const SizedBox(width: 10),
              Text(
                busyCount > 0 ? 'SETTLE BEFORE HANDOVER' : 'ALL SETTLED',
                style: LobbyFonts.mono(
                  size: 10,
                  letterSpacing: 10 * 0.08,
                  color: busyCount > 0 ? ArenaColors.warning : ArenaColors.accent,
                ),
              ),
            ],
          ),
          if (busy.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 22, bottom: 6),
              child: Text(
                'Every station is idle. Nothing left to settle.',
                style: LobbyFonts.body(
                  size: 13.5,
                  color: ArenaColors.textPrimary.withValues(alpha: 0.4),
                ),
              ),
            )
          else
            for (final s in busy)
              Container(
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0x0EFFFFFF))),
                ),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 82,
                      child: Text(
                        s.id,
                        style: LobbyFonts.display(size: 17),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        s.players.isEmpty
                            ? 'Walk-in · no member attached'
                            : s.players.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LobbyFonts.body(
                          size: 13.5,
                          weight: FontWeight.w600,
                          color: ArenaColors.textPrimary.withValues(alpha: 0.72),
                        ),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Text(
                      _timeLabel(s),
                      style: LobbyFonts.mono(size: 13, color: _timeFg(s)),
                    ),
                    const SizedBox(width: 13),
                    SizedBox(
                      width: 74,
                      child: Text(
                        DemoData.inr(s.runningAmountPaise),
                        textAlign: TextAlign.right,
                        style: LobbyFonts.mono(size: 14, weight: FontWeight.w700),
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

class _DrawerPanel extends StatelessWidget {
  const _DrawerPanel({required this.shift, required this.busyCount});

  final DemoShiftSnapshot shift;
  final int busyCount;

  @override
  Widget build(BuildContext context) {
    final canClose = busyCount == 0;
    final rows = <(String, String, Color, FontWeight, double)>[
      (
        'Cash taken',
        DemoData.inr(shift.cashPaise),
        ArenaColors.textPrimary,
        FontWeight.w500,
        14,
      ),
      (
        'UPI · verified',
        DemoData.inr(shift.upiPaise),
        ArenaColors.textPrimary.withValues(alpha: 0.6),
        FontWeight.w500,
        14,
      ),
      (
        'Opening float',
        DemoData.inr(shift.openingFloatPaise),
        ArenaColors.textPrimary.withValues(alpha: 0.6),
        FontWeight.w500,
        14,
      ),
      (
        'Card',
        DemoData.inr(shift.cardPaise),
        ArenaColors.textPrimary.withValues(alpha: 0.6),
        FontWeight.w500,
        14,
      ),
      (
        'Cash in drawer now',
        DemoData.inr(shift.expectedCashPaise),
        ArenaColors.accent,
        FontWeight.w700,
        19,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            color: ArenaColors.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x12FFFFFF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'DRAWER COUNT',
                style: LobbyFonts.display(
                  size: 12,
                  weight: FontWeight.w600,
                  letterSpacing: 12 * 0.15,
                  color: ArenaColors.textPrimary.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 11),
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          r.$1,
                          style: LobbyFonts.body(
                            size: 13.5,
                            color: ArenaColors.textPrimary.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                      Text(
                        r.$2,
                        style: LobbyFonts.mono(
                          size: r.$5,
                          weight: r.$4,
                          color: r.$3,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 11),
        LobbyButton(
          label: canClose
              ? 'CLOSE SHIFT & HAND OVER'
              : 'CANNOT CLOSE · $busyCount OPEN',
          height: 58,
          radius: 11,
          fontSize: 15,
          letterSpacingEm: 0.1,
          expanded: true,
          enabled: canClose,
          onTap: canClose ? () {} : null,
          background: canClose ? ArenaColors.accent : const Color(0x00000000),
          foreground: canClose
              ? ArenaColors.onAccent
              : ArenaColors.warning.withValues(alpha: 0.85),
          borderColor: canClose ? null : ArenaColors.warning.withValues(alpha: 0.35),
          tone: canClose ? LobbyButtonTone.primary : LobbyButtonTone.ghost,
        ),
        const SizedBox(height: 11),
        Text(
          canClose
              ? 'Locks the tablet, prints the summary and pushes the day to the owner dashboard.'
              : 'End or transfer the open sessions on the floor board, then close.',
          style: LobbyFonts.body(
            size: 12,
            color: ArenaColors.textPrimary.withValues(alpha: 0.35),
          ),
        ),
      ],
    );
  }
}
