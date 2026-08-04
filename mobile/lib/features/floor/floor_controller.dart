import 'dart:async';
import 'package:arena_os/core/errors/app_failure.dart';
import 'package:arena_os/features/devices/device_repository.dart';
import 'package:arena_os/features/floor/floor_repository.dart';
import 'package:arena_os/features/tenant/tenant_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum DerivedStationState {
  idle,
  live,
  ending,
  overtime,
  paused,
  maintenance,
  inactive,
}

class StationDisplay {
  StationDisplay({
    required this.id,
    required this.name,
    required this.zoneId,
    required this.stationTypeId,
    required this.status,
    required this.derivedState,
    this.activeSession,
    this.formattedTimer = '00:00:00',
    this.seatCapacity = 1,
  });

  final String id;
  final String name;
  final String zoneId;
  final String stationTypeId;
  final String status;
  final DerivedStationState derivedState;
  final Map<String, dynamic>? activeSession;
  final String formattedTimer;
  final int seatCapacity;
}

class FloorState {
  const FloorState({
    this.zones = const [],
    this.stationTypes = const [],
    this.stations = const [],
    this.games = const [],
    this.billingPlans = const [],
    this.unbilledSessions = const [],
    this.isLoading = false,
    this.error,
  });

  final List<Map<String, dynamic>> zones;
  final List<Map<String, dynamic>> stationTypes;
  final List<StationDisplay> stations;
  final List<Map<String, dynamic>> games;
  final List<Map<String, dynamic>> billingPlans;
  final List<Map<String, dynamic>> unbilledSessions;
  final bool isLoading;
  final String? error;

  FloorState copyWith({
    List<Map<String, dynamic>>? zones,
    List<Map<String, dynamic>>? stationTypes,
    List<StationDisplay>? stations,
    List<Map<String, dynamic>>? games,
    List<Map<String, dynamic>>? billingPlans,
    List<Map<String, dynamic>>? unbilledSessions,
    bool? isLoading,
    String? error,
  }) {
    return FloorState(
      zones: zones ?? this.zones,
      stationTypes: stationTypes ?? this.stationTypes,
      stations: stations ?? this.stations,
      games: games ?? this.games,
      billingPlans: billingPlans ?? this.billingPlans,
      unbilledSessions: unbilledSessions ?? this.unbilledSessions,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

final floorControllerProvider =
    NotifierProvider<FloorControllerNotifier, FloorState>(
      FloorControllerNotifier.new,
    );

class FloorControllerNotifier extends Notifier<FloorState> {
  Timer? _timer;

  @override
  FloorState build() {
    _startTimer();
    ref.onDispose(() {
      _timer?.cancel();
    });

    final tenantState = ref.watch(tenantControllerProvider);
    final arenaId = tenantState.selectedArena?['id'] as String?;

    if (arenaId != null) {
      Future.microtask(() => loadFloor(arenaId));
    }

    return const FloorState();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _tickTimer();
    });
  }

  void _tickTimer() {
    if (state.stations.isEmpty) return;

    final updatedStations = state.stations.map((st) {
      if (st.activeSession == null) return st;
      final derived = _deriveStationState(st.status, st.activeSession);
      final timerText = _calculateFormattedTimer(st.activeSession);
      return StationDisplay(
        id: st.id,
        name: st.name,
        zoneId: st.zoneId,
        stationTypeId: st.stationTypeId,
        status: st.status,
        derivedState: derived,
        activeSession: st.activeSession,
        formattedTimer: timerText,
        seatCapacity: st.seatCapacity,
      );
    }).toList();

    state = state.copyWith(stations: updatedStations);
  }

  Future<void> loadFloor(String arenaId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final repo = ref.read(floorRepositoryProvider);
      final snapshot = await repo.fetchFloorSnapshot(arenaId);

      final rawZones = (snapshot['zones'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final rawTypes = (snapshot['station_types'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final rawStations = (snapshot['stations'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final rawGames = (snapshot['games'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final rawPlans = (snapshot['billing_plans'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final rawLiveSessions =
          (snapshot['live_sessions'] as List<dynamic>? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
      final rawUnbilled =
          (snapshot['unbilled_sessions'] as List<dynamic>? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();

      final stationDisplays = rawStations.map((st) {
        final stId = st['id'] as String;
        final activeSess = rawLiveSessions
            .cast<Map<String, dynamic>?>()
            .firstWhere(
              (sess) => sess?['station_id'] == stId,
              orElse: () => null,
            );

        final derived = _deriveStationState(
          st['status'] as String? ?? 'active',
          activeSess,
        );
        final timerText = _calculateFormattedTimer(activeSess);

        return StationDisplay(
          id: stId,
          name: st['name'] as String? ?? '',
          zoneId: st['zone_id'] as String? ?? '',
          stationTypeId: st['station_type_id'] as String? ?? '',
          status: st['status'] as String? ?? 'active',
          derivedState: derived,
          activeSession: activeSess,
          formattedTimer: timerText,
          seatCapacity: st['seat_capacity'] as int? ?? 1,
        );
      }).toList();

      state = state.copyWith(
        zones: rawZones,
        stationTypes: rawTypes,
        stations: stationDisplays,
        games: rawGames,
        billingPlans: rawPlans,
        unbilledSessions: rawUnbilled,
        isLoading: false,
      );
      ref.read(lastServerContactProvider.notifier).touch();
    } catch (e) {
      final message = e is AppFailure ? e.message : e.toString();
      state = state.copyWith(isLoading: false, error: message);
    }
  }

  static DerivedStationState _deriveStationState(
    String status,
    Map<String, dynamic>? session,
  ) {
    if (status == 'maintenance') return DerivedStationState.maintenance;
    if (status == 'inactive') return DerivedStationState.inactive;
    if (session == null) return DerivedStationState.idle;

    final sessionStatus = session['status'] as String?;
    if (sessionStatus == 'paused') return DerivedStationState.paused;

    final plannedEndStr = session['planned_end_at'] as String?;
    if (plannedEndStr == null) return DerivedStationState.live;

    final plannedEnd = DateTime.tryParse(plannedEndStr);
    if (plannedEnd == null) return DerivedStationState.live;

    final remainingSeconds = plannedEnd.difference(DateTime.now()).inSeconds;
    if (remainingSeconds <= 0) return DerivedStationState.overtime;
    if (remainingSeconds <= 600) return DerivedStationState.ending;
    return DerivedStationState.live;
  }

  static String _calculateFormattedTimer(Map<String, dynamic>? session) {
    if (session == null) return '00:00:00';

    final startedAtStr = session['started_at'] as String?;
    final plannedEndStr = session['planned_end_at'] as String?;
    final totalPaused = session['total_paused_seconds'] as int? ?? 0;
    final status = session['status'] as String?;

    if (startedAtStr == null) return '00:00:00';
    final startedAt = DateTime.tryParse(startedAtStr) ?? DateTime.now();

    if (status == 'paused') return 'PAUSED';

    if (plannedEndStr != null) {
      final plannedEnd = DateTime.tryParse(plannedEndStr) ?? DateTime.now();
      final diff = plannedEnd.difference(DateTime.now()).inSeconds;

      if (diff < 0) {
        final overtimeSec = diff.abs();
        return '+${_formatHHMMSS(overtimeSec)}';
      }
      return _formatHHMMSS(diff);
    }

    final elapsedSec =
        DateTime.now().difference(startedAt).inSeconds - totalPaused;
    return _formatHHMMSS(elapsedSec > 0 ? elapsedSec : 0);
  }

  static String _formatHHMMSS(int totalSeconds) {
    final hours = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
    final minutes = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}
