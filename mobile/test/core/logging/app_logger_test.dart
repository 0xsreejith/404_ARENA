import 'package:arena_os/core/config/arena_env.dart';
import 'package:arena_os/core/logging/app_logger.dart';
import 'package:arena_os/core/logging/redaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LogRedactor — credentials (D37)', () {
    const redactor = LogRedactor();

    test('scrubs a JWT anywhere in free text', () {
      const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYW5vbiJ9.abcdefghijk';
      final output = redactor.redactText('failed with key $jwt at boot');
      expect(output, isNot(contains(jwt)));
      expect(output, contains(LogRedactor.redacted));
    });

    test('scrubs both current-format key shapes', () {
      final secret = redactor.redactText('key=sb_secret_abc123XYZ_-def');
      final publishable = redactor.redactText('key=sb_publishable_abc123XYZ');
      expect(secret, isNot(contains('sb_secret_abc123XYZ')));
      expect(publishable, isNot(contains('sb_publishable_abc123XYZ')));
    });

    test('scrubs sensitive field names whatever the value', () {
      final fields = redactor.redactFields(<String, Object?>{
        'anonKey': 'anything',
        'authorization': 'Bearer abc',
        'staff_pin_hash': 'hash',
        'refreshToken': 'r',
        'apiKey': 'k',
      });
      for (final value in fields.values) {
        expect(value, LogRedactor.redacted);
      }
    });
  });

  group('LogRedactor — member PII (D19)', () {
    const redactor = LogRedactor();

    test('scrubs phone, name, dob, and notes by field name', () {
      final fields = redactor.redactFields(<String, Object?>{
        'phone': '+919876543210',
        'memberPhone': '9876543210',
        'full_name': 'A Real Person',
        'displayName': 'A Real Person',
        'dob': '1990-01-01',
        'notes': 'anything at all',
      });
      for (final entry in fields.entries) {
        expect(entry.value, LogRedactor.redacted, reason: entry.key);
      }
    });

    test('keeps the member id — that is what we log instead', () {
      final fields = redactor.redactFields(<String, Object?>{
        'memberId': '11111111-2222-3333-4444-555555555555',
        'arenaId': '66666666-7777-8888-9999-000000000000',
      });
      expect(fields['memberId'], isNot(LogRedactor.redacted));
      expect(fields['arenaId'], isNot(LogRedactor.redacted));
    });

    test('scrubs a phone number embedded in free text', () {
      for (final phone in <String>[
        '+919876543210',
        '9876543210',
        '+91 98765 43210',
        '098765-43210',
      ]) {
        final output = redactor.redactText('member $phone could not be found');
        expect(output, isNot(contains(phone)), reason: phone);
      }
    });

    test('recurses into nested maps and lists', () {
      final fields = redactor.redactFields(<String, Object?>{
        'session': <String, Object?>{
          'id': 'abc',
          'member': <String, Object?>{'phone': '+919876543210'},
        },
        'contacts': <Object?>[
          <String, Object?>{'phone': '+919876543210'},
        ],
      });
      final rendered = fields.toString();
      expect(rendered, isNot(contains('9876543210')));
      expect(rendered, contains(LogRedactor.redacted));
    });

    test('scrubs an unknown object stringified into a field', () {
      final fields = redactor.redactFields(<String, Object?>{
        'entity': _MemberLike('+919876543210'),
      });
      expect(fields['entity'].toString(), isNot(contains('9876543210')));
    });

    test('leaves ordinary values alone', () {
      final fields = redactor.redactFields(<String, Object?>{
        'stationName': 'PC-04',
        'playerCount': 2,
        'live': true,
        'elapsedSeconds': 7260,
      });
      expect(fields['stationName'], 'PC-04');
      expect(fields['playerCount'], 2);
      expect(fields['live'], true);
      expect(fields['elapsedSeconds'], 7260);
    });
  });

  group('AppLogger', () {
    test('redaction is not opt-in — it applies to message, fields, and error', () {
      final sink = MemoryLogSink();
      final logger = AppLogger(name: 'test', minimumLevel: LogLevel.debug, sink: sink);

      logger.error(
        'sign-in failed for +919876543210',
        fields: <String, Object?>{'phone': '+919876543210'},
        error: Exception('token eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYW5vbiJ9.s1gnatur3 rejected'),
      );

      final record = sink.records.single;
      expect(record.message, isNot(contains('9876543210')));
      expect(record.fields['phone'], LogRedactor.redacted);
      expect(record.error.toString(), isNot(contains('eyJhbGciOiJIUzI1NiJ9')));
    });

    test('production suppresses debug and info detail', () {
      final sink = MemoryLogSink();
      final logger = AppLogger.forEnvironment(ArenaEnv.production, sink: sink);

      logger
        ..debug('floor refreshed')
        ..info('session started')
        ..warn('sync retry')
        ..error('settlement failed');

      expect(sink.records.map((r) => r.level), <LogLevel>[LogLevel.warn, LogLevel.error]);
    });

    test('development keeps everything', () {
      final sink = MemoryLogSink();
      final logger = AppLogger.forEnvironment(ArenaEnv.development, sink: sink);
      logger.debug('floor refreshed');
      expect(sink.records, hasLength(1));
    });

    test('child loggers namespace and inherit the level', () {
      final sink = MemoryLogSink();
      final logger = AppLogger.forEnvironment(ArenaEnv.production, sink: sink).child('sync');
      logger
        ..debug('suppressed')
        ..error('surfaced');
      expect(sink.records.single.name, 'arena.sync');
    });
  });
}

class _MemberLike {
  const _MemberLike(this.phone);

  final String phone;

  @override
  String toString() => 'Member(phone: $phone)';
}
