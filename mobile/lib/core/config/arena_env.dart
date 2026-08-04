/// The three deployment environments.
///
/// Each maps one-to-one onto a **separate Supabase project** (D34). PostgreSQL
/// schemas inside a single project are not used as environment isolation, so
/// there is no fourth "shared" value and there never should be.
enum ArenaEnv {
  development('development'),
  staging('staging'),
  production('production');

  const ArenaEnv(this.wireName);

  /// The value passed as `--dart-define=ARENA_ENV=...`.
  final String wireName;

  /// Short label for logs and the debug banner.
  String get shortName => switch (this) {
    ArenaEnv.development => 'dev',
    ArenaEnv.staging => 'stg',
    ArenaEnv.production => 'prod',
  };

  /// Whether this environment talks to real tenants and real money.
  ///
  /// Guards that must never fire in production — verbose logging, fixture
  /// seeding, destructive database scripts — key off this.
  bool get isProduction => this == ArenaEnv.production;

  /// Whether `[FIXTURE]`-prefixed pricing may exist here (D33).
  ///
  /// Production pricing is configured by a tenant user; fixture pricing must
  /// never reach it.
  bool get allowsFixtureData => !isProduction;

  static ArenaEnv? tryParse(String? raw) {
    for (final env in ArenaEnv.values) {
      if (env.wireName == raw) return env;
    }
    return null;
  }
}
