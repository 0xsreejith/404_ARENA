import 'package:arena_os/features/permissions/permission_gate.dart';
import 'package:flutter/material.dart';

/// Legacy name — prefer [PermissionGate].
typedef PermissionGuard = PermissionGate;

/// Convenience constructor matching the older API shape.
class PermissionGuardBox extends StatelessWidget {
  const PermissionGuardBox({
    required this.requiredPermission,
    required this.child,
    this.fallback,
    super.key,
  });

  final String requiredPermission;
  final Widget child;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: requiredPermission,
      fallback: fallback,
      child: child,
    );
  }
}
