import 'dart:async';
import 'dart:io';

import 'package:arena_os/core/errors/app_failure.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Maps transport and database errors to [AppFailure], once, at the Supabase
/// boundary (`ARCHITECTURE.md` §10).
///
/// Nothing above the data layer catches a `PostgrestException`. If a raw
/// Supabase type appears in a controller, this mapper was bypassed.
///
/// The mapping is driven by the stable RPC error codes in `API.md` §1. Every
/// mutating RPC raises one, so the common path is a lookup rather than string
/// matching on a Postgres message.
class FailureMapper {
  const FailureMapper();

  /// PostgreSQL `SQLSTATE` values that surface for reasons of their own,
  /// independently of the application-level codes.
  static const String _sqlStateUniqueViolation = '23505';
  static const String _sqlStateForeignKeyViolation = '23503';
  static const String _sqlStateCheckViolation = '23514';
  static const String _sqlStateNotNullViolation = '23502';
  static const String _sqlStateInsufficientPrivilege = '42501';
  static const String _sqlStateRaiseException = 'P0001';

  AppFailure map(Object error, [StackTrace? stackTrace]) {
    if (error is AppFailure) return error;

    if (error is PostgrestException) return _fromPostgrest(error);
    if (error is AuthException) {
      final raw = error.message.toLowerCase();
      final message = raw.contains('invalid') || raw.contains('credentials')
          ? 'Email or password is incorrect.'
          : 'Your session is no longer valid. Sign in again.';
      return AuthFailure(
        message: message,
        serverCode: error.statusCode,
        cause: error,
      );
    }
    if (error is StorageException) {
      return NetworkFailure(message: 'Storage request failed.', cause: error);
    }

    if (error is SocketException || error is HttpException) {
      return NetworkFailure(
        message: 'No connection to the server. Check the network and retry.',
        cause: error,
      );
    }
    if (error is TimeoutException) {
      return NetworkFailure(
        message: 'The server took too long to respond. Retry in a moment.',
        cause: error,
      );
    }
    if (error is FormatException) {
      return ValidationFailure(
        message: 'The server sent a response this app could not read.',
        cause: error,
      );
    }

    return UnknownFailure(message: 'Something went wrong.', cause: error);
  }

  AppFailure _fromPostgrest(PostgrestException error) {
    // `API.md` §1 codes are raised as the exception's code or embedded in the
    // message by `RAISE EXCEPTION ... USING ERRCODE`.
    final code = _applicationCode(error);

    switch (code) {
      case 'insufficient_privilege':
        return PermissionFailure(message: 'You do not have permission to do that.', cause: error);
      case 'not_found':
        return NotFoundFailure(message: 'That item no longer exists.', cause: error);
      case 'invalid_state':
        if (error.message.toLowerCase().contains('open shift')) {
          return ConflictFailure(
            message: 'Open a shift before taking payments.',
            serverCode: code,
            cause: error,
          );
        }
        return ConflictFailure(
          message:
              'That action is not possible in the current state. '
              'Refresh and try again.',
          serverCode: code,
          cause: error,
        );
      case 'conflict':
        return ConflictFailure(
          message: 'Someone else changed this first. Refresh and try again.',
          serverCode: code,
          cause: error,
        );
      case 'idempotency_key_reuse':
        return ConflictFailure(
          message: 'This request was already sent with different details.',
          serverCode: code,
          cause: error,
        );
      case 'operation_in_progress':
        return OperationInProgressFailure(
          message: 'That request is still being processed.',
          cause: error,
        );
      case 'clock_skew_exceeded':
        return ClockSkewFailure(
          message:
              "This device's clock is wrong, so the server rejected the "
              'time. Fix the device clock.',
          cause: error,
        );
      case 'stale_operation':
        return StaleClientFailure(
          message: 'This action was queued too long ago to apply safely.',
          cause: error,
        );
      case 'validation_failed':
        return ValidationFailure(message: 'Some details were not accepted.', cause: error);
    }

    // No application code: fall back to SQLSTATE. Reaching here for a mutation
    // usually means an RPC raised a bare exception instead of one of the
    // documented codes.
    switch (error.code) {
      case _sqlStateInsufficientPrivilege:
        return PermissionFailure(message: 'You do not have permission to do that.', cause: error);
      case _sqlStateUniqueViolation:
      case _sqlStateForeignKeyViolation:
      case _sqlStateCheckViolation:
      case _sqlStateNotNullViolation:
        return ConflictFailure(
          message: 'That change conflicts with existing data.',
          serverCode: error.code,
          cause: error,
        );
    }

    final status = int.tryParse(error.code ?? '');
    if (status != null) {
      if (status == 401 || status == 403) {
        return PermissionFailure(message: 'You do not have permission to do that.', cause: error);
      }
      if (status == 404) {
        return NotFoundFailure(message: 'That item no longer exists.', cause: error);
      }
      if (status == 409) {
        return ConflictFailure(
          message: 'Someone else changed this first. Refresh and try again.',
          serverCode: error.code,
          cause: error,
        );
      }
      if (status >= 500) {
        return NetworkFailure(
          message: 'The server had a problem. Retry in a moment.',
          serverCode: error.code,
          cause: error,
        );
      }
      if (status >= 400) {
        return ValidationFailure(
          message: 'The server rejected that request.',
          serverCode: error.code,
          cause: error,
        );
      }
    }

    return UnknownFailure(message: 'Something went wrong.', serverCode: error.code, cause: error);
  }

  /// Recovers the `API.md` §1 code from a PostgrestException.
  ///
  /// `RAISE EXCEPTION ... USING ERRCODE = 'P0001'` puts the application code in
  /// the message, so both shapes are checked.
  static String? _applicationCode(PostgrestException error) {
    const known = <String>{
      'insufficient_privilege',
      'not_found',
      'invalid_state',
      'conflict',
      'idempotency_key_reuse',
      'operation_in_progress',
      'clock_skew_exceeded',
      'stale_operation',
      'validation_failed',
    };

    final code = error.code;
    if (code != null && known.contains(code)) return code;

    if (code == null || code == _sqlStateRaiseException) {
      final message = error.message.trim();
      for (final candidate in known) {
        if (message == candidate || message.startsWith('$candidate:')) {
          return candidate;
        }
      }
    }
    return null;
  }
}

/// The shared mapper instance. Stateless, so a const singleton is enough.
const FailureMapper failureMapper = FailureMapper();
