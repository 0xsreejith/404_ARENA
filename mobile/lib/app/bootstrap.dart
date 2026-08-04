import 'dart:async';

import 'package:arena_os/app/app.dart';
import 'package:arena_os/core/config/env_config.dart';
import 'package:arena_os/core/errors/app_failure.dart';
import 'package:arena_os/core/logging/app_logger.dart';
import 'package:arena_os/core/supabase/supabase_bootstrap.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Injected dependencies resolved during startup.
///
/// Providers read these rather than reaching for globals, so tests can build an
/// app against a fake environment without touching Supabase.
class AppRuntime {
  const AppRuntime({required this.config, required this.logger, required this.supabase});

  final EnvConfig config;
  final AppLogger logger;
  final SupabaseClient supabase;
}

/// Overridden in [bootstrap]; reading it before startup completes is a bug.
final Provider<AppRuntime> appRuntimeProvider = Provider<AppRuntime>(
  (ref) => throw StateError('appRuntimeProvider was not overridden in bootstrap()'),
);

final Provider<EnvConfig> envConfigProvider = Provider<EnvConfig>(
  (ref) => ref.watch(appRuntimeProvider).config,
);

final Provider<AppLogger> loggerProvider = Provider<AppLogger>(
  (ref) => ref.watch(appRuntimeProvider).logger,
);

final Provider<SupabaseClient> supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => ref.watch(appRuntimeProvider).supabase,
);

/// Single startup path for all three flavours.
///
/// Startup either produces a fully configured runtime or renders a
/// configuration error. It never falls back to a default Supabase project:
/// a build that cannot prove which environment it belongs to must not run
/// (D34).
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  final EnvConfig config;
  try {
    config = EnvConfig.fromCompileTimeDefines(isDebugBuild: kDebugMode);
  } on EnvConfigException catch (error) {
    runApp(
      ConfigurationErrorApp(
        failure: ConfigurationFailure(message: error.message, cause: error),
        remedy: error.remedy,
      ),
    );
    return;
  }

  final logger = AppLogger.forEnvironment(config.env);

  FlutterError.onError = (details) {
    logger.error('Uncaught Flutter error', error: details.exception, stackTrace: details.stack);
  };

  await runZonedGuarded<Future<void>>(
    () async {
      final client = await SupabaseBootstrap.initialise(
        config: config,
        logger: logger.child('supabase'),
      );

      runApp(
        ProviderScope(
          overrides: [
            appRuntimeProvider.overrideWithValue(
              AppRuntime(config: config, logger: logger, supabase: client),
            ),
          ],
          child: const ArenaApp(),
        ),
      );
    },
    (error, stackTrace) =>
        logger.error('Uncaught zone error', error: error, stackTrace: stackTrace),
  );
}
