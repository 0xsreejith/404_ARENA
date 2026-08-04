import 'package:arena_os/app/bootstrap.dart';
import 'package:arena_os/core/errors/app_failure.dart';
import 'package:arena_os/core/errors/failure_mapper.dart';
import 'package:arena_os/features/devices/device_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum AuthStatus {
  unauthenticated,
  authenticating,
  authenticated,
  error,
}

class AuthState {
  const AuthState({
    required this.status,
    this.userContext,
    this.failure,
  });

  factory AuthState.initial() => const AuthState(status: AuthStatus.unauthenticated);

  final AuthStatus status;
  final Map<String, dynamic>? userContext;
  final AppFailure? failure;

  String? get errorMessage => failure?.message;

  AuthState copyWith({
    AuthStatus? status,
    Map<String, dynamic>? userContext,
    AppFailure? failure,
    bool clearFailure = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      userContext: userContext ?? this.userContext,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});

final authControllerProvider =
    NotifierProvider<AuthControllerNotifier, AuthState>(AuthControllerNotifier.new);

class AuthControllerNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    final repo = ref.watch(authRepositoryProvider);
    if (repo.isAuthenticated) {
      Future.microtask(loadUserContext);
    }
    return AuthState.initial();
  }

  AuthRepository get _repository => ref.read(authRepositoryProvider);

  Future<void> signIn(String email, String password) async {
    state = state.copyWith(status: AuthStatus.authenticating, clearFailure: true);
    try {
      await _repository.signInWithEmailAndPassword(email: email, password: password);
      await loadUserContext();
    } catch (e, st) {
      final failure = e is AppFailure ? e : failureMapper.map(e, st);
      state = state.copyWith(status: AuthStatus.error, failure: failure);
    }
  }

  Future<void> loadUserContext() async {
    state = state.copyWith(status: AuthStatus.authenticating, clearFailure: true);
    try {
      final context = await _repository.fetchUserContext();
      ref.read(lastServerContactProvider.notifier).touch();
      state = state.copyWith(
        status: AuthStatus.authenticated,
        userContext: context,
        clearFailure: true,
      );
    } catch (e, st) {
      final failure = e is AppFailure ? e : failureMapper.map(e, st);
      state = state.copyWith(status: AuthStatus.error, failure: failure);
    }
  }

  Future<void> signOut() async {
    await _repository.signOut();
    state = AuthState.initial();
  }
}

/// Repository handling authentication and user context RPC calls.
class AuthRepository {
  AuthRepository(this._supabase);

  final SupabaseClient _supabase;

  bool get isAuthenticated => _supabase.auth.currentSession != null;

  String? get currentUserId => _supabase.auth.currentUser?.id;

  Future<AuthResponse> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      return await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } catch (error, stackTrace) {
      throw failureMapper.map(error, stackTrace);
    }
  }

  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (error, stackTrace) {
      throw failureMapper.map(error, stackTrace);
    }
  }

  Future<Map<String, dynamic>> fetchUserContext() async {
    try {
      final response = await _supabase.rpc<dynamic>('me');
      if (response == null) {
        throw const FormatException('me() RPC returned null response');
      }
      return Map<String, dynamic>.from(response as Map);
    } catch (error, stackTrace) {
      throw failureMapper.map(error, stackTrace);
    }
  }
}
