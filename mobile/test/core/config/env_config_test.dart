import 'dart:convert';

import 'package:arena_os/core/config/arena_env.dart';
import 'package:arena_os/core/config/env_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds an unsigned JWT with the given `role` claim.
///
/// Structurally identical to a Supabase legacy key. The signature is a
/// throwaway literal — this is not a credential, and the validator does not
/// verify signatures (it is a footgun-guard, not authentication).
String jwtWithRole(String role) {
  String segment(Map<String, Object?> claims) =>
      base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '');
  final header = segment(<String, Object?>{'alg': 'HS256', 'typ': 'JWT'});
  final payload = segment(<String, Object?>{
    'iss': 'supabase',
    'ref': 'examplerefexample',
    'role': role,
    'iat': 1700000000,
    'exp': 2000000000,
  });
  return '$header.$payload.not-a-real-signature';
}

Map<String, String> defines({
  String env = 'development',
  String url = 'https://example-dev.supabase.co',
  String? anonKey,
  String allowProdDebug = '',
}) => <String, String>{
  'ARENA_ENV': env,
  'SUPABASE_URL': url,
  'SUPABASE_ANON_KEY': anonKey ?? jwtWithRole('anon'),
  'ARENA_ALLOW_PRODUCTION_DEBUG': allowProdDebug,
};

