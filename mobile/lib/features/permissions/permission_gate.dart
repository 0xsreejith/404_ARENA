import 'package:arena_os/core/permissions/can.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Renders [child] only when the selected arena grants [permission].
///
/// Prefer this over scattering `if (hasPermission)` in screens
/// (`ARCHITECTURE.md` §8, M2).
class PermissionGate extends ConsumerWidget {
  const PermissionGate({
    required this.permission,
    required this.child,
    this.fallback,
    super.key,
  });

  final String permission;
  final Widget child;
  final Widget? fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref.watch(canProvider(permission));
    if (allowed) return child;
    return fallback ?? const SizedBox.shrink();
  }
}
