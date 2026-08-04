import 'package:arena_os/app/theme/arena_colors.dart';
import 'package:arena_os/features/auth/auth_controller.dart';
import 'package:arena_os/features/lobby_ui/lobby_fonts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Authenticated user has no permission for any shipped staff module.
class NoAccessScreen extends ConsumerWidget {
  const NoAccessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: ArenaColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.lock_outline,
                        color: ArenaColors.danger,
                        size: 40,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'NO ACCESS',
                        style: LobbyFonts.display(
                          color: ArenaColors.textPrimary,
                          size: 22,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Your role has no permissions for the modules available in '
                        'this build. Ask an owner to grant session.view or '
                        'station.view, or switch branch.',
                        textAlign: TextAlign.center,
                        style: LobbyFonts.body(color: ArenaColors.textMuted),
                      ),
                      const SizedBox(height: 24),
                      TextButton(
                        onPressed: () => context.go('/arenas'),
                        child: const Text(
                          'SWITCH BRANCH',
                          style: TextStyle(color: ArenaColors.accent),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          await ref.read(authControllerProvider.notifier).signOut();
                          if (context.mounted) context.go('/sign-in');
                        },
                        child: const Text(
                          'SIGN OUT',
                          style: TextStyle(color: ArenaColors.textMuted),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