void main() {
  group('ArenaEnv', () {
    test('parses exactly the three project names', () {
      expect(ArenaEnv.tryParse('development'), ArenaEnv.development);
      expect(ArenaEnv.tryParse('staging'), ArenaEnv.staging);
      expect(ArenaEnv.tryParse('production'), ArenaEnv.production);
    });

    test('rejects anything else — there is no fourth environment (D34)', () {
      for (final bad in <String?>[null, '', 'dev', 'prod', 'local', 'test']) {
        expect(ArenaEnv.tryParse(bad), isNull, reason: 'should reject "$bad"');
      }
    });

    test('only production is production, and only it forbids fixtures (D33)', () {
      expect(ArenaEnv.production.isProduction, isTrue);
      expect(ArenaEnv.production.allowsFixtureData, isFalse);
      expect(ArenaEnv.development.allowsFixtureData, isTrue);
      expect(ArenaEnv.staging.allowsFixtureData, isTrue);
    });
  });

  group('EnvConfig.resolve — a build proves which project it belongs to', () {
    test('accepts a complete development configuration', () {
      final config = EnvConfig.resolve(defines(), isDebugBuild: true);
      expect(config.env, ArenaEnv.development);
      expect(config.supabaseUrl, 'https://example-dev.supabase.co');
    });

    test('rejects a missing or unknown environment', () {
      expect(
        () => EnvConfig.resolve(defines(env: ''), isDebugBuild: true),
        throwsA(isA<EnvConfigException>()),
      );
      expect(
        () => EnvConfig.resolve(defines(env: 'qa'), isDebugBuild: true),
        throwsA(isA<EnvConfigException>()),
      );
    });

    test('rejects a missing URL or key — there is no default project', () {
      expect(
        () => EnvConfig.resolve(defines(url: ''), isDebugBuild: true),
        throwsA(isA<EnvConfigException>()),
      );
      expect(
        () => EnvConfig.resolve(defines(anonKey: ''), isDebugBuild: true),
        throwsA(isA<EnvConfigException>()),
      );
    });

    test('rejects a non-https or malformed URL', () {
      for (final bad in <String>[
        'http://example.supabase.co',
        'example.supabase.co',
        'https://',
        'not a url',
      ]) {
        expect(
          () => EnvConfig.resolve(defines(url: bad), isDebugBuild: true),
          throwsA(isA<EnvConfigException>()),
          reason: 'should reject "$bad"',
        );
      }
    });

    test('allows http only for the local development stack on loopback', () {
      final config = EnvConfig.resolve(
        defines(url: 'http://127.0.0.1:54321'),
        isDebugBuild: true,
      );
      expect(config.supabaseUrl, 'http://127.0.0.1:54321');

      expect(
        () => EnvConfig.resolve(
          defines(env: 'production', url: 'http://127.0.0.1:54321'),
          isDebugBuild: false,
        ),
        throwsA(isA<EnvConfigException>()),
      );
    });

    test('rejects the committed placeholder so an example file cannot ship', () {
      expect(
        () => EnvConfig.resolve(
          defines(url: 'https://${EnvConfig.placeholderToken}.supabase.co'),
          isDebugBuild: true,
        ),
        throwsA(isA<EnvConfigException>()),
      );
      expect(
        () => EnvConfig.resolve(defines(anonKey: EnvConfig.placeholderToken), isDebugBuild: true),
        throwsA(isA<EnvConfigException>()),
      );
    });
  });

  group('service_role guard (D37)', () {
    test('rejects a legacy service_role JWT', () {
      expect(
        () => EnvConfig.resolve(defines(anonKey: jwtWithRole('service_role')), isDebugBuild: true),
        throwsA(
          isA<EnvConfigException>().having((e) => e.message, 'message', contains('service_role')),
        ),
      );
    });

    test('rejects any non-anon role claim', () {
      for (final role in <String>['service_role', 'authenticated', 'postgres', 'supabase_admin']) {
        expect(
          () => EnvConfig.resolve(defines(anonKey: jwtWithRole(role)), isDebugBuild: true),
          throwsA(isA<EnvConfigException>()),
          reason: 'should reject role "$role"',
        );
      }
    });

    test('rejects a current-format secret key', () {
      expect(
        () => EnvConfig.resolve(defines(anonKey: 'sb_secret_abcdef0123456789'), isDebugBuild: true),
        throwsA(isA<EnvConfigException>()),
      );
    });

    test('accepts a current-format publishable key', () {
      final config = EnvConfig.resolve(
        defines(anonKey: 'sb_publishable_abcdef0123456789'),
        isDebugBuild: true,
      );
      expect(config.supabaseAnonKey, startsWith('sb_publishable_'));
    });

    test('rejects a key that is neither format', () {
      expect(
        () => EnvConfig.resolve(defines(anonKey: 'plain-string-key'), isDebugBuild: true),
        throwsA(isA<EnvConfigException>()),
      );
    });
  });

  group('production-in-debug guard (D34)', () {
    test('refuses a debug build against production by default', () {
      expect(
        () => EnvConfig.resolve(
          defines(env: 'production', url: 'https://example-prod.supabase.co'),
          isDebugBuild: true,
        ),
        throwsA(
          isA<EnvConfigException>().having((e) => e.message, 'message', contains('production')),
        ),
      );
    });

    test('allows a release build against production', () {
      final config = EnvConfig.resolve(
        defines(env: 'production', url: 'https://example-prod.supabase.co'),
        isDebugBuild: false,
      );
      expect(config.env, ArenaEnv.production);
    });

    test('allows a debug build only when deliberately acknowledged', () {
      final config = EnvConfig.resolve(
        defines(env: 'production', url: 'https://example-prod.supabase.co', allowProdDebug: 'true'),
        isDebugBuild: true,
      );
      expect(config.env, ArenaEnv.production);
    });

    test('does not constrain development or staging in debug', () {
      expect(EnvConfig.resolve(defines(env: 'staging'), isDebugBuild: true).env, ArenaEnv.staging);
    });
  });

  group('redacted view', () {
    test('never exposes the key, not even truncated', () {
      final key = jwtWithRole('anon');
      final config = EnvConfig.resolve(defines(anonKey: key), isDebugBuild: true);
      final redacted = config.toRedactedMap();

      expect(redacted['env'], 'development');
      expect(redacted['supabaseHost'], 'example-dev.supabase.co');
      expect(redacted['anonKeyPresent'], isTrue);
      expect(redacted.values.join(' '), isNot(contains(key)));
      expect(config.toString(), isNot(contains(key)));
    });
  });
}
