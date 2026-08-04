import 'package:arena_os/app/theme/arena_colors.dart';
import 'package:arena_os/features/lobby_ui/demo_data.dart';
import 'package:arena_os/features/lobby_ui/lobby_controller.dart';
import 'package:arena_os/features/lobby_ui/lobby_fonts.dart';
import 'package:arena_os/features/lobby_ui/widgets/lobby_button.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _MemberFilter { all, walkIn, members, blocked }

/// S7 Members list + S8 profile — shell owns the page title.
class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen({super.key});

  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends ConsumerState<MembersScreen> {
  _MemberFilter _filter = _MemberFilter.all;
  String _profileTab = 'visits';
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<DemoMember> _filtered(String query) {
    final q = query.trim().toLowerCase().replaceAll(' ', '');
    return DemoData.members.where((m) {
      switch (_filter) {
        case _MemberFilter.all:
          break;
        case _MemberFilter.walkIn:
          if (m.plan != 'WALK-IN') return false;
        case _MemberFilter.members:
          if (m.plan == 'WALK-IN') return false;
        case _MemberFilter.blocked:
          return false;
      }
      if (q.isEmpty) return true;
      return m.phone.replaceAll(' ', '').toLowerCase().contains(q) ||
          m.name.toLowerCase().contains(query.trim().toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lobbyUiProvider);
    final ctrl = ref.read(lobbyUiProvider.notifier);

    DemoMember? selected;
    final selectedId = state.selectedMemberId;
    if (selectedId != null) {
      for (final m in DemoData.members) {
        if (m.id == selectedId) {
          selected = m;
          break;
        }
      }
    }

    if (selected != null) {
      return _MemberProfile(
        member: selected,
        tab: _profileTab,
        onTab: (t) => setState(() => _profileTab = t),
        onBack: () {
          setState(() => _profileTab = 'visits');
          ctrl.closeMember();
        },
      );
    }

    final members = _filtered(state.memberQuery);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _MonoSearchField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  hint: 'Search by phone number — 98470 — or name',
                  onChanged: ctrl.setMemberQuery,
                ),
              ),
              const SizedBox(width: 10),
              LobbyButton(
                label: '+ ADD MEMBER',
                height: 52,
                fontSize: 13.5,
                letterSpacingEm: 0.09,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: <Widget>[
              _FilterPill(
                label: 'ALL · ${DemoData.members.length}',
                selected: _filter == _MemberFilter.all,
                onTap: () => setState(() => _filter = _MemberFilter.all),
              ),
              _FilterPill(
                label: 'WALK-IN',
                selected: _filter == _MemberFilter.walkIn,
                onTap: () => setState(() => _filter = _MemberFilter.walkIn),
              ),
              _FilterPill(
                label: 'MEMBERS',
                selected: _filter == _MemberFilter.members,
                onTap: () => setState(() => _filter = _MemberFilter.members),
              ),
              _FilterPill(
                label: 'BLOCKED',
                selected: _filter == _MemberFilter.blocked,
                onTap: () => setState(() => _filter = _MemberFilter.blocked),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: const Color(0x12FFFFFF)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: <Widget>[
                  Container(
                    color: ArenaColors.panel,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: const _MemberHeaderRow(),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: members.length,
                      itemBuilder: (context, i) {
                        final m = members[i];
                        return _MemberRow(
                          member: m,
                          onTap: () => ctrl.openMember(m.id),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonoSearchField extends StatelessWidget {
  const _MonoSearchField({
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
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: const Color(0x0DFFFFFF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: focused
                  ? ArenaColors.accent
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
                    size: 13,
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

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? ArenaColors.accent.withValues(alpha: 0.13)
              : const Color(0x0AFFFFFF),
          borderRadius: BorderRadius.circular(19),
          border: Border.all(
            color: selected
                ? ArenaColors.accent.withValues(alpha: 0.32)
                : const Color(0x17FFFFFF),
          ),
        ),
        child: Text(
          label,
          style: LobbyFonts.mono(
            size: 10.5,
            letterSpacing: 10.5 * 0.08,
            color: selected
                ? ArenaColors.accent
                : ArenaColors.textPrimary.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

class _MemberHeaderRow extends StatelessWidget {
  const _MemberHeaderRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 154,
          child: Text(
            'PHONE',
            style: LobbyFonts.mono(
              size: 9.5,
              letterSpacing: 9.5 * 0.11,
              color: ArenaColors.textPrimary.withValues(alpha: 0.38),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 14,
          child: Text(
            'MEMBER',
            style: LobbyFonts.mono(
              size: 9.5,
              letterSpacing: 9.5 * 0.11,
              color: ArenaColors.textPrimary.withValues(alpha: 0.38),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 148,
          child: Text(
            'MEMBERSHIP',
            style: LobbyFonts.mono(
              size: 9.5,
              letterSpacing: 9.5 * 0.11,
              color: ArenaColors.textPrimary.withValues(alpha: 0.38),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 92,
          child: Text(
            'VISITS',
            style: LobbyFonts.mono(
              size: 9.5,
              letterSpacing: 9.5 * 0.11,
              color: ArenaColors.textPrimary.withValues(alpha: 0.38),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 100,
          child: Text(
            'SPEND',
            style: LobbyFonts.mono(
              size: 9.5,
              letterSpacing: 9.5 * 0.11,
              color: ArenaColors.textPrimary.withValues(alpha: 0.38),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 84,
          child: Text(
            'COINS',
            style: LobbyFonts.mono(
              size: 9.5,
              letterSpacing: 9.5 * 0.11,
              color: ArenaColors.textPrimary.withValues(alpha: 0.38),
            ),
          ),
        ),
      ],
    );
  }
}

class _MemberRow extends StatefulWidget {
  const _MemberRow({required this.member, required this.onTap});

  final DemoMember member;
  final VoidCallback onTap;

  @override
  State<_MemberRow> createState() => _MemberRowState();
}

class _MemberRowState extends State<_MemberRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final walkIn = m.plan == 'WALK-IN';
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: _hover
                ? ArenaColors.accent.withValues(alpha: 0.05)
                : const Color(0xFF0D0E13),
            border: const Border(
              top: BorderSide(color: Color(0x0EFFFFFF)),
            ),
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 154,
                child: Text(
                  m.phone,
                  style: LobbyFonts.mono(size: 13, weight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 14,
                child: Row(
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
                        m.initials,
                        style: LobbyFonts.mono(
                          size: 10.5,
                          weight: FontWeight.w700,
                          color: ArenaColors.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            m.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: LobbyFonts.body(size: 14, weight: FontWeight.w600),
                          ),
                          Text(
                            walkIn ? 'No membership' : 'Joined ${m.joined}',
                            style: LobbyFonts.body(
                              size: 11,
                              color: ArenaColors.textPrimary.withValues(alpha: 0.34),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 148,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: walkIn
                          ? const Color(0x0EFFFFFF)
                          : ArenaColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      m.plan,
                      style: LobbyFonts.mono(
                        size: 10,
                        letterSpacing: 10 * 0.06,
                        color: walkIn
                            ? ArenaColors.textPrimary.withValues(alpha: 0.6)
                            : ArenaColors.accent,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 92,
                child: Text(
                  '${m.visits}',
                  style: LobbyFonts.mono(
                    size: 12.5,
                    color: ArenaColors.textPrimary.withValues(alpha: 0.6),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 100,
                child: Text(
                  DemoData.inr(m.spendPaise),
                  style: LobbyFonts.mono(
                    size: 12.5,
                    color: ArenaColors.textPrimary.withValues(alpha: 0.6),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 84,
                child: Text(
                  '${m.coins}',
                  style: LobbyFonts.mono(
                    size: 12.5,
                    weight: FontWeight.w500,
                    color: ArenaColors.warning,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberProfile extends StatelessWidget {
  const _MemberProfile({
    required this.member,
    required this.tab,
    required this.onTab,
    required this.onBack,
  });

  final DemoMember member;
  final String tab;
  final ValueChanged<String> onTab;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final walkIn = member.plan == 'WALK-IN';
    // HTML treats coin units as ₹½ each via `inr(M.coins / 2)`.
    final redeemable = DemoData.inr((member.coins / 2 * 100).round());

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          GestureDetector(
            onTap: onBack,
            child: Text(
              '← MEMBERS',
              style: LobbyFonts.mono(
                size: 10.5,
                letterSpacing: 10.5 * 0.09,
                color: ArenaColors.textPrimary.withValues(alpha: 0.45),
              ),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 720;
              final main = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(17),
                    decoration: BoxDecoration(
                      color: ArenaColors.panel,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0x12FFFFFF)),
                    ),
                    child: Row(
                      children: <Widget>[
                        CustomPaint(
                          foregroundPainter: _DashedRRectPainter(
                            color: const Color(0x29FFFFFF),
                            radius: 12,
                            strokeWidth: 1.5,
                          ),
                          child: SizedBox(
                            width: 76,
                            height: 76,
                            child: Center(
                              child: Text(
                                member.initials,
                                style: LobbyFonts.mono(
                                  size: 21,
                                  weight: FontWeight.w700,
                                  color: ArenaColors.textPrimary.withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                member.name,
                                style: LobbyFonts.display(size: 27, height: 1.05),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                member.phone,
                                style: LobbyFonts.mono(
                                  size: 13,
                                  color: ArenaColors.textPrimary.withValues(alpha: 0.55),
                                ),
                              ),
                              const SizedBox(height: 7),
                              Wrap(
                                spacing: 7,
                                runSpacing: 7,
                                children: <Widget>[
                                  _chip(
                                    walkIn ? 'NO MEMBERSHIP' : member.plan,
                                    walkIn
                                        ? const Color(0x0EFFFFFF)
                                        : ArenaColors.accent.withValues(alpha: 0.12),
                                    walkIn
                                        ? ArenaColors.textPrimary.withValues(alpha: 0.6)
                                        : ArenaColors.accent,
                                  ),
                                  _chip(
                                    'JOINED ${member.joined}'.toUpperCase(),
                                    const Color(0x0EFFFFFF),
                                    ArenaColors.textPrimary.withValues(alpha: 0.6),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: <Widget>[
                            Text(
                              'COIN BALANCE',
                              style: LobbyFonts.mono(
                                size: 9,
                                letterSpacing: 9 * 0.11,
                                color: ArenaColors.textPrimary.withValues(alpha: 0.34),
                              ),
                            ),
                            Text(
                              '${member.coins}',
                              style: LobbyFonts.mono(
                                size: 28,
                                weight: FontWeight.w700,
                                height: 1,
                                color: ArenaColors.warning,
                              ),
                            ),
                            Text(
                              '≈ $redeemable redeemable',
                              style: LobbyFonts.body(
                                size: 11,
                                color: ArenaColors.textPrimary.withValues(alpha: 0.32),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 13),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: <Widget>[
                      for (final t in <(String, String)>[
                        ('visits', 'VISIT HISTORY'),
                        ('spend', 'SPEND'),
                        ('games', 'MOST PLAYED'),
                      ])
                        _ProfileTab(
                          label: t.$2,
                          selected: tab == t.$1,
                          onTap: () => onTab(t.$1),
                        ),
                    ],
                  ),
                  const SizedBox(height: 13),
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                    decoration: BoxDecoration(
                      color: ArenaColors.panel,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0x12FFFFFF)),
                    ),
                    child: Column(
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            for (final h in _tabHeaders(tab)) ...<Widget>[
                              Expanded(
                                child: Text(
                                  h,
                                  style: LobbyFonts.mono(
                                    size: 9.5,
                                    letterSpacing: 9.5 * 0.11,
                                    color: ArenaColors.textPrimary.withValues(alpha: 0.38),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        ..._tabRows(tab, member),
                      ],
                    ),
                  ),
                ],
              );

              final side = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  LobbyButton(
                    label: 'START SESSION',
                    height: 52,
                    fontSize: 13.5,
                    letterSpacingEm: 0.09,
                    expanded: true,
                    onTap: () {},
                  ),
                  const SizedBox(height: 11),
                  LobbyButton(
                    label: 'RENEW MEMBERSHIP',
                    height: 48,
                    tone: LobbyButtonTone.ghost,
                    fontSize: 12.5,
                    letterSpacingEm: 0.09,
                    radius: 9,
                    expanded: true,
                    onTap: () {},
                  ),
                  const SizedBox(height: 11),
                  LobbyButton(
                    label: 'ADJUST COINS',
                    height: 48,
                    tone: LobbyButtonTone.ghost,
                    fontSize: 12.5,
                    letterSpacingEm: 0.09,
                    radius: 9,
                    expanded: true,
                    onTap: () {},
                  ),
                  const SizedBox(height: 11),
                  LobbyButton(
                    label: 'BLOCK MEMBER',
                    height: 48,
                    tone: LobbyButtonTone.danger,
                    fontSize: 12.5,
                    letterSpacingEm: 0.09,
                    radius: 9,
                    expanded: true,
                    onTap: () {},
                  ),
                  const SizedBox(height: 11),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
                    decoration: BoxDecoration(
                      color: ArenaColors.panel,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0x12FFFFFF)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'ID ON FILE',
                          style: LobbyFonts.display(
                            size: 11.5,
                            weight: FontWeight.w600,
                            letterSpacing: 11.5 * 0.14,
                            color: ArenaColors.textPrimary.withValues(alpha: 0.55),
                          ),
                        ),
                        const SizedBox(height: 9),
                        _idFact('Visits', '${member.visits}'),
                        _idFact('Lifetime spend', DemoData.inr(member.spendPaise)),
                        _idFact('Joined', member.joined),
                        const SizedBox(height: 6),
                        Text(
                          'No ID image or full number is stored — last 4 digits only, with recorded consent.',
                          style: LobbyFonts.body(
                            size: 11,
                            height: 1.45,
                            color: ArenaColors.textPrimary.withValues(alpha: 0.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );

              if (!wide) {
                return Column(
                  children: <Widget>[main, const SizedBox(height: 15), side],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: main),
                  const SizedBox(width: 15),
                  SizedBox(width: 262, child: side),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  List<String> _tabHeaders(String t) {
    return switch (t) {
      'spend' => <String>['PERIOD', 'SESSIONS', 'AMOUNT', 'AVG'],
      'games' => <String>['TITLE', 'PLAYS', 'HOURS', 'LAST'],
      _ => <String>['DATE', 'STATION', 'TITLE', 'AMOUNT'],
    };
  }

  List<Widget> _tabRows(String t, DemoMember m) {
    final rows = switch (t) {
      'spend' => <List<String>>[
          <String>['This month', '8', DemoData.inr(m.spendPaise ~/ 6), DemoData.inr(m.spendPaise ~/ 48)],
          <String>['Last 90 days', '22', DemoData.inr(m.spendPaise ~/ 2), DemoData.inr(m.spendPaise ~/ 44)],
        ],
      'games' => <List<String>>[
          <String>['EA FC 25', '12', '18 h', '2d ago'],
          <String>['Tekken 8', '5', '6 h', '1w ago'],
        ],
      _ => <List<String>>[
          for (final s in DemoData.stations.take(4))
            <String>[
              '26 Jul',
              s.id,
              s.game ?? 'Open play',
              DemoData.inr(s.ratePaise),
            ],
        ],
    };
    return <Widget>[
      for (final r in rows)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0x0EFFFFFF))),
          ),
          child: Row(
            children: <Widget>[
              for (var i = 0; i < r.length; i++)
                Expanded(
                  child: Text(
                    r[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: i == 0 || i == 2
                        ? LobbyFonts.body(size: 13.5, weight: FontWeight.w600)
                        : LobbyFonts.mono(size: 12.5),
                  ),
                ),
            ],
          ),
        ),
    ];
  }

  Widget _chip(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(
        label,
        style: LobbyFonts.mono(size: 10, letterSpacing: 10 * 0.07, color: fg),
      ),
    );
  }

  Widget _idFact(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              k,
              style: LobbyFonts.body(
                size: 12.5,
                color: ArenaColors.textPrimary.withValues(alpha: 0.45),
              ),
            ),
          ),
          Text(v, style: LobbyFonts.mono(size: 12)),
        ],
      ),
    );
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? ArenaColors.accent.withValues(alpha: 0.12)
              : const Color(0x0AFFFFFF),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected
                ? ArenaColors.accent.withValues(alpha: 0.32)
                : const Color(0x17FFFFFF),
          ),
        ),
        child: Text(
          label,
          style: LobbyFonts.display(
            size: 12.5,
            weight: FontWeight.w600,
            letterSpacing: 12.5 * 0.08,
            color: selected
                ? ArenaColors.accent
                : ArenaColors.textPrimary.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({
    required this.color,
    required this.radius,
    this.strokeWidth = 1.5,
  });

  final Color color;
  final double radius;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      const dash = 4.0;
      const gap = 3.0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
