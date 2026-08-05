import 'package:arena_os/features/tenant/tenant_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True when the selected arena grants [permissionCode].
///
/// Authorise by permission **code**, never by role name (`PERMISSIONS.md`).
final canProvider = Provider.family<bool, String>((ref, permissionCode) {
  return ref.watch(tenantControllerProvider).hasPermission(permissionCode);
});

/// Destinations that exist in the production staff app today.
///
/// Unfinished modules are not listed — permission reduction hides them by
/// absence, not by stub screens.
String firstPermittedPath(List<String> permissions) {
  if (permissions.contains('session.view') || permissions.contains('station.view')) {
    return '/floor';
  }
  if (permissions.contains('member.view')) {
    return '/members';
  }
  if (permissions.contains('shift.view')) {
    return '/shift';
  }
  return '/no-access';
}
