import 'dart:convert';

import 'package:arena_os/core/config/arena_env.dart';

/// Raised when the build was compiled without valid environment values.
///
/// This is deliberately fatal. A misconfigured build that silently falls back
/// to a default would be a build that can point at the wrong Supabase project,
/// which is exactly what D34 exists to prevent.
class EnvConfigException implements Exception {
  const EnvConfigException(this.message, {this.remedy});

  final String message;
  final String? remedy;

  @override
  String toString() =>
      remedy == null ? 'EnvConfigException: $message' : 'EnvConfigException: $message\n$remedy';
}

/// Validated, immutable environment configuration for one build.
///
/// Values arrive via `--dart-define` at build time and are never committed
/// (D34). There are no defaults: a build either carries a complete, valid
/// configuration or it refuses to start.
class EnvConfig {
  const EnvConfig._({required this.env, required this.supabaseUrl, required this.supabaseAnonKey});

  /// Reads the compile-time defines for this build.
  ///
  /// [isDebugBuild] is injected rather than read from `kDebugMode` so that this
  /// file stays free of Flutter imports and the production-in-debug guard is
  /// testable.
  factory EnvConfig.fromCompileTimeDefines({required bool isDebugBuild}) {
    return resolve(const <String, String>{
      _envKey: String.fromEnvironment(_envKey),
      _urlKey: String.fromEnvironment(_urlKey),
      _anonKeyKey: String.fromEnvironment(_anonKeyKey),
      _allowProdDebugKey: String.fromEnvironment(_allowProdDebugKey),
    }, isDebugBuild: isDebugBuild);
  }

  final ArenaEnv env;
  final String supabaseUrl;

  /// The **anon** key, and only ever the anon key.
  ///
  /// It is public by definition and carries no privilege beyond what RLS and
  /// RPC grants allow. [resolve] rejects a `service_role` or secret key
  /// outright (D37).
  final String supabaseAnonKey;

  /// Placeholder token used in the tracked `env/*.json.example` files.
  ///
  /// Real values are never committed, so the examples must be obviously
  /// unusable and must fail loudly rather than reach a network call.
  static const String placeholderToken = 'REPLACE_ME';

  static const String _envKey = 'ARENA_ENV';
  static const String _urlKey = 'SUPABASE_URL';
  static const String _anonKeyKey = 'SUPABASE_ANON_KEY';
  static const String _allowProdDebugKey = 'ARENA_ALLOW_PRODUCTION_DEBUG';

  /// Validates a raw define map. Pure, so every rule below is unit-testable.
  ///
  /// Throws [EnvConfigException] on the first problem, with a remedy the
  /// developer can act on.
  static EnvConfig resolve(Map<String, String> defines, {required bool isDebugBuild}) {
    final rawEnv = defines[_envKey]?.trim() ?? '';
    final env = ArenaEnv.tryParse(rawEnv);
    if (env == null) {
      throw EnvConfigException(
        rawEnv.isEmpty
            ? '$_envKey was not provided.'
            : '$_envKey="$rawEnv" is not a known environment.',
        remedy:
            'Pass --dart-define=$_envKey=<'
            '${ArenaEnv.values.map((e) => e.wireName).join('|')}>, '
            'or use --dart-define-from-file=env/<environment>.json.',
      );
    }

    final url = _requireValue(defines, _urlKey, env);
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.isAbsolute || uri.host.isEmpty || !_isAllowedSupabaseUrl(uri, env)) {
      throw EnvConfigException(
        '$_urlKey must be an absolute https URL (got "$url"). '
        'Local development may use http://127.0.0.1 or http://localhost.',
        remedy:
            'Copy the Project URL from the ${env.wireName} Supabase '
            'project settings, or point development at the local stack '
            '(http://127.0.0.1:54321).',
      );
    }

    final anonKey = _requireValue(defines, _anonKeyKey, env);
    _rejectPrivilegedKey(anonKey, env);

