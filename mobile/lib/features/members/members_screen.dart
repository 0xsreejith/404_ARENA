import 'dart:math';

import 'package:arena_os/app/theme/arena_colors.dart';
import 'package:arena_os/core/permissions/can.dart';
import 'package:arena_os/features/lobby_ui/lobby_fonts.dart';
import 'package:arena_os/features/lobby_ui/widgets/lobby_button.dart';
import 'package:arena_os/features/members/members_controller.dart';
import 'package:arena_os/features/tenant/tenant_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Production Members list + thin profile (Wave A/B/C fields when present).
class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen({super.key});

  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends ConsumerState<MembersScreen> {
  final _searchCtrl = TextEditingController();
  String _tab = 'visits';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String? get _arenaId =>
      ref.read(tenantControllerProvider).selectedArena?['id'] as String?;

  Future<void> _showCreateDialog() async {
    final arenaId = _arenaId;
    if (arenaId == null) return;
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF13151D),
        title: Text('Add member', style: LobbyFonts.display(size: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              style: LobbyFonts.body(size: 14),
              decoration: const InputDecoration(labelText: 'Full name'),
            ),
            TextField(
              controller: phoneCtrl,
              style: LobbyFonts.body(size: 14),
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (created != true || !mounted) return;
    await ref.read(membersControllerProvider.notifier).createMember(
          arenaId: arenaId,
          memberId: _newUuid(),
          fullName: nameCtrl.text.trim(),
          phone: phoneCtrl.text.trim(),
          idempotencyKey: _newUuid(),
        );
  }

  String _newUuid() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    values[6] = (values[6] & 0x0f) | 0x40;
    values[8] = (values[8] & 0x3f) | 0x80;
    final hex = values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(membersControllerProvider);
    final canCreate = ref.watch(canProvider('member.create'));
    final arenaId = _arenaId;

    if (state.selected != null) {
      return _Profile(
        member: state.selected!,
        notes: state.notes,
        timeline: state.timeline,
        tab: _tab,
        loading: state.isLoadingProfile,
        onTab: (t) => setState(() => _tab = t),
        onBack: () {
          setState(() => _tab = 'visits');
          ref.read(membersControllerProvider.notifier).closeMember();
        },
        onBlock: () async {
          final blocked = state.selected!['blocked'] == true;
          String? reason;
          if (!blocked) {
            reason = await _askReason();
            if (reason == null || reason.trim().isEmpty) return;
          }
          if (arenaId == null) return;
          await ref.read(membersControllerProvider.notifier).setBlocked(
                arenaId: arenaId,
                memberId: state.selected!['id'] as String,
                blocked: !blocked,
                reason: reason,
              );
        },
        onAddNote: () async {
          final body = await _askNote();
          if (body == null || body.trim().isEmpty || arenaId == null) return;
          await ref.read(membersControllerProvider.notifier).addNote(
                arenaId: arenaId,
                memberId: state.selected!['id'] as String,
                kind: 'general',
                body: body,
              );
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  style: LobbyFonts.mono(size: 14),
                  decoration: InputDecoration(
                    hintText: 'Search by phone or name (min 3 chars)',
                    hintStyle: LobbyFonts.mono(
                      size: 13,
                      color: ArenaColors.textMuted,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF181B22),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  onChanged: (q) {
                    if (arenaId != null) {
                      ref
                          .read(membersControllerProvider.notifier)
                          .setQuery(arenaId, q);
                    }
                  },
                ),
              ),
              if (canCreate) ...[
                const SizedBox(width: 10),
                LobbyButton(
                  label: '+ ADD MEMBER',
                  height: 48,
                  fontSize: 13,
                  onTap: _showCreateDialog,
                ),
              ],
            ],
          ),
          if (state.error != null) ...[
            const SizedBox(height: 10),
            Text(state.error!, style: LobbyFonts.body(color: ArenaColors.danger, size: 13)),
          ],
          const SizedBox(height: 14),
          Expanded(
            child: state.isSearching
                ? const Center(child: CircularProgressIndicator())
                : state.results.isEmpty
                    ? Center(
                        child: Text(
                          state.query.trim().length < 3
                              ? 'Type at least 3 characters to search'
                              : 'No members match',
                          style: LobbyFonts.body(color: ArenaColors.textMuted),
                        ),
                      )
                    : ListView.separated(
                        itemCount: state.results.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final m = state.results[i];
                          final blocked = m['blocked'] == true;
                          return Material(
                            color: const Color(0xFF181B22),
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: arenaId == null
                                  ? null
                                  : () {
                                      final id = m['id'] as String;
                                      ref
                                          .read(membersControllerProvider.notifier)
                                          .openMember(arenaId, id);
                                    },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: blocked
                                          ? ArenaColors.danger.withValues(alpha: 0.2)
                                          : ArenaColors.accent.withValues(alpha: 0.15),
                                      child: Text(
                                        _initials(m['full_name'] as String? ?? '?'),
                                        style: LobbyFonts.mono(
                                          size: 11,
                                          weight: FontWeight.w700,
                                          color: blocked
                                              ? ArenaColors.danger
                                              : ArenaColors.accent,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            m['full_name'] as String? ?? '—',
                                            style: LobbyFonts.body(
                                              size: 14,
                                              weight: FontWeight.w600,
                                              color: blocked
                                                  ? ArenaColors.danger
                                                  : ArenaColors.textPrimary,
                                            ),
                                          ),
                                          Text(
                                            (m['phone_masked'] ?? m['phone'] ?? '')
                                                as String,
                                            style: LobbyFonts.mono(
                                              size: 12,
                                              color: ArenaColors.textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      blocked ? 'BLOCKED' : 'ACTIVE',
                                      style: LobbyFonts.mono(
                                        size: 10,
                                        color: blocked
                                            ? ArenaColors.danger
                                            : ArenaColors.accent,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Future<String?> _askReason() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF13151D),
        title: Text('Block reason', style: LobbyFonts.display(size: 16)),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Block'),
          ),
        ],
      ),
    );
  }

  Future<String?> _askNote() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF13151D),
        title: Text('Add note', style: LobbyFonts.display(size: 16)),
        content: TextField(controller: ctrl, maxLines: 3, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _Profile extends StatelessWidget {
  const _Profile({
    required this.member,
    required this.notes,
    required this.timeline,
    required this.tab,
    required this.loading,
    required this.onTab,
    required this.onBack,
    required this.onBlock,
    required this.onAddNote,
  });

  final Map<String, dynamic> member;
  final List<Map<String, dynamic>> notes;
  final List<Map<String, dynamic>> timeline;
  final String tab;
  final bool loading;
  final ValueChanged<String> onTab;
  final VoidCallback onBack;
  final VoidCallback onBlock;
  final VoidCallback onAddNote;

  @override
  Widget build(BuildContext context) {
    final blocked = member['blocked'] == true;
    final stats = Map<String, dynamic>.from(member['stats'] as Map? ?? const {});
    final loyalty = Map<String, dynamic>.from(member['loyalty'] as Map? ?? const {});
    final membership = member['membership'] as Map?;
    final sessions = (member['recent_sessions'] as List?) ?? const [];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TextButton(onPressed: onBack, child: const Text('← Back')),
              const Spacer(),
              TextButton(onPressed: onAddNote, child: const Text('Add note')),
              TextButton(
                onPressed: onBlock,
                child: Text(blocked ? 'Unblock' : 'Block'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            member['full_name'] as String? ?? '—',
            style: LobbyFonts.display(size: 26),
          ),
          Text(
            '${member['phone'] ?? ''} · ${member['member_code'] ?? ''}',
            style: LobbyFonts.mono(size: 12, color: ArenaColors.textMuted),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _Chip('Visits', '${stats['visit_count'] ?? 0}'),
              _Chip('Spend', '${stats['total_spend'] ?? '0.00'}'),
              _Chip('Wallet', '${member['wallet_balance'] ?? '0.00'}'),
              _Chip(
                'Loyalty',
                '${loyalty['points'] ?? 0} ${(loyalty['tier'] as Map?)?['label'] ?? ''}',
              ),
              _Chip(
                'Plan',
                membership == null
                    ? 'Walk-in'
                    : (membership['plan_name'] as String? ?? 'Member'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final t in ['visits', 'notes', 'timeline', 'wallet'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(t.toUpperCase()),
                    selected: tab == t,
                    onSelected: (_) => onTab(t),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : switch (tab) {
                    'notes' => ListView(
                        children: [
                          for (final n in notes)
                            ListTile(
                              title: Text(n['body'] as String? ?? ''),
                              subtitle: Text('${n['kind']} · ${n['created_at']}'),
                            ),
                          if (notes.isEmpty)
                            Text('No notes yet', style: LobbyFonts.body(color: ArenaColors.textMuted)),
                        ],
                      ),
                    'timeline' => ListView(
                        children: [
                          for (final e in timeline)
                            ListTile(
                              title: Text('${e['kind']} · ${e['status'] ?? ''}'),
                              subtitle: Text('${e['at'] ?? ''}'),
                              trailing: Text('${e['amount'] ?? ''}'),
                            ),
                          if (timeline.isEmpty)
                            Text('No timeline events', style: LobbyFonts.body(color: ArenaColors.textMuted)),
                        ],
                      ),
                    'wallet' => ListView(
                        children: [
                          ListTile(
                            title: const Text('Wallet balance'),
                            trailing: Text('${member['wallet_balance'] ?? '0.00'}'),
                          ),
                          ListTile(
                            title: const Text('Outstanding'),
                            trailing: Text('${member['outstanding_balance'] ?? '0.00'}'),
                          ),
                        ],
                      ),
                    _ => ListView(
                        children: [
                          for (final s in sessions)
                            ListTile(
                              title: Text(
                                '${(s as Map)['station_name'] ?? 'Station'} · ${s['game_title'] ?? ''}',
                              ),
                              subtitle: Text('${s['started_at'] ?? ''} · ${s['status']}'),
                            ),
                          if (sessions.isEmpty)
                            Text(
                              'No recent sessions',
                              style: LobbyFonts.body(color: ArenaColors.textMuted),
                            ),
                        ],
                      ),
                  },
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: ArenaColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ArenaColors.accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: LobbyFonts.mono(size: 9, color: ArenaColors.accent)),
          Text(value, style: LobbyFonts.mono(size: 13, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return '?';
  return parts.take(2).map((p) => p.isEmpty ? '' : p[0].toUpperCase()).join();
}
