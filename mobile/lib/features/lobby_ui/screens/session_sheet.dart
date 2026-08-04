import 'package:arena_os/app/theme/arena_colors.dart';
import 'package:arena_os/features/lobby_ui/demo_data.dart';
import 'package:arena_os/features/lobby_ui/lobby_controller.dart';
import 'package:arena_os/features/lobby_ui/lobby_fonts.dart';
import 'package:arena_os/features/lobby_ui/widgets/lobby_anims.dart';
import 'package:arena_os/features/lobby_ui/widgets/lobby_button.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _games = <(String title, String rating)>[
  ('EA FC 25', '3+ · PS5'),
  ('Call of Duty MW3', '18+ · PS5'),
  ('Tekken 8', '16+ · PS5'),
  ('GTA V', '18+ · PS5'),
];

const _durations = <(int? mins, String label)>[
  (30, '30 MIN'),
  (60, '1 HR'),
  (120, '2 HR'),
  (null, 'OPEN'),
];

/// Centered session panel — NOT a Material bottom sheet.
Future<void> showSessionSheet(
  BuildContext context,
  WidgetRef ref,
  DemoStation station, {
  SessionSheetKind kind = SessionSheetKind.session,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss session',
    barrierColor: const Color(0xBD040407),
    transitionDuration: LobbyAnims.sheetUp,
    pageBuilder: (context, animation, secondaryAnimation) {
      return _SessionSheetDialog(station: station, kind: kind);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final t = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return AnimatedBuilder(
        animation: t,
        builder: (context, _) {
          return Opacity(
            opacity: t.value,
            child: Transform.translate(
              offset: Offset(0, 22 * (1 - t.value)),
              child: child,
            ),
          );
        },
      );
    },
  ).whenComplete(() {
    ref.read(lobbyUiProvider.notifier).closeStation();
  });
}

class _SessionSheetDialog extends ConsumerStatefulWidget {
  const _SessionSheetDialog({required this.station, required this.kind});

  final DemoStation station;
  final SessionSheetKind kind;

  @override
  ConsumerState<_SessionSheetDialog> createState() => _SessionSheetDialogState();
}

class _SessionSheetDialogState extends ConsumerState<_SessionSheetDialog> {
  final _queryCtrl = TextEditingController();
  final _queryFocus = FocusNode();
  String _query = '';
  final List<String> _picked = <String>[];
  String? _game;
  int? _mins = 60;

  DemoStation get station => widget.station;
  SessionSheetKind get kind => widget.kind;
  bool get isBill => kind == SessionSheetKind.bill;

  @override
  void dispose() {
    _queryCtrl.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).pop();

  double _panelWidth(BuildContext context) {
    final maxW = MediaQuery.sizeOf(context).width - 64;
    final preferred = isBill
        ? 820.0
        : station.isBusy
            ? 920.0
            : station.status == DemoStationStatus.maintenance
                ? 560.0
                : 780.0;
    return preferred.clamp(320.0, maxW > preferred ? preferred : maxW);
  }

  String get _kicker {
    if (isBill) return 'BILL · ${station.id}';
    if (station.status == DemoStationStatus.maintenance) {
      return 'MAINTENANCE · ${station.id}';
    }
    if (station.isBusy) return 'ACTIVE SESSION · ${station.id}';
    return 'START SESSION · ${station.id}';
  }

  String get _title {
    if (isBill) {
      return station.players.map((p) => p.split(' ').first).join(' + ');
    }
    if (station.status == DemoStationStatus.maintenance) {
      return 'Station not bookable';
    }
    if (station.isBusy) {
      final names = station.players.map((p) {
        final parts = p.trim().split(RegExp(r'\s+'));
        return parts.isEmpty ? p : parts.first;
      }).join(' + ');
      final game = station.game ?? '';
      return game.isEmpty ? names : '$names on $game';
    }
    return 'Who, what, how long';
  }

  List<DemoMember> get _hits {
    final q = _query.trim().toLowerCase().replaceAll(' ', '');
    return DemoData.members.where((m) {
      if (q.isEmpty) return true;
      return m.phone.replaceAll(' ', '').toLowerCase().contains(q) ||
          m.name.toLowerCase().contains(_query.trim().toLowerCase());
    }).take(6).toList();
  }

