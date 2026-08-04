import 'package:arena_os/core/permissions/can.dart';
import 'package:arena_os/features/auth/auth_controller.dart';
import 'package:arena_os/features/auth/login_screen.dart';
import 'package:arena_os/features/checkout/checkout_screen.dart';
import 'package:arena_os/features/devices/device_repository.dart';
import 'package:arena_os/features/floor/floor_screen.dart';
import 'package:arena_os/features/shell/no_access_screen.dart';
import 'package:arena_os/features/shell/staff_shell.dart';
import 'package:arena_os/features/shell/stale_screen.dart';
import 'package:arena_os/features/shift/shift_screen.dart';
import 'package:arena_os/features/tenant/branch_selector_screen.dart';
import 'package:arena_os/features/tenant/tenant_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Single redirect state machine (`ARCHITECTURE.md` §8).
///
/// Order: session → arena → staleness → permission → destination.
/// Only production routes are registered — unfinished modules are omitted
/// from navigation until their epics land (no demo/mock destinations).
final goRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.listen(tenantControllerProvider, (_, _) => refresh.value++);
  ref.listen(lastServerContactProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/sign-in',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final tenant = ref.read(tenantControllerProvider);
      final loc = state.matchedLocation;

      if (auth.status == AuthStatus.authenticating) {
        return null;
      }

      final signedIn = auth.status == AuthStatus.authenticated;
      final onSignIn = loc == '/sign-in';

      if (!signedIn) {
        return onSignIn ? null : '/sign-in';
      }

      if (onSignIn) {
        if (tenant.selectedArena == null) return '/arenas';
        if (ref.read(lastServerContactProvider.notifier).isStale) return '/stale';
        return firstPermittedPath(tenant.permissions);
      }

      if (tenant.selectedArena == null && loc != '/arenas') {
        return '/arenas';
      }

      if (tenant.selectedArena != null &&
          ref.read(lastServerContactProvider.notifier).isStale &&
          loc != '/stale') {
        return '/stale';
      }

      if (loc == '/floor' &&
          !tenant.hasPermission('session.view') &&
          !tenant.hasPermission('station.view')) {
        return '/no-access';
      }

      if (loc.startsWith('/checkout') && !tenant.hasPermission('payment.create')) {
        return '/no-access';
      }

      if (loc == '/shift' && !tenant.hasPermission('shift.view')) {
        return '/no-access';
      }

      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/sign-in',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/arenas',
        builder: (context, state) => BranchSelectorScreen(
          onBranchSelected: () async {
            final arena = ref.read(tenantControllerProvider).selectedArena;
            final arenaId = arena?['id'] as String?;
            if (arenaId != null) {
              try {
                await ref.read(deviceRepositoryProvider).register(
                      arenaId: arenaId,
                      deviceName: 'Staff device',
                      appVersion: '0.1.0',
                    );
              } on Object {
                // Telemetry must not block entry; server still enforces ops.
              }
              ref.read(lastServerContactProvider.notifier).touch();
            }
            if (context.mounted) {
              context.go(firstPermittedPath(ref.read(tenantControllerProvider).permissions));
            }
          },
        ),
      ),
      GoRoute(
        path: '/stale',
        builder: (context, state) => const StaleScreen(),
      ),
      GoRoute(
        path: '/no-access',
        builder: (context, state) => const NoAccessScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => StaffShell(child: child),
        routes: <RouteBase>[
          GoRoute(
            path: '/floor',
            builder: (context, state) => const FloorScreen(),
          ),
          GoRoute(
            path: '/shift',
            builder: (context, state) => const ShiftScreen(),
          ),
          GoRoute(
            path: '/checkout/:orderId',
            builder: (context, state) {
              final orderId = state.pathParameters['orderId']!;
              final sessionId = state.uri.queryParameters['sessionId'];
              final memberName = state.uri.queryParameters['memberName'];
              return CheckoutScreen(
                orderId: orderId,
                sessionId: sessionId,
                memberName: memberName,
              );
            },
          ),
        ],
      ),
    ],
  );
});
