import 'package:arena_os/app/router.dart';
import 'package:arena_os/app/theme/arena_theme.dart';
import 'package:arena_os/core/errors/app_failure.dart';
import 'package:arena_os/features/tenant/tenant_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Application shell — navigation is owned by [goRouterProvider].
class ArenaApp extends ConsumerWidget {
  const ArenaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    final brandName = ref.watch(tenantControllerProvider.select((t) => t.brandName));

    return MaterialApp.router(
      title: brandName,
      debugShowCheckedModeBanner: false,
      theme: ArenaTheme.dark(),
      darkTheme: ArenaTheme.dark(),
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}

/// Shown when the build carries no valid environment configuration.
class ConfigurationErrorApp extends StatelessWidget {
  const ConfigurationErrorApp({required this.failure, this.remedy, super.key});

  final ConfigurationFailure failure;
  final String? remedy;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Arena OS',
      debugShowCheckedModeBanner: false,
      theme: ArenaTheme.dark(),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Icon(Icons.error_outline, color: Color(0xFFFF4444), size: 40),
                    const SizedBox(height: 16),
                    Text('Build is not configured', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    Text(failure.message, style: Theme.of(context).textTheme.bodyMedium),
                    if (remedy != null) ...<Widget>[
                      const SizedBox(height: 16),
                      Text(
                        remedy!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF9AA3B8),
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
