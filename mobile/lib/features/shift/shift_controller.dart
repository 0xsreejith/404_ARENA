import 'dart:math';

import 'package:arena_os/core/errors/app_failure.dart';
import 'package:arena_os/core/errors/failure_mapper.dart';
import 'package:arena_os/features/devices/device_repository.dart';
import 'package:arena_os/features/shift/shift_repository.dart';
import 'package:arena_os/features/tenant/tenant_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ShiftState {
  const ShiftState({
    this.current,
    this.summary,
    this.isLoading = false,
    this.isSubmitting = false,
    this.error,
  });

  final Map<String, dynamic>? current;
  final Map<String, dynamic>? summary;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;

  ShiftState copyWith({
    Map<String, dynamic>? current,
    Map<String, dynamic>? summary,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
    bool clearCurrent = false,
    bool clearSummary = false,
    bool clearError = false,
  }) {
    return ShiftState(
      current: clearCurrent ? null : (current ?? this.current),
      summary: clearSummary ? null : (summary ?? this.summary),
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final shiftControllerProvider =
    NotifierProvider<ShiftControllerNotifier, ShiftState>(ShiftControllerNotifier.new);

class ShiftControllerNotifier extends Notifier<ShiftState> {
  @override
  ShiftState build() {
    final arenaId = ref.watch(tenantControllerProvider).selectedArena?['id'] as String?;
    if (arenaId != null) {
      Future.microtask(() => load(arenaId));
    }
    return const ShiftState();
  }

  Future<void> load(String arenaId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final repo = ref.read(shiftRepositoryProvider);
      final current = await repo.fetchCurrent(arenaId);
      final summary = current == null
          ? null
          : await repo.fetchSummary(
              arenaId: arenaId,
              shiftId: current['id'] as String,
            );
      state = state.copyWith(
        current: current,
        summary: summary,
        isLoading: false,
        clearCurrent: current == null,
        clearSummary: summary == null,
      );
      ref.read(lastServerContactProvider.notifier).touch();
    } catch (e, st) {
      final failure = e is AppFailure ? e : failureMapper.map(e, st);
      state = state.copyWith(isLoading: false, error: failure.message);
    }
  }

  Future<void> openShift(String openingFloat) async {
    final arenaId = ref.read(tenantControllerProvider).selectedArena?['id'] as String?;
    if (arenaId == null) return;

    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final repo = ref.read(shiftRepositoryProvider);
      await repo.openShift(
        arenaId: arenaId,
        shiftId: _newUuidV4(),
        openingFloat: openingFloat,
        idempotencyKey: 'shift-open-${_newUuidV4()}',
      );
      await load(arenaId);
      state = state.copyWith(isSubmitting: false);
    } catch (e, st) {
      final failure = e is AppFailure ? e : failureMapper.map(e, st);
      state = state.copyWith(isSubmitting: false, error: failure.message);
    }
  }

  Future<void> closeShift({
    required String countedCash,
    required String notes,
  }) async {
    final arenaId = ref.read(tenantControllerProvider).selectedArena?['id'] as String?;
    final shiftId = state.current?['id'] as String?;
    if (arenaId == null || shiftId == null) return;

    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final repo = ref.read(shiftRepositoryProvider);
      await repo.closeShift(
        arenaId: arenaId,
        shiftId: shiftId,
        countedCash: countedCash,
        notes: notes,
        idempotencyKey: 'shift-close-${_newUuidV4()}',
      );
      await load(arenaId);
      state = state.copyWith(isSubmitting: false);
    } catch (e, st) {
      final failure = e is AppFailure ? e : failureMapper.map(e, st);
      state = state.copyWith(isSubmitting: false, error: failure.message);
    }
  }

  static String _newUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final h = bytes.map(hex).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }
}
