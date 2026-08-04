import 'package:arena_os/core/config/env_config.dart';
import 'package:arena_os/core/logging/app_logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Initialises the Supabase client for exactly one environment (D34).
///
/// `supabase_flutter` is the only transport (D24): Auth, PostgREST reads under
/// RLS, and RPC for every mutation. There is no Dio, because there is no
/// separate REST backend.
///
/// The client is created from a validated [EnvConfig], so by the time this runs
/// the URL is a real https endpoint and the key has already been proven to be
/// an anon key rather than a `service_role` key (D37).
class SupabaseBootstrap {
  const SupabaseBootstrap._();

  static Future<SupabaseClient> initialise({
    required EnvConfig config,
    required AppLogger logger,
  }) async {
    await Supabase.initialize(
      url: config.supabaseUrl,
      // The SDK now calls this the publishable key; the specification and the
      // Supabase dashboard both still say "anon key". Same value, and
      // EnvConfig has already proven it is not a service_role or secret key.
      publishableKey: config.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        // Staff sign in on a shared counter device and stay signed in across
        // restarts; the session is refreshed rather than re-entered (M2).
        autoRefreshToken: true,
      ),
      // Realtime is designed for but not enabled in P0 (D23). Repository reads
      // are Stream-shaped so it can be switched on later without touching
      // controllers or UI. Keeping the heartbeat low avoids paying for a
      // connection nothing subscribes to.
      realtimeClientOptions: const RealtimeClientOptions(logLevel: RealtimeLogLevel.error),
      debug: !config.env.isProduction,
    );

    // Never logs the key or the full URL — host only (D37).
    logger.info('Supabase client initialised', fields: config.toRedactedMap());

    return Supabase.instance.client;
  }
}
