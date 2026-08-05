import 'dart:math';
import 'package:arena_os/core/errors/app_failure.dart';
import 'package:arena_os/features/floor/floor_controller.dart';
import 'package:arena_os/features/floor/floor_repository.dart';
import 'package:arena_os/features/lobby_ui/lobby_fonts.dart';
import 'package:arena_os/features/lobby_ui/widgets/station_card.dart';
import 'package:arena_os/features/members/members_repository.dart';
import 'package:arena_os/features/tenant/tenant_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class FloorScreen extends ConsumerStatefulWidget {
  const FloorScreen({super.key});

  @override
  ConsumerState<FloorScreen> createState() => _FloorScreenState();
}

class _FloorScreenState extends ConsumerState<FloorScreen> {
  String? _selectedZoneId;

  String _generateUuid() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    values[6] = (values[6] & 0x0f) | 0x40;
    values[8] = (values[8] & 0x3f) | 0x80;
    final hex = values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  void _showStartSessionDialog(StationDisplay station) {
    final tenantState = ref.read(tenantControllerProvider);
    if (!tenantState.hasPermission('session.start')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have permission to start sessions.'),
        ),
      );
      return;
    }
    final floorState = ref.read(floorControllerProvider);
    final arenaId = tenantState.selectedArena?['id'] as String?;
    if (arenaId == null) return;

    final billingPlans = floorState.billingPlans;
    if (billingPlans.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No billing plans configured for this branch'),
        ),
      );
      return;
    }

    String selectedPlanId = billingPlans.first['id'] as String;
    int playerCount = 1;
    String? selectedMemberId;
    String? selectedMemberName;
    var memberHits = <Map<String, dynamic>>[];
    var memberQuery = '';
    var searchingMembers = false;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF13151D),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0x14FFFFFF)),
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          actionsPadding: const EdgeInsets.all(24),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'START SESSION — ${_stripFixturePrefix(station.name)}',
                style: LobbyFonts.display(
                  color: Colors.white,
                  size: 18,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              const Divider(color: Color(0x14FFFFFF), height: 1),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Text(
                  'WHO (OPTIONAL)',
                  style: LobbyFonts.mono(
                    color: Color(0x73E8EAF0),
                    size: 11,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  style: LobbyFonts.body(color: Colors.white, size: 13),
                  decoration: InputDecoration(
                    hintText: 'Search member phone or name',
                    hintStyle: LobbyFonts.body(color: Color(0x73E8EAF0), size: 13),
                    filled: true,
                    fillColor: const Color(0xFF181B22),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0x14FFFFFF)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: tenantState.primaryColor),
                    ),
                  ),
                  onChanged: (q) async {
                    memberQuery = q;
                    if (q.trim().length < 3) {
                      setDialogState(() {
                        memberHits = [];
                        searchingMembers = false;
                      });
                      return;
                    }
                    setDialogState(() => searchingMembers = true);
                    try {
                      final hits = await ref.read(membersRepositoryProvider).search(
                            arenaId: arenaId,
                            query: q.trim(),
                            limit: 6,
                          );
                      if (memberQuery == q) {
                        setDialogState(() {
                          memberHits = hits;
                          searchingMembers = false;
                        });
                      }
                    } catch (_) {
                      if (memberQuery == q) {
                        setDialogState(() {
                          memberHits = [];
                          searchingMembers = false;
                        });
                      }
                    }
                  },
                ),
                if (selectedMemberName != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Selected: $selectedMemberName',
                          style: LobbyFonts.body(
                            color: tenantState.primaryColor,
                            size: 13,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setDialogState(() {
                          selectedMemberId = null;
                          selectedMemberName = null;
                        }),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                ],
                if (searchingMembers)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                for (final hit in memberHits)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      hit['full_name'] as String? ?? '—',
                      style: LobbyFonts.body(color: Colors.white, size: 13),
                    ),
                    subtitle: Text(
                      (hit['phone_masked'] ?? hit['phone'] ?? '') as String,
                      style: LobbyFonts.mono(color: Color(0x73E8EAF0), size: 11),
                    ),
                    onTap: () => setDialogState(() {
                      selectedMemberId = hit['id'] as String?;
                      selectedMemberName = hit['full_name'] as String?;
                      memberHits = [];
                    }),
                  ),
                const SizedBox(height: 16),
                Text(
                  'SELECT BILLING PLAN',
                  style: LobbyFonts.mono(
                    color: Color(0x73E8EAF0),
                    size: 11,
                    letterSpacing: 1.0,
                  ),
                ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: selectedPlanId,
                isExpanded: true,
                dropdownColor: const Color(0xFF181B22),
                style: LobbyFonts.body(
                  color: Colors.white,
                  size: 13,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF181B22),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0x14FFFFFF)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: tenantState.primaryColor),
                  ),
                ),
                items: billingPlans.map((bp) {
                  return DropdownMenuItem<String>(
                    value: bp['id'] as String,
                    child: Text(
                      '${_stripFixturePrefix(bp['name'] as String? ?? 'Plan')} (${bp['price']} ${tenantState.currency})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedPlanId = val);
                },
              ),
              const SizedBox(height: 16),
              Text(
                'PLAYER COUNT',
                style: LobbyFonts.mono(
                  color: Color(0x73E8EAF0),
                  size: 11,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF181B22),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0x14FFFFFF)),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.remove_circle_outline,
                        color: Colors.white70,
                      ),
                      onPressed: playerCount > 1
                          ? () => setDialogState(() => playerCount--)
                          : null,
                    ),
                    Text(
                      '$playerCount',
                      style: LobbyFonts.mono(
                        color: Colors.white,
                        size: 16,
                        weight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.add_circle_outline,
                        color: Colors.white70,
                      ),
                      onPressed: () => setDialogState(() => playerCount++),
                    ),
                  ],
                ),
              ),
            ],
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: const Color(0x0FFFFFFF),
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0x14FFFFFF)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(
                        'CANCEL',
                        style: LobbyFonts.display(
                          size: 12,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: tenantState.primaryColor,
                        foregroundColor: const Color(0xFF07070A),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () async {
                        Navigator.of(dialogContext).pop();
                        try {
                          final repo = ref.read(floorRepositoryProvider);
                          final uuid = _generateUuid();

                          await repo.startSession(
                            arenaId: arenaId,
                            sessionId: uuid,
                            stationId: station.id,
                            billingPlanId: selectedPlanId,
                            playerCount: playerCount,
                            memberId: selectedMemberId,
                          );
                          await ref
                              .read(floorControllerProvider.notifier)
                              .loadFloor(arenaId);
                        } catch (e) {
                          if (mounted) {
                            final message = e is AppFailure
                                ? e.message
                                : e.toString();
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(SnackBar(content: Text(message)));
                          }
                        }
                      },
                      child: Text(
                        'START SESSION',
                        style: LobbyFonts.display(
                          size: 12,
                          letterSpacing: 0.6,
                          color: const Color(0xFF07070A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showUnbilledQueue() {
    final floorState = ref.read(floorControllerProvider);
    final sessions = floorState.unbilledSessions;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF12131A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final maxListHeight = MediaQuery.sizeOf(sheetContext).height * 0.45;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'UNBILLED SESSIONS',
                  style: LobbyFonts.display(
                    color: Colors.white,
                    size: 16,
                    letterSpacing: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  '${sessions.length} completed session${sessions.length == 1 ? '' : 's'} awaiting payment',
                  style: LobbyFonts.body(color: const Color(0x73E8EAF0)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                if (sessions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Queue is clear.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0x73E8EAF0)),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxListHeight),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: sessions.length,
                      separatorBuilder: (_, _) =>
                          const Divider(color: Colors.white10),
                      itemBuilder: (context, index) {
                        final row = sessions[index];
                        final sessionId = row['id'] as String? ?? '';
                        final stationName =
                            row['station_name'] as String? ?? 'Station';
                        final memberName = row['member_name'] as String?;
                        final openOrderId = row['open_order_id'] as String?;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            stationName,
                            style: LobbyFonts.body(
                              color: Colors.white,
                              weight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            memberName ?? 'Walk-in',
                            style: LobbyFonts.body(
                              color: const Color(0x73E8EAF0),
                              size: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: ElevatedButton(
                            onPressed: () {
                              Navigator.of(sheetContext).pop();
                              final orderId = openOrderId ?? _generateUuid();
                              context.push(
                                '/checkout/$orderId?sessionId=$sessionId'
                                '${memberName != null ? '&memberName=${Uri.encodeComponent(memberName)}' : ''}',
                              );
                            },
                            child: const Text('BILL'),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleSessionAction(
    StationDisplay station,
    String action,
  ) async {
    final tenantState = ref.read(tenantControllerProvider);
    final arenaId = tenantState.selectedArena?['id'] as String?;
    final sessionId = station.activeSession?['id'] as String?;
    if (arenaId == null || sessionId == null) return;

    final requiredPermission = switch (action) {
      'pause' => 'session.pause',
      'resume' => 'session.resume',
      'stop' => 'session.stop',
      _ => null,
    };
    if (requiredPermission != null &&
        !tenantState.hasPermission(requiredPermission)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('You do not have permission to $action sessions.'),
          ),
        );
      }
      return;
    }

    final repo = ref.read(floorRepositoryProvider);
    try {
      if (action == 'pause') {
        await repo.pauseSession(arenaId: arenaId, sessionId: sessionId);
      } else if (action == 'resume') {
        await repo.resumeSession(arenaId: arenaId, sessionId: sessionId);
      } else if (action == 'stop') {
        await repo.stopSession(arenaId: arenaId, sessionId: sessionId);
        await ref.read(floorControllerProvider.notifier).loadFloor(arenaId);
        if (!mounted) return;
        final orderId = _generateUuid();
        await context.push('/checkout/$orderId?sessionId=$sessionId');
        return;
      }
      await ref.read(floorControllerProvider.notifier).loadFloor(arenaId);
    } catch (e) {
      if (mounted) {
        final message = e is AppFailure ? e.message : e.toString();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final floorState = ref.watch(floorControllerProvider);
    final tenantState = ref.watch(tenantControllerProvider);
    final primaryColor = tenantState.primaryColor;

    final showZoneFilters = floorState.zones.length > 1;
    final filteredStations = (!showZoneFilters || _selectedZoneId == null)
        ? floorState.stations
        : floorState.stations
              .where((s) => s.zoneId == _selectedZoneId)
              .toList();

    return Material(
      color: const Color(0xFF07070A),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (showZoneFilters)
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _ZoneChip(
                            label: 'ALL ZONES',
                            selected: _selectedZoneId == null,
                            color: primaryColor,
                            onTap: () => setState(() => _selectedZoneId = null),
                          ),
                          const SizedBox(width: 8),
                          ...floorState.zones.map((z) {
                            final isSelected = _selectedZoneId == z['id'];
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _ZoneChip(
                                label: (z['name'] as String).toUpperCase(),
                                selected: isSelected,
                                color: primaryColor,
                                onTap: () => setState(
                                  () => _selectedZoneId = z['id'] as String,
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  )
                else
                  const Spacer(),
                SizedBox(
                  height: 36,
                  child: Row(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                            icon: const Icon(
                              Icons.receipt_long,
                              color: Colors.white70,
                              size: 22,
                            ),
                            tooltip: 'Unbilled sessions',
                            onPressed: _showUnbilledQueue,
                          ),
                          if (floorState.unbilledSessions.isNotEmpty)
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFF4444),
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '${floorState.unbilledSessions.length}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        icon: const Icon(
                          Icons.refresh,
                          color: Colors.white70,
                          size: 22,
                        ),
                        onPressed: () {
                          final arenaId =
                              tenantState.selectedArena?['id'] as String?;
                          if (arenaId != null) {
                            ref
                                .read(floorControllerProvider.notifier)
                                .loadFloor(arenaId);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: floorState.isLoading
                ? Center(child: CircularProgressIndicator(color: primaryColor))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final narrow = constraints.maxWidth < 700;
                      if (narrow) {
                        // Phone / compact: intrinsic-height cards — never clip.
                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                          itemCount: filteredStations.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            return _buildStationCard(filteredStations[index]);
                          },
                        );
                      }
                      return GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 360,
                          mainAxisExtent: 260,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: filteredStations.length,
                        itemBuilder: (context, index) {
                          return _buildStationCard(filteredStations[index]);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStationCard(StationDisplay st) {
    return StationCard(
      station: _toLiveStationCardData(st),
      onTap: () => _handleStationCardTap(st),
    );
  }

  void _handleStationCardTap(StationDisplay station) {
    switch (station.derivedState) {
      case DerivedStationState.idle:
        _showStartSessionDialog(station);
      case DerivedStationState.live:
      case DerivedStationState.ending:
      case DerivedStationState.overtime:
      case DerivedStationState.paused:
        _showSessionActions(station);
      case DerivedStationState.maintenance:
      case DerivedStationState.inactive:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${station.name} is not bookable right now.')),
        );
    }
  }

  void _showSessionActions(StationDisplay station) {
    final activeSession = station.activeSession;
    if (activeSession == null) return;

    final playerName = activeSession['member_name'] as String? ?? 'Walk-in';
    final gameTitle = activeSession['game_title'] as String? ?? 'General Play';
    final canPause =
        station.derivedState == DerivedStationState.live ||
        station.derivedState == DerivedStationState.ending ||
        station.derivedState == DerivedStationState.overtime;
    final canResume = station.derivedState == DerivedStationState.paused;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF12131A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  station.name.toUpperCase(),
                  style: LobbyFonts.display(
                    color: Colors.white,
                    size: 16,
                    letterSpacing: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  '$playerName · $gameTitle',
                  style: LobbyFonts.body(
                    color: const Color(0x73E8EAF0),
                    size: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                if (canPause)
                  _sessionSheetButton(
                    label: 'PAUSE SESSION',
                    color: const Color(0xFFFFB020),
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _handleSessionAction(station, 'pause');
                    },
                  ),
                if (canResume)
                  _sessionSheetButton(
                    label: 'RESUME SESSION',
                    color: const Color(0xFF7CFF4F),
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _handleSessionAction(station, 'resume');
                    },
                  ),
                if (canPause || canResume) const SizedBox(height: 10),
                _sessionSheetButton(
                  label: 'END & BILL',
                  color: const Color(0xFFFF4444),
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    _handleSessionAction(station, 'stop');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sessionSheetButton({
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 42,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.14),
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.35)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: onPressed,
        child: Text(
          label,
          style: LobbyFonts.display(
            size: 12,
            letterSpacing: 0.6,
            color: color,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  LiveStationCardData _toLiveStationCardData(StationDisplay station) {
    final floorState = ref.read(floorControllerProvider);
    final activeSession = station.activeSession;
    final playerCount = activeSession?['player_count'] as int? ?? 0;
    final seats = max(station.seatCapacity, max(1, playerCount));
    final zoneName = _lookupName(
      floorState.zones,
      station.zoneId,
      fallback: 'FLOOR',
    );
    final stationTypeName = _lookupName(
      floorState.stationTypes,
      station.stationTypeId,
      fallback: 'STATION',
    );
    final seatWord = seats == 1 ? 'SEAT' : 'SEATS';
    final typeLine = '$stationTypeName · $zoneName · $seats $seatWord';
    final plannedEndAt = _parseDate(activeSession?['planned_end_at']);
    final startedAt = _parseDate(activeSession?['started_at']);
    final elapsedMinutes = _elapsedMinutes(activeSession);
    final timerLabel = switch (station.derivedState) {
      DerivedStationState.overtime => 'OVER BOOKED TIME',
      DerivedStationState.paused => 'ON HOLD',
      _ => plannedEndAt == null ? 'ELAPSED · OPEN-ENDED' : 'REMAINING',
    };

    return LiveStationCardData(
      id: _stripFixturePrefix(station.name),
      typeLine: typeLine.toUpperCase(),
      seats: seats,
      status: _toCardStatus(station.derivedState),
      players: _playersFor(activeSession),
      gameName: _stripFixturePrefix(
        activeSession?['game_title'] as String? ?? 'General Play',
      ),
      timerText: station.derivedState == DerivedStationState.idle
          ? 'READY'
          : station.formattedTimer,
      timerLabel: station.derivedState == DerivedStationState.idle
          ? 'FREE NOW'
          : timerLabel,
      progressFraction: _sessionProgress(
        startedAt: startedAt,
        plannedEndAt: plannedEndAt,
        elapsedMinutes: elapsedMinutes,
        state: station.derivedState,
      ),
      rateText: _rateText(floorState.billingPlans, station.stationTypeId),
      amountLabel: activeSession == null ? '' : 'RUNNING',
      amountText: activeSession == null
          ? '—'
          : _runningAmountText(activeSession, elapsedMinutes),
      idleLine: 'Tap to start',
      maintenanceLine: station.derivedState == DerivedStationState.inactive
          ? 'Disabled in catalogue'
          : 'Not bookable right now',
    );
  }

  LiveStationCardStatus _toCardStatus(DerivedStationState state) {
    return switch (state) {
      DerivedStationState.idle => LiveStationCardStatus.idle,
      DerivedStationState.live => LiveStationCardStatus.live,
      DerivedStationState.ending => LiveStationCardStatus.ending,
      DerivedStationState.overtime => LiveStationCardStatus.overtime,
      DerivedStationState.paused => LiveStationCardStatus.paused,
      DerivedStationState.maintenance => LiveStationCardStatus.maintenance,
      DerivedStationState.inactive => LiveStationCardStatus.inactive,
    };
  }

  String _lookupName(
    List<Map<String, dynamic>> rows,
    String id, {
    required String fallback,
  }) {
    for (final row in rows) {
      if (row['id'] == id) {
        return _stripFixturePrefix(row['name'] as String? ?? fallback);
      }
    }
    return fallback;
  }

  String _stripFixturePrefix(String value) {
    return value.replaceFirst(RegExp(r'^\[FIXTURE\]\s*', caseSensitive: false), '').trim();
  }

  List<String> _playersFor(Map<String, dynamic>? session) {
    if (session == null) return const <String>[];
    final count = max(1, session['player_count'] as int? ?? 1);
    final memberName = session['member_name'] as String?;
    if (memberName == null || memberName.trim().isEmpty) {
      return List<String>.generate(count, (index) => 'Walk-in ${index + 1}');
    }
    return <String>[memberName, for (var i = 2; i <= count; i++) 'Player $i'];
  }

  String _rateText(
    List<Map<String, dynamic>> billingPlans,
    String stationTypeId,
  ) {
    Map<String, dynamic>? plan;
    for (final row in billingPlans) {
      if (row['station_type_id'] == stationTypeId) {
        plan = row;
        break;
      }
    }
    plan ??= billingPlans.isNotEmpty ? billingPlans.first : null;
    if (plan == null) return '—';

    final price = _asNum(plan['price']);
    if (price == null) {
      return _stripFixturePrefix(plan['name'] as String? ?? '—');
    }
    final type = plan['type'] as String?;
    final duration = plan['duration_minutes'] as int?;
    if (type == 'fixed_duration' && duration != null) {
      return '${_formatCurrency(price)} · ${duration}m';
    }
    return '${_formatCurrency(price)} · hr';
  }

  String _runningAmountText(
    Map<String, dynamic> session,
    double elapsedMinutes,
  ) {
    final snapshot = session['pricing_snapshot'];
    final pricing = snapshot is Map
        ? Map<String, dynamic>.from(snapshot)
        : const <String, dynamic>{};
    final rate = _asNum(pricing['rate']);
    if (rate == null) return '—';

    final planType = pricing['plan_type'] as String?;
    final plannedEndAt = _parseDate(session['planned_end_at']);
    var amount = rate;
    if (planType != 'fixed_duration') {
      amount = rate * max(elapsedMinutes, 1) / 60;
    } else if (plannedEndAt != null && DateTime.now().isAfter(plannedEndAt)) {
      final overtimeMinutes = DateTime.now().difference(plannedEndAt).inMinutes;
      amount += rate * (overtimeMinutes / 60);
    }
    return _formatCurrency(amount);
  }

  double _elapsedMinutes(Map<String, dynamic>? session) {
    if (session == null) return 0;
    final startedAt = _parseDate(session['started_at']);
    if (startedAt == null) return 0;
    final totalPausedSeconds = session['total_paused_seconds'] as int? ?? 0;
    final pausedAt = _parseDate(session['paused_at']);
    final end = pausedAt ?? DateTime.now();
    final elapsedSeconds =
        end.difference(startedAt).inSeconds - totalPausedSeconds;
    return max(0, elapsedSeconds) / 60;
  }

  double _sessionProgress({
    required DateTime? startedAt,
    required DateTime? plannedEndAt,
    required double elapsedMinutes,
    required DerivedStationState state,
  }) {
    if (state == DerivedStationState.idle ||
        state == DerivedStationState.paused) {
      return 0;
    }
    if (state == DerivedStationState.overtime) return 1;
    if (startedAt == null || plannedEndAt == null) {
      return (elapsedMinutes / 60).clamp(0.0, 1.0);
    }
    final totalSeconds = plannedEndAt.difference(startedAt).inSeconds;
    if (totalSeconds <= 0) return 1;
    final elapsedSeconds = DateTime.now().difference(startedAt).inSeconds;
    return (elapsedSeconds / totalSeconds).clamp(0.0, 1.0);
  }

  DateTime? _parseDate(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }

  num? _asNum(Object? value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value);
    return null;
  }

  String _formatCurrency(num value) {
    final currency = ref.read(tenantControllerProvider).currency;
    final rounded = value.round();
    final raw = rounded.toString();
    final withCommas = raw.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]},',
    );
    return '$withCommas $currency';
  }
}

class _ZoneChip extends StatelessWidget {
  const _ZoneChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color : const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? color : const Color(0x28FFFFFF),
          ),
        ),
        child: Text(
          label,
          style: LobbyFonts.display(
            color: selected ? const Color(0xFF07070A) : Colors.white,
            size: 11,
            letterSpacing: 0.6,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
