import 'dart:async';

import 'package:arena_os/core/errors/app_failure.dart';
import 'package:arena_os/features/members/members_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MembersState {
  const MembersState({
    this.query = '',
    this.results = const [],
    this.selected,
    this.notes = const [],
    this.timeline = const [],
    this.isSearching = false,
    this.isLoadingProfile = false,
    this.error,
  });

  final String query;
  final List<Map<String, dynamic>> results;
  final Map<String, dynamic>? selected;
  final List<Map<String, dynamic>> notes;
  final List<Map<String, dynamic>> timeline;
  final bool isSearching;
  final bool isLoadingProfile;
  final String? error;

  MembersState copyWith({
    String? query,
    List<Map<String, dynamic>>? results,
    Map<String, dynamic>? selected,
    bool clearSelected = false,
    List<Map<String, dynamic>>? notes,
    List<Map<String, dynamic>>? timeline,
    bool? isSearching,
    bool? isLoadingProfile,
    String? error,
    bool clearError = false,
  }) {
    return MembersState(
      query: query ?? this.query,
      results: results ?? this.results,
      selected: clearSelected ? null : (selected ?? this.selected),
      notes: notes ?? this.notes,
      timeline: timeline ?? this.timeline,
      isSearching: isSearching ?? this.isSearching,
      isLoadingProfile: isLoadingProfile ?? this.isLoadingProfile,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final membersControllerProvider =
    NotifierProvider<MembersControllerNotifier, MembersState>(
  MembersControllerNotifier.new,
);

class MembersControllerNotifier extends Notifier<MembersState> {
  Timer? _debounce;

  MembersRepository get _repo => ref.read(membersRepositoryProvider);

  @override
  MembersState build() {
    ref.onDispose(() => _debounce?.cancel());
    return const MembersState();
  }

  void setQuery(String arenaId, String query) {
    state = state.copyWith(query: query, clearError: true);
    _debounce?.cancel();
    if (query.trim().length < 3) {
      state = state.copyWith(results: const [], isSearching: false);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), () {
      unawaited(search(arenaId, query));
    });
  }

  Future<void> search(String arenaId, String query) async {
    state = state.copyWith(isSearching: true, clearError: true);
    try {
      final rows = await _repo.search(arenaId: arenaId, query: query);
      state = state.copyWith(results: rows, isSearching: false);
    } on AppFailure catch (e) {
      state = state.copyWith(isSearching: false, error: e.message);
    } catch (e) {
      state = state.copyWith(isSearching: false, error: e.toString());
    }
  }

  Future<void> openMember(String arenaId, String memberId) async {
    state = state.copyWith(isLoadingProfile: true, clearError: true);
    try {
      final member = await _repo.get(arenaId: arenaId, memberId: memberId);
      final notes = await _repo.listNotes(arenaId: arenaId, memberId: memberId);
      final timeline =
          await _repo.timeline(arenaId: arenaId, memberId: memberId);
      state = state.copyWith(
        selected: member,
        notes: notes,
        timeline: timeline,
        isLoadingProfile: false,
      );
    } on AppFailure catch (e) {
      state = state.copyWith(isLoadingProfile: false, error: e.message);
    } catch (e) {
      state = state.copyWith(isLoadingProfile: false, error: e.toString());
    }
  }

  void closeMember() {
    state = state.copyWith(
      clearSelected: true,
      notes: const [],
      timeline: const [],
    );
  }

  Future<Map<String, dynamic>?> createMember({
    required String arenaId,
    required String memberId,
    required String fullName,
    required String phone,
    String? notes,
    String? idempotencyKey,
  }) async {
    try {
      final created = await _repo.create(
        arenaId: arenaId,
        memberId: memberId,
        fullName: fullName,
        phone: phone,
        notes: notes,
        idempotencyKey: idempotencyKey,
      );
      await openMember(arenaId, created['id'] as String);
      return created;
    } on AppFailure catch (e) {
      state = state.copyWith(error: e.message);
      return null;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  Future<void> setBlocked({
    required String arenaId,
    required String memberId,
    required bool blocked,
    String? reason,
  }) async {
    try {
      await _repo.setBlocked(
        arenaId: arenaId,
        memberId: memberId,
        blocked: blocked,
        reason: reason,
      );
      await openMember(arenaId, memberId);
    } on AppFailure catch (e) {
      state = state.copyWith(error: e.message);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> addNote({
    required String arenaId,
    required String memberId,
    required String kind,
    required String body,
  }) async {
    try {
      await _repo.addNote(
        arenaId: arenaId,
        memberId: memberId,
        kind: kind,
        body: body,
      );
      await openMember(arenaId, memberId);
    } on AppFailure catch (e) {
      state = state.copyWith(error: e.message);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
}
