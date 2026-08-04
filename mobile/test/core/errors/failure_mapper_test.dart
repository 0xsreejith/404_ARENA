import 'dart:async';
import 'dart:io';

import 'package:arena_os/core/errors/app_failure.dart';
import 'package:arena_os/core/errors/failure_mapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

PostgrestException pg({String? code, String message = 'boom'}) =>
    PostgrestException(message: message, code: code);

void main() {
  const mapper = FailureMapper();

  group('API.md §1 error codes map to failures', () {
    final expectations = <String, Matcher>{
      'insufficient_privilege': isA<PermissionFailure>(),
      'not_found': isA<NotFoundFailure>(),
      'invalid_state': isA<ConflictFailure>(),
      'conflict': isA<ConflictFailure>(),
      'idempotency_key_reuse': isA<ConflictFailure>(),
      'operation_in_progress': isA<OperationInProgressFailure>(),
      'clock_skew_exceeded': isA<ClockSkewFailure>(),
      'stale_operation': isA<StaleClientFailure>(),
      'validation_failed': isA<ValidationFailure>(),
    };

    expectations.forEach((code, matcher) {
      test(code, () {
        expect(mapper.map(pg(code: code)), matcher);
      });
    });

    test('a code raised via RAISE EXCEPTION is recovered from the message', () {
      final failure = mapper.map(pg(code: 'P0001', message: 'insufficient_privilege'));
      expect(failure, isA<PermissionFailure>());
    });

    test('a code with a trailing detail is still recognised', () {
      final failure = mapper.map(
        pg(code: 'P0001', message: 'conflict: station already has a live session'),
      );
      expect(failure, isA<ConflictFailure>());
    });
  });

  group('retryability matches OFFLINE.md §5', () {
    test('network, offline, and in-progress are retryable', () {
      expect(const NetworkFailure(message: 'x').retryable, isTrue);
      expect(const OfflineFailure(message: 'x').retryable, isTrue);
      expect(const OperationInProgressFailure(message: 'x').retryable, isTrue);
    });

    test('permission, skew, stale, reuse, and validation are not', () {
      expect(const PermissionFailure(message: 'x').retryable, isFalse);
      expect(const ClockSkewFailure(message: 'x').retryable, isFalse);
      expect(const StaleClientFailure(message: 'x').retryable, isFalse);
      expect(const ValidationFailure(message: 'x').retryable, isFalse);
      expect(
        const ConflictFailure(message: 'x', serverCode: 'idempotency_key_reuse').retryable,
        isFalse,
      );
    });

    test('an unknown failure is never retried against a financial endpoint', () {
      expect(const UnknownFailure(message: 'x').retryable, isFalse);
    });
  });

  group('reachedServer — the UI must not claim an unsent write succeeded', () {
    test('is false only when the request never left the device', () {
      expect(const NetworkFailure(message: 'x').reachedServer, isFalse);
      expect(const OfflineFailure(message: 'x').reachedServer, isFalse);
      expect(const StaleClientFailure(message: 'x').reachedServer, isFalse);
    });

    test('is true when the server answered', () {
      expect(const ConflictFailure(message: 'x').reachedServer, isTrue);
      expect(const PermissionFailure(message: 'x').reachedServer, isTrue);
    });
  });

  group('SQLSTATE fallback', () {
    test('42501 is a permission failure', () {
      expect(mapper.map(pg(code: '42501')), isA<PermissionFailure>());
    });

    test('constraint violations are conflicts', () {
      for (final state in <String>['23505', '23503', '23514', '23502']) {
        expect(mapper.map(pg(code: state)), isA<ConflictFailure>(), reason: state);
      }
    });
  });

  group('HTTP status fallback', () {
    test('401 and 403 are permission failures', () {
      expect(mapper.map(pg(code: '401')), isA<PermissionFailure>());
      expect(mapper.map(pg(code: '403')), isA<PermissionFailure>());
    });

    test('404 is not found, 409 is conflict', () {
      expect(mapper.map(pg(code: '404')), isA<NotFoundFailure>());
      expect(mapper.map(pg(code: '409')), isA<ConflictFailure>());
    });

    test('5xx is a retryable network failure', () {
      final failure = mapper.map(pg(code: '503'));
      expect(failure, isA<NetworkFailure>());
      expect(failure.retryable, isTrue);
    });

    test('other 4xx is a validation failure', () {
      expect(mapper.map(pg(code: '422')), isA<ValidationFailure>());
    });
  });

  group('transport errors', () {
    test('socket and timeout errors are retryable network failures', () {
      expect(mapper.map(const SocketException('down')), isA<NetworkFailure>());
      expect(mapper.map(TimeoutException('slow')), isA<NetworkFailure>());
      expect(mapper.map(const SocketException('down')).retryable, isTrue);
    });

    test('an auth error is a non-retryable auth failure', () {
      final failure = mapper.map(const AuthException('expired'));
      expect(failure, isA<AuthFailure>());
      expect(failure.retryable, isFalse);
    });

    test('an unreadable response is a validation failure', () {
      expect(mapper.map(const FormatException('bad json')), isA<ValidationFailure>());
    });

    test('anything unrecognised becomes UnknownFailure, never a crash', () {
      expect(mapper.map(Object()), isA<UnknownFailure>());
    });

    test('an AppFailure passes through unchanged', () {
      const original = PermissionFailure(message: 'already mapped');
      expect(identical(mapper.map(original), original), isTrue);
    });
  });

  group('messages are for staff, not for engineers', () {
    test('no raw exception text or SQLSTATE reaches the message', () {
      final failures = <AppFailure>[
        mapper.map(pg(code: '23505', message: 'duplicate key value violates unique constraint')),
        mapper.map(pg(code: 'insufficient_privilege')),
        mapper.map(const SocketException('Connection refused')),
      ];
      for (final failure in failures) {
        expect(failure.message, isNot(contains('Exception')));
        expect(failure.message, isNot(contains('23505')));
        expect(failure.message, isNot(contains('violates')));
        expect(failure.message.trim(), isNotEmpty);
      }
    });
  });
}