  String get _startSummary {
    if (_picked.isEmpty || _game == null) {
      return 'Pick players and a title — target is under 10 seconds.';
    }
    final dur = _mins == null ? 'open-ended' : '$_mins min';
    return '${_picked.length} on ${station.id} · $_game · $dur';
  }

  bool get _canStart => _picked.isNotEmpty && _game != null;

  int _durationPricePaise(int? mins) {
    if (mins == null) return 0;
    final heads = station.isPerHead ? (_picked.isEmpty ? 1 : _picked.length) : 1;
    return ((mins / 60.0) * station.ratePaise * heads).round();
  }

  Color get _timerFg {
    return switch (station.status) {
      DemoStationStatus.overtime => const Color(0xFFFF6B6B),
      DemoStationStatus.ending => ArenaColors.warning,
      _ => ArenaColors.accent,
    };
  }

  Color get _timerBg {
    return switch (station.status) {
      DemoStationStatus.overtime => const Color(0x12FF4444),
      DemoStationStatus.ending => const Color(0x12FFB020),
      _ => ArenaColors.panel,
    };
  }

  Color get _timerRing {
    return switch (station.status) {
      DemoStationStatus.overtime => const Color(0x66FF4444),
      DemoStationStatus.ending => const Color(0x59FFB020),
      _ => const Color(0x12FFFFFF),
    };
  }

  String get _timerLabel {
    if (station.bookedMinutes != null) {
      final rem = station.remainingMinutes ?? 0;
      return rem < 0 ? 'OVER BOOKED TIME' : 'TIME REMAINING';
    }
    return 'ELAPSED · OPEN-ENDED';
  }

  String get _timerValue {
    if (station.bookedMinutes != null && station.remainingMinutes != null) {
      return DemoData.formatDuration(station.remainingMinutes!);
    }
    return DemoData.formatDuration(station.elapsedMinutes ?? 0);
  }

  String get _timerSub {
    if (station.bookedMinutes != null) {
      return '${station.bookedMinutes} min booked · ${station.typeLine}';
    }
    return 'Billing per 15 min';
  }