    // Strict separation (D34): production values must not be picked up by an
    // ordinary `flutter run` on a developer machine. Debugging against
    // production has to be a deliberate, visible act.
    if (env.isProduction && isDebugBuild) {
      final acknowledged = defines[_allowProdDebugKey]?.trim().toLowerCase() == 'true';
      if (!acknowledged) {
        throw const EnvConfigException(
          'Refusing to run a debug build against the production Supabase '
          'project.',
          remedy:
              'Build in release mode, or acknowledge deliberately with '
              '--dart-define=$_allowProdDebugKey=true.',
        );
      }
    }

    return EnvConfig._(env: env, supabaseUrl: url, supabaseAnonKey: anonKey);
  }

  /// Remote projects must be https. The local Supabase CLI stack is http on
  /// loopback only, and only for the development flavour.
  static bool _isAllowedSupabaseUrl(Uri uri, ArenaEnv env) {
    if (uri.scheme == 'https') return true;
    if (uri.scheme != 'http') return false;
    if (!env.allowsFixtureData) return false;
    return uri.host == '127.0.0.1' || uri.host == 'localhost';
  }

  static String _requireValue(Map<String, String> defines, String key, ArenaEnv env) {
    final value = defines[key]?.trim() ?? '';
    if (value.isEmpty) {
      throw EnvConfigException(
        '$key was not provided for ${env.wireName}.',
        remedy:
            'Pass --dart-define-from-file=env/${env.wireName}.json '
            '(copy env/${env.wireName}.json.example and fill it in). '
            'Never commit the filled-in file.',
      );
    }
    if (value.contains(placeholderToken)) {
      throw EnvConfigException(
        '$key still contains the $placeholderToken placeholder.',
        remedy:
            'Fill in env/${env.wireName}.json with the real values from '
            'the ${env.wireName} Supabase project.',
      );
    }
    return value;
  }

  /// Rejects any credential that is more than a public anon key (D37).
  ///
  /// Two key formats exist. Both are checked, because "we only ever paste the
  /// anon key" is a habit and this is a control.
  static void _rejectPrivilegedKey(String key, ArenaEnv env) {
    const remedy =
        'Use the anon / publishable key. The service_role key '
        'bypasses RLS entirely and must never reach Flutter, a device, a log, '
        'or CI (D37, SECURITY.md §11).';

    // Current format: sb_publishable_… (safe) / sb_secret_… (forbidden).
    if (key.startsWith('sb_secret_')) {
      throw const EnvConfigException(
        'SUPABASE_ANON_KEY is a secret key (sb_secret_…).',
        remedy: remedy,
      );
    }
    if (key.startsWith('sb_publishable_')) return;

    // Legacy format: a JWT whose `role` claim states the privilege.
    final role = _jwtRoleClaim(key);
    if (role == null) {
      throw EnvConfigException(
        'SUPABASE_ANON_KEY for ${env.wireName} is not a recognised Supabase '
        'key (expected sb_publishable_… or a JWT).',
        remedy: remedy,
      );
    }
    if (role != 'anon') {
      throw EnvConfigException(
        'SUPABASE_ANON_KEY for ${env.wireName} has role "$role", not "anon".',
        remedy: remedy,
      );
    }
  }

  /// Extracts the `role` claim from an unverified JWT payload.
  ///
  /// The signature is intentionally not verified: this is a local
  /// footgun-guard against pasting the wrong key, not authentication.
  static String? _jwtRoleClaim(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return null;
      final role = decoded['role'];
      return role is String ? role : null;
    } on FormatException {
      return null;
    }
  }

  /// A redacted view safe to write to a log or a crash report.
  ///
  /// The key itself is never included, not even truncated.
  Map<String, Object?> toRedactedMap() => <String, Object?>{
    'env': env.wireName,
    'supabaseHost': Uri.parse(supabaseUrl).host,
    'anonKeyPresent': supabaseAnonKey.isNotEmpty,
  };

  @override
  String toString() => 'EnvConfig(${toRedactedMap()})';
}
