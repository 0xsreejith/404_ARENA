/// The single failure type crossing the data-source boundary
/// (`ARCHITECTURE.md` §10).
///
/// Raw `PostgrestException`, `AuthException`, and socket errors are mapped once
/// in `failure_mapper.dart` and never reach a controller or a widget. Every
/// screen renders loading, empty, error, and permission-denied states from
/// these variants.
///
/// [retryable] follows the classification in `OFFLINE.md` §5 and is what the
/// sync engine keys off when deciding between backoff and dead-lettering.
sealed class AppFailure implements Exception {
  const AppFailure({required this.message, this.serverCode, this.cause});

  /// Plain-language text safe to show a member of staff.
  ///
  /// Says what happened and what to do — "Station already in use, refresh the
  /// floor", never "PostgrestException 23505".
  final String message;

  /// The stable RPC error code from `API.md` §1, when the server supplied one.
  final String? serverCode;

  /// The originating error, for logs only. Never rendered.
  final Object? cause;

  /// Whether the sync engine may retry this operation (`OFFLINE.md` §5).
  bool get retryable;

  /// Whether the operation definitively did not take effect on the server.
  ///
  /// The UI must never present an operation as confirmed unless this is false
  /// and the call actually succeeded (`CLAUDE.md`, non-negotiable 8).
  bool get reachedServer => switch (this) {
    NetworkFailure() || OfflineFailure() || StaleClientFailure() => false,
    _ => true,
  };

  @override
  String toString() => '$runtimeType(${serverCode ?? '-'}): $message';
}

/// The request left the device but the network failed, timed out, or the
/// server returned 5xx.
class NetworkFailure extends AppFailure {
  const NetworkFailure({required super.message, super.cause, super.serverCode});

  @override
  bool get retryable => true;
}

/// The device has no connectivity and the operation is not offline-capable
/// (`OFFLINE.md` §2). Never sent.
class OfflineFailure extends AppFailure {
  const OfflineFailure({required super.message, super.cause})
    : super(serverCode: 'offline_not_permitted');

  @override
  bool get retryable => true;
}

/// More than 24 hours without a successful sync, so no new mutation is
/// accepted (D18). Read-only until the device reconnects.
class StaleClientFailure extends AppFailure {
  const StaleClientFailure({required super.message, super.cause})
    : super(serverCode: 'stale_operation');

  @override
  bool get retryable => false;
}

/// Not signed in, or the session expired and could not be refreshed.
class AuthFailure extends AppFailure {
  const AuthFailure({required super.message, super.cause, super.serverCode});

  @override
  bool get retryable => false;
}

/// Authenticated, but lacking the permission code the RPC requires.
///
/// Non-retryable by design: a queued mutation that fails this way must reach a
/// human rather than loop (`OFFLINE.md` §5).
class PermissionFailure extends AppFailure {
  const PermissionFailure({required super.message, super.cause})
    : super(serverCode: 'insufficient_privilege');

  @override
  bool get retryable => false;
}

/// The server rejected the arguments.
class ValidationFailure extends AppFailure {
  const ValidationFailure({
    required super.message,
    super.cause,
    super.serverCode = 'validation_failed',
    this.fieldErrors = const <String, String>{},
  });

  final Map<String, String> fieldErrors;

  @override
  bool get retryable => false;
}

/// A constraint or state conflict: the station is already live, the
/// idempotency key was reused, the state transition is illegal.
///
/// Always user-visible and actionable, never a silent retry
/// (`ARCHITECTURE.md` §10).
class ConflictFailure extends AppFailure {
  const ConflictFailure({required super.message, super.cause, super.serverCode});

  @override
  bool get retryable => false;
}

/// The entity does not exist, or exists outside the caller's arena.
///
/// The server does not distinguish the two, and neither should the UI —
/// telling a caller that a row exists in another tenant is itself a leak.
class NotFoundFailure extends AppFailure {
  const NotFoundFailure({required super.message, super.cause}) : super(serverCode: 'not_found');

  @override
  bool get retryable => false;
}

/// An identical operation is already in flight under the same idempotency key.
class OperationInProgressFailure extends AppFailure {
  const OperationInProgressFailure({required super.message, super.cause})
    : super(serverCode: 'operation_in_progress');

  @override
  bool get retryable => true;
}

/// The device clock is outside the arena's tolerance, so the server refused to
/// derive a timestamp from it (`OFFLINE.md` §6).
class ClockSkewFailure extends AppFailure {
  const ClockSkewFailure({required super.message, super.cause})
    : super(serverCode: 'clock_skew_exceeded');

  @override
  bool get retryable => false;
}

/// The build is misconfigured — missing or invalid environment values (D34).
class ConfigurationFailure extends AppFailure {
  const ConfigurationFailure({required super.message, super.cause});

  @override
  bool get retryable => false;
}

/// The server failed in a way this client does not recognise.
///
/// Not retryable: an unrecognised failure of unknown effect must not be
/// replayed against a financial endpoint.
class UnknownFailure extends AppFailure {
  const UnknownFailure({required super.message, super.cause, super.serverCode});

  @override
  bool get retryable => false;
}
