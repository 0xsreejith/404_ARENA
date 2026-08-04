import 'package:arena_os/app/theme/arena_colors.dart';
import 'package:arena_os/features/auth/auth_controller.dart';
import 'package:arena_os/features/devices/device_repository.dart';
import 'package:arena_os/features/lobby_ui/lobby_fonts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// D18: client has not successfully contacted the server for 24h.
class StaleScreen extends ConsumerWidget {
  const StaleScreen({super.key});

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
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(
                          Icons.cloud_off,
                          color: ArenaColors.warning,
                          size: 40,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'CONNECTION STALE',
                          style: LobbyFonts.display(
                            color: ArenaColors.textPrimary,
                            size: 22,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'This device has not synced with the server for more than '
                          '24 hours. Mutations are blocked until contact is restored '
                          '(D18). Pull to refresh after network is back.',
                          style: LobbyFonts.body(
                            color: ArenaColors.textMuted,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: ArenaColors.accent,
                            foregroundColor: ArenaColors.background,
                            minimumSize: const Size.fromHeight(52),
                          ),
                          onPressed: () async {
                            await ref
                                .read(authControllerProvider.notifier)
                                .loadUserContext();
                            ref.read(lastServerContactProvider.notifier).touch();
                            if (context.mounted) context.go('/arenas');
                          },
                          child: Text(
                            'RETRY SYNC',
                            style: LobbyFonts.display(
                              color: ArenaColors.background,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
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
