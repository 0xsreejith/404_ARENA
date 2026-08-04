import 'package:arena_os/app/theme/arena_colors.dart';
import 'package:arena_os/features/lobby_ui/demo_data.dart';
import 'package:arena_os/features/lobby_ui/lobby_controller.dart';
import 'package:arena_os/features/lobby_ui/lobby_fonts.dart';
import 'package:arena_os/features/lobby_ui/widgets/station_card.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Floor board — zone pills, 3-col station grid, legend.
/// Titles / stats live in [StaffShell] header only.
class FloorScreen extends ConsumerWidget {
  const FloorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stations = DemoData.stations;

    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _ZoneRow(stations: stations),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.crossAxisExtent;
              final cross = width >= 720
                  ? 3
                  : width >= 420
                  ? 2
                  : 1;
              return SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cross,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  mainAxisExtent: 206,
                ),
                delegate: SliverChildBuilderDelegate((context, i) {
                  final s = stations[i];
                  return StationCard(
                    station: s.toLiveStationCardData(),
                    onTap: () =>
                        ref.read(lobbyUiProvider.notifier).openStation(s.id),
                  );
                }, childCount: stations.length),
              );
            },
          ),
        ),
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(22, 0, 22, 22),
          sliver: SliverToBoxAdapter(child: _LegendRow()),
        ),
      ],
    );
  }
}

extension on DemoStation {
  LiveStationCardData toLiveStationCardData() {
    final isFixed = bookedMinutes != null && remainingMinutes != null;
    final remaining = remainingMinutes ?? 0;
    final booked = bookedMinutes ?? 1;
    final elapsed = elapsedMinutes ?? 0;
    final status = switch (this.status) {
      DemoStationStatus.idle => LiveStationCardStatus.idle,
      DemoStationStatus.live => LiveStationCardStatus.live,
      DemoStationStatus.ending => LiveStationCardStatus.ending,
      DemoStationStatus.overtime => LiveStationCardStatus.overtime,
      DemoStationStatus.maintenance => LiveStationCardStatus.maintenance,
      DemoStationStatus.paused => LiveStationCardStatus.paused,
    };

    return LiveStationCardData(
      id: id,
      typeLine: typeLine,
      seats: seats,
      status: status,
      players: players,
      gameName: game,
      timerText: isFixed
          ? DemoData.formatDuration(remaining)
          : DemoData.formatDuration(elapsed),
      timerLabel: isFixed
          ? (remaining < 0 ? 'OVER BOOKED TIME' : 'REMAINING')
          : 'ELAPSED · OPEN-ENDED',
      progressFraction: isFixed
          ? (1 - (remaining / booked)).clamp(0.0, 1.0)
          : (elapsed / 60).clamp(0.0, 1.0),
      rateText: '${DemoData.inr(ratePaise)}/hr${isPerHead ? ' per head' : ''}',
      amountLabel: 'RUNNING',
      amountText: DemoData.inr(runningAmountPaise),
    );
  }
}

class _ZoneRow extends StatelessWidget {
  const _ZoneRow({required this.stations});

  final List<DemoStation> stations;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (final zone in DemoData.zoneOrder) ...<Widget>[
          _ZonePill(
            name: zone,
            count: stations.where((s) => s.zone == zone).length,
          ),
          const SizedBox(width: 9),
        ],
        Expanded(
          child: Container(
            height: 1,
            color: const Color(0xFFFFFFFF).withValues(alpha: 0.07),
          ),
        ),
        const SizedBox(width: 9),
        Text(
          'TAP IDLE → START · TAP LIVE → SESSION',
          style: LobbyFonts.mono(
            size: 9.5,
            letterSpacing: 9.5 * 0.1,
            color: ArenaColors.textPrimary.withValues(alpha: 0.3),
          ),
        ),
      ],
    );
  }
}

class _ZonePill extends StatelessWidget {
  const _ZonePill({required this.name, required this.count});

  final String name;
  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count == 1 ? '1 STATION' : '$count STATIONS';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF).withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFFFFFF).withValues(alpha: 0.09),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            name,
            style: LobbyFonts.display(
              size: 11.5,
              weight: FontWeight.w600,
              letterSpacing: 11.5 * 0.13,
              color: ArenaColors.textPrimary.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: LobbyFonts.mono(
              size: 10,
              color: ArenaColors.textPrimary.withValues(alpha: 0.38),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow();

  static const _items = <(String, Color)>[
    ('IDLE', ArenaColors.grey),
    ('LIVE', ArenaColors.accent),
    ('LAST 5 MIN', ArenaColors.warning),
    ('OVER TIME', ArenaColors.danger),
    ('MAINTENANCE', Color(0x33FFFFFF)),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: const Color(0xFFFFFFFF).withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Wrap(
        spacing: 15,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'CARD STATES',
              style: LobbyFonts.mono(
                size: 9.5,
                letterSpacing: 9.5 * 0.12,
                color: ArenaColors.textPrimary.withValues(alpha: 0.3),
              ),
            ),
          ),
          for (final item in _items)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: item.$2,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    item.$1,
                    style: LobbyFonts.mono(
                      size: 9.5,
                      letterSpacing: 9.5 * 0.07,
                      color: ArenaColors.textPrimary.withValues(alpha: 0.4),
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