  @override
  Widget build(BuildContext context) {
    final width = _panelWidth(context);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: MediaQuery.sizeOf(context).height - 64),
        child: Container(
          width: width,
          decoration: BoxDecoration(
            color: ArenaColors.sheet,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x17FFFFFF)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0xE6000000),
                blurRadius: 80,
                offset: Offset(0, 30),
                spreadRadius: -20,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _header(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 19, 22, 22),
                  child: isBill
                      ? _billBody()
                      : station.status == DemoStationStatus.maintenance
                          ? _maintenanceBody()
                          : station.isBusy
                              ? _activeBody()
                              : _startBody(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 17, 22, 17),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x12FFFFFF))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _kicker,
                  style: LobbyFonts.mono(
                    size: 10,
                    letterSpacing: 10 * 0.14,
                    color: ArenaColors.accent,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _title,
                  style: LobbyFonts.display(size: 23, height: 1.1),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _close,
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              child: Text(
                '✕',
                style: LobbyFonts.mono(
                  size: 16,
                  color: ArenaColors.textPrimary.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _maintenanceBody() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ArenaColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x12FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'IN MAINTENANCE',
            style: LobbyFonts.mono(
              size: 10,
              letterSpacing: 10 * 0.14,
              color: ArenaColors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${station.id} is down — not bookable until marked working.',
            style: LobbyFonts.body(
              size: 15,
              color: ArenaColors.textPrimary.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Controller drift — logged · owner notified.',
            style: LobbyFonts.mono(
              size: 11,
              color: ArenaColors.textPrimary.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _startBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 640;
            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _whoCol(),
                  const SizedBox(height: 18),
                  _whatHowCol(),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: _whoCol()),
                const SizedBox(width: 18),
                Expanded(child: _whatHowCol()),
              ],
            );
          },
        ),
        const SizedBox(height: 15),
        Container(
          padding: const EdgeInsets.only(top: 16),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0x12FFFFFF))),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _startSummary,
                  style: LobbyFonts.body(
                    size: 13,
                    color: ArenaColors.textPrimary.withValues(alpha: 0.45),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              LobbyButton(
                label: 'START',
                height: 56,
                fontSize: 16,
                letterSpacingEm: 0.1,
                padding: const EdgeInsets.symmetric(horizontal: 34),
                enabled: _canStart,
                onTap: _canStart ? _close : null,
                background: _canStart ? ArenaColors.accent : const Color(0x14FFFFFF),
                foreground: _canStart
                    ? ArenaColors.onAccent
                    : ArenaColors.textPrimary.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: LobbyFonts.mono(
        size: 9.5,
        letterSpacing: 9.5 * 0.12,
        color: ArenaColors.textPrimary.withValues(alpha: 0.4),
      ),
    );
  }

  Widget _whoCol() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _sectionLabel('1 · WHO'),
        const SizedBox(height: 9),
        _SearchField(
          controller: _queryCtrl,
          focusNode: _queryFocus,
          hint: 'Phone number or name',
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 180),
          child: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                for (final m in _hits) ...<Widget>[
                  _MemberHit(
                    member: m,
                    selected: _picked.contains(m.name),
                    onTap: () {
                      setState(() {
                        if (_picked.contains(m.name)) {
                          _picked.remove(m.name);
                        } else if (_picked.length < station.seats) {
                          _picked.add(m.name);
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 5),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () {
            setState(() {
              final n = 'Walk-in ${_picked.where((p) => p.startsWith('Walk-in')).length + 1}';
              if (_picked.length < station.seats) _picked.add(n);
            });
          },
          child: Container(
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: const Color(0x1FFFFFFF)),
            ),
            child: Text(
              '+ QUICK-ADD WALK-IN · NAME + PHONE ONLY',
              style: LobbyFonts.mono(
                size: 11,
                letterSpacing: 11 * 0.08,
                color: ArenaColors.textPrimary.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: <Widget>[
            for (final name in _picked)
              Container(
                height: 38,
                padding: const EdgeInsets.only(left: 12, right: 8),
                decoration: BoxDecoration(
                  color: ArenaColors.accent.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(color: ArenaColors.accent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      name,
                      style: LobbyFonts.body(
                        size: 13,
                        weight: FontWeight.w600,
                        color: ArenaColors.accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setState(() => _picked.remove(name)),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: Center(
                          child: Text(
                            '✕',
                            style: LobbyFonts.mono(
                              size: 11,
                              color: ArenaColors.accent.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _whatHowCol() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _sectionLabel('2 · WHAT · INSTALLED ON ${station.id}'),
        const SizedBox(height: 9),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.2,
          children: <Widget>[
            for (final g in _games)
              _SelectTile(
                title: g.$1,
                sub: g.$2,
                selected: _game == g.$1,
                onTap: () => setState(() => _game = g.$1),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Age ratings come from the member date of birth on file.',
          style: LobbyFonts.body(
            size: 11.5,
            color: ArenaColors.textPrimary.withValues(alpha: 0.32),
          ),
        ),
        const SizedBox(height: 15),
        _sectionLabel('3 · HOW LONG'),
        const SizedBox(height: 9),
        Row(
          children: <Widget>[
            for (var i = 0; i < _durations.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _DurationTile(
                  label: _durations[i].$2,
                  price: _durations[i].$1 == null
                      ? 'per 15 min'
                      : DemoData.inr(_durationPricePaise(_durations[i].$1)),
                  selected: _mins == _durations[i].$1,
                  onTap: () => setState(() => _mins = _durations[i].$1),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _activeBody() {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 700;
        final left = _activeLeft();
        final right = _activeRight();
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[left, const SizedBox(height: 20), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(width: 300, child: left),
            const SizedBox(width: 20),
            Expanded(child: right),
          ],
        );
      },
    );
  }

  Widget _activeLeft() {
    final playLine = station.bookedMinutes != null
        ? '${station.bookedMinutes} min booked'
        : 'Open time so far';
    return Column(
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _timerBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _timerRing),
          ),
          child: Column(
            children: <Widget>[
              Text(
                _timerLabel,
                style: LobbyFonts.mono(
                  size: 9.5,
                  letterSpacing: 9.5 * 0.14,
                  color: _timerFg == ArenaColors.accent
                      ? ArenaColors.textPrimary.withValues(alpha: 0.4)
                      : _timerFg,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _timerValue,
                style: LobbyFonts.mono(
                  size: 60,
                  weight: FontWeight.w700,
                  height: 1,
                  color: _timerFg,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _timerSub,
                textAlign: TextAlign.center,
                style: LobbyFonts.body(
                  size: 12.5,
                  color: ArenaColors.textPrimary.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
          decoration: BoxDecoration(
            color: ArenaColors.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x12FFFFFF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _sectionLabel('RUNNING BILL'),
              const SizedBox(height: 8),
              _billLine(playLine, DemoData.inr(station.runningAmountPaise)),
              const SizedBox(height: 8),
              _billLine('Snacks on the tab', '—'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.only(top: 8),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0x17FFFFFF))),
                ),
                child: Row(
                  children: <Widget>[
                    Text(
                      'SO FAR',
                      style: LobbyFonts.mono(
                        size: 10,
                        letterSpacing: 10 * 0.1,
                        color: ArenaColors.textPrimary.withValues(alpha: 0.45),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      DemoData.inr(station.runningAmountPaise),
                      style: LobbyFonts.mono(
                        size: 24,
                        weight: FontWeight.w700,
                        color: ArenaColors.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _billLine(String k, String v) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            k,
            style: LobbyFonts.body(
              size: 12.5,
              color: ArenaColors.textPrimary.withValues(alpha: 0.55),
            ),
          ),
        ),
        Text(v, style: LobbyFonts.mono(size: 13)),
      ],
    );
  }

  Widget _activeRight() {
    final seatsLabel =
        '${station.players.length} of ${station.seats} seats · rate ${station.isPerHead ? 'per head' : 'per station'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _sectionLabel('PLAYERS · $seatsLabel'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final p in station.players) _playerChip(p),
            _pillButton('+ ADD PLAYER', accent: true),
          ],
        ),
        const SizedBox(height: 15),
        Row(
          children: <Widget>[
            _sectionLabel('TAB · SNACKS ON THIS SESSION'),
            const Spacer(),
            Text(
              DemoData.inr(0),
              style: LobbyFonts.mono(
                size: 13,
                weight: FontWeight.w700,
                color: ArenaColors.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[_pillButton('+ ADD SNACKS', accent: true)],
        ),
        const SizedBox(height: 15),
        Row(
          children: <Widget>[
            _sectionLabel('TITLES PLAYED · TAP TO ADD ANOTHER'),
            if (station.game != null) ...<Widget>[
              const SizedBox(width: 9),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: ArenaColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  station.game!,
                  style: LobbyFonts.mono(
                    size: 9.5,
                    letterSpacing: 9.5 * 0.06,
                    color: ArenaColors.accent,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.1,
          children: <Widget>[
            for (final g in _games)
              _SelectTile(
                title: g.$1,
                sub: g.$2.split(' · ').first,
                selected: station.game == g.$1,
                onTap: () {},
              ),
          ],
        ),
        const SizedBox(height: 15),
        _sectionLabel('EXTEND'),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            for (final label in <String>['+15 MIN', '+30 MIN', '+1 HR']) ...<Widget>[
              Expanded(
                child: GestureDetector(
                  onTap: () {},
                  child: Container(
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0x0DFFFFFF),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: const Color(0x1CFFFFFF)),
                    ),
                    child: Text(
                      label,
                      style: LobbyFonts.display(
                        size: 13.5,
                        weight: FontWeight.w600,
                        letterSpacing: 13.5 * 0.06,
                        color: ArenaColors.textPrimary.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ),
              ),
              if (label != '+1 HR') const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 15),
        Container(
          padding: const EdgeInsets.only(top: 14),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0x12FFFFFF))),
          ),
          child: Row(
            children: <Widget>[
              LobbyButton(
                label: '+ SNACKS',
                height: 52,
                tone: LobbyButtonTone.ghost,
                fontSize: 12.5,
                letterSpacingEm: 0.08,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                radius: 9,
                onTap: () {},
              ),
              const SizedBox(width: 8),
              LobbyButton(
                label: 'SWAP STATION',
                height: 52,
                tone: LobbyButtonTone.ghost,
                fontSize: 12.5,
                letterSpacingEm: 0.08,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                radius: 9,
                onTap: () {},
              ),
              const Spacer(),
              LobbyButton(
                label: 'END AND BILL',
                height: 52,
                fontSize: 14,
                letterSpacingEm: 0.09,
                padding: const EdgeInsets.symmetric(horizontal: 26),
                radius: 9,
                onTap: () {
                  Navigator.of(context).pop();
                  ref.read(lobbyUiProvider.notifier).openStation(
                        station.id,
                        kind: SessionSheetKind.bill,
                      );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _billBody() {
    final prefs = ref.watch(lobbyUiProvider.select((s) => s.billPrefs));
    final ctrl = ref.read(lobbyUiProvider.notifier);
    final math = DemoData.billMath(station, coins: prefs.coins, gst: prefs.gst);
    final coinActive = math.coinCutPaise > 0;
    final gstActive = prefs.gst;

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 640;
        final linesCol = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final line in math.lines) _billSheetLine(line),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                _billToggle(
                  label: coinActive
                      ? 'COINS APPLIED · ${DemoData.inr(math.coinCutPaise)}'
                      : 'REDEEM COINS',
                  active: coinActive,
                  activeColor: ArenaColors.warning,
                  onTap: ctrl.toggleBillCoins,
                ),
                const SizedBox(width: 8),
                _billToggle(
                  label: gstActive ? 'GST INVOICE ✓' : 'GST INVOICE',
                  active: gstActive,
                  activeColor: ArenaColors.accent,
                  onTap: ctrl.toggleBillGst,
                ),
              ],
            ),
          ],
        );

        final totalsCol = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
              decoration: BoxDecoration(
                color: const Color(0x0AFFFFFF),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: const Color(0x14FFFFFF)),
              ),
              child: Column(
                children: <Widget>[
                  _billTotalRow('Subtotal', DemoData.inr(math.subPaise)),
                  const SizedBox(height: 8),
                  _billTotalRow(
                    math.member != null
                        ? 'Coins · ${math.member!.name.split(' ').first} has ${math.member!.coins}'
                        : 'Coins · walk-in',
                    coinActive ? '−${DemoData.inr(math.coinCutPaise)}' : '—',
                    valueColor: coinActive ? ArenaColors.warning : null,
                    muted: !coinActive,
                  ),
                  const SizedBox(height: 8),
                  _billTotalRow(
                    'GST 18%${gstActive ? ' · tax invoice' : ' · not applied'}',
                    gstActive ? DemoData.inr(math.gstPaise) : '—',
                    muted: !gstActive,
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 9),
                    padding: const EdgeInsets.only(top: 9),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: Color(0x1AFFFFFF))),
                    ),
                    child: Row(
                      children: <Widget>[
                        Text(
                          'TOTAL',
                          style: LobbyFonts.mono(
                            size: 10,
                            letterSpacing: 10 * 0.12,
                            color: ArenaColors.textPrimary.withValues(alpha: 0.45),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          DemoData.inr(math.totalPaise),
                          style: LobbyFonts.mono(
                            size: 29,
                            weight: FontWeight.w700,
                            height: 1,
                            color: ArenaColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 13),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.4,
              children: <Widget>[
                for (final p in const <(String, String)>[
                  ('cash', 'CASH'),
                  ('upi', 'UPI'),
                  ('split', 'SPLIT'),
                  ('later', 'PAY LATER'),
                ])
                  _payOption(
                    label: p.$2,
                    selected: prefs.pay == p.$1,
                    onTap: () => ctrl.setBillPay(p.$1),
                  ),
              ],
            ),
            const SizedBox(height: 13),
            LobbyButton(
              label: 'TAKE PAYMENT & PRINT',
              height: 58,
              fontSize: 15.5,
              letterSpacingEm: 0.1,
              radius: 10,
              expanded: true,
              onTap: () {
                ctrl.confirmBill();
                _close();
              },
            ),
            const SizedBox(height: 8),
            Text(
              gstActive
                  ? 'GST invoice · series INV/26-27 · thermal 58mm'
                  : 'Thermal receipt 58mm · works offline, syncs later',
              textAlign: TextAlign.center,
              style: LobbyFonts.body(
                size: 11.5,
                color: ArenaColors.textPrimary.withValues(alpha: 0.34),
              ),
            ),
          ],
        );

        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[linesCol, const SizedBox(height: 18), totalsCol],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: linesCol),
            const SizedBox(width: 18),
            SizedBox(width: 300, child: totalsCol),
          ],
        );
      },
    );
  }

  Widget _billSheetLine(DemoBillLine line) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x0EFFFFFF))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  line.name,
                  style: LobbyFonts.body(size: 14, weight: FontWeight.w600),
                ),
                Text(
                  line.detail,
                  style: LobbyFonts.mono(
                    size: 10.5,
                    color: ArenaColors.textPrimary.withValues(alpha: 0.35),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 92,
            child: Text(
              line.qty,
              textAlign: TextAlign.right,
              style: LobbyFonts.mono(
                size: 12,
                color: ArenaColors.textPrimary.withValues(alpha: 0.45),
              ),
            ),
          ),
          SizedBox(
            width: 96,
            child: Text(
              DemoData.inr(line.amountPaise),
              textAlign: TextAlign.right,
              style: LobbyFonts.mono(
                size: 14.5,
                weight: FontWeight.w500,
                color: line.warn ? const Color(0xFFFF6B6B) : ArenaColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _billTotalRow(
    String k,
    String v, {
    Color? valueColor,
    bool muted = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Expanded(
          child: Text(
            k,
            style: LobbyFonts.body(
              size: 12.5,
              color: ArenaColors.textPrimary.withValues(alpha: 0.5),
            ),
          ),
        ),
        Text(
          v,
          style: LobbyFonts.mono(
            size: 13.5,
            weight: FontWeight.w500,
            color: valueColor ??
                (muted
                    ? ArenaColors.textPrimary.withValues(alpha: 0.35)
                    : ArenaColors.textPrimary),
          ),
        ),
      ],
    );
  }

  Widget _billToggle({
    required String label,
    required bool active,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: active ? activeColor.withValues(alpha: activeColor == ArenaColors.warning ? 0.13 : 0.12) : null,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active
                  ? activeColor.withValues(alpha: 0.32)
                  : const Color(0x1FFFFFFF),
            ),
          ),
          child: Text(
            label,
            style: LobbyFonts.mono(
              size: 11,
              letterSpacing: 11 * 0.07,
              color: active
                  ? activeColor
                  : ArenaColors.textPrimary.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }

  Widget _payOption({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? ArenaColors.accent.withValues(alpha: 0.12) : const Color(0x0AFFFFFF),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? ArenaColors.accent.withValues(alpha: 0.35) : const Color(0x1AFFFFFF),
          ),
        ),
        child: Text(
          label,
          style: LobbyFonts.display(
            size: 13,
            weight: FontWeight.w600,
            letterSpacing: 13 * 0.07,
            color: selected ? ArenaColors.accent : ArenaColors.textPrimary.withValues(alpha: 0.72),
          ),
        ),
      ),
    );
  }

  Widget _playerChip(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final initials = parts.length >= 2
        ? (parts.first[0] + parts.last[0]).toUpperCase()
        : name.substring(0, 1).toUpperCase();
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 10, right: 8),
      decoration: BoxDecoration(
        color: const Color(0x0DFFFFFF),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ArenaColors.accent.withValues(alpha: 0.14),
            ),
            child: Text(
              initials,
              style: LobbyFonts.mono(
                size: 10,
                weight: FontWeight.w700,
                color: ArenaColors.accent,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Text(name, style: LobbyFonts.body(size: 13.5, weight: FontWeight.w600)),
          const SizedBox(width: 6),
          Text(
            '✕',
            style: LobbyFonts.mono(
              size: 11,
              color: ArenaColors.textPrimary.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pillButton(String label, {bool accent = false}) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: accent
                ? ArenaColors.accent.withValues(alpha: 0.28)
                : const Color(0x1AFFFFFF),
          ),
        ),
        child: Text(
          label,
          style: LobbyFonts.mono(
            size: 11,
            letterSpacing: 11 * 0.07,
            color: accent ? ArenaColors.accent : ArenaColors.textPrimary.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[focusNode, controller]),
      builder: (context, _) {
        final focused = focusNode.hasFocus;
        final empty = controller.text.isEmpty;
        return Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: const Color(0x0DFFFFFF),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: focused
                  ? ArenaColors.accent.withValues(alpha: 0.45)
                  : const Color(0x1AFFFFFF),
            ),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: <Widget>[
              if (empty)
                Text(
                  hint,
                  style: LobbyFonts.mono(
                    size: 15,
                    color: ArenaColors.textPrimary.withValues(alpha: 0.35),
                  ),
                ),
              EditableText(
                controller: controller,
                focusNode: focusNode,
                style: LobbyFonts.mono(size: 15),
                cursorColor: ArenaColors.accent,
                backgroundCursorColor: ArenaColors.accent,
                onChanged: onChanged,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MemberHit extends StatelessWidget {
  const _MemberHit({
    required this.member,
    required this.selected,
    required this.onTap,
  });

  final DemoMember member;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? ArenaColors.accent.withValues(alpha: 0.1)
              : const Color(0x09FFFFFF),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected
                ? ArenaColors.accent.withValues(alpha: 0.3)
                : const Color(0x14FFFFFF),
          ),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ArenaColors.accent.withValues(alpha: 0.14),
              ),
              child: Text(
                member.initials,
                style: LobbyFonts.mono(
                  size: 11,
                  weight: FontWeight.w700,
                  color: ArenaColors.accent,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    member.name,
                    style: LobbyFonts.body(size: 14, weight: FontWeight.w600),
                  ),
                  Text(
                    '${member.phone} · ${member.coins} coins',
                    style: LobbyFonts.mono(
                      size: 10.5,
                      color: ArenaColors.textPrimary.withValues(alpha: 0.38),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: member.plan == 'WALK-IN'
                    ? const Color(0x0EFFFFFF)
                    : ArenaColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                member.plan,
                style: LobbyFonts.mono(
                  size: 10,
                  letterSpacing: 10 * 0.06,
                  color: member.plan == 'WALK-IN'
                      ? ArenaColors.textPrimary.withValues(alpha: 0.55)
                      : ArenaColors.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectTile extends StatelessWidget {
  const _SelectTile({
    required this.title,
    required this.sub,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected
              ? ArenaColors.accent.withValues(alpha: 0.12)
              : const Color(0x0AFFFFFF),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected
                ? ArenaColors.accent.withValues(alpha: 0.35)
                : const Color(0x17FFFFFF),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LobbyFonts.display(
                size: 13.5,
                weight: FontWeight.w600,
                color: selected ? ArenaColors.accent : ArenaColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              style: LobbyFonts.mono(
                size: 9.5,
                letterSpacing: 9.5 * 0.05,
                color: selected
                    ? ArenaColors.accent.withValues(alpha: 0.7)
                    : ArenaColors.textPrimary.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DurationTile extends StatelessWidget {
  const _DurationTile({
    required this.label,
    required this.price,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String price;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
        decoration: BoxDecoration(
          color: selected
              ? ArenaColors.accent.withValues(alpha: 0.12)
              : const Color(0x0AFFFFFF),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected
                ? ArenaColors.accent.withValues(alpha: 0.35)
                : const Color(0x17FFFFFF),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              label,
              style: LobbyFonts.display(
                size: 14,
                color: selected ? ArenaColors.accent : ArenaColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              price,
              style: LobbyFonts.mono(
                size: 10,
                color: selected
                    ? ArenaColors.accent.withValues(alpha: 0.7)
                    : ArenaColors.textPrimary.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
