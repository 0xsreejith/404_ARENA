import 'package:arena_os/features/auth/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TenantState {
  const TenantState({
    this.selectedArena,
    this.accessibleArenas = const [],
  });

  final Map<String, dynamic>? selectedArena;
  final List<Map<String, dynamic>> accessibleArenas;

  Color get primaryColor {
    final branding = selectedArena?['branding'] as Map<String, dynamic>?;
    final hex = branding?['primary_color'] as String? ?? '#7CFF4F';
    return _parseColor(hex, const Color(0xFF7CFF4F));
  }

  Color get accentColor {
    final branding = selectedArena?['branding'] as Map<String, dynamic>?;
    final hex = branding?['accent_color'] as String? ?? '#00F0FF';
    return _parseColor(hex, const Color(0xFF00F0FF));
  }

  String get brandName {
    final branding = selectedArena?['branding'] as Map<String, dynamic>?;
    return branding?['brand_name'] as String? ??
        selectedArena?['name'] as String? ??
        'Arena OS';
  }

  /// ISO 4217 from `arenas.currency` — never hardcoded (D31).
  String get currency => selectedArena?['currency'] as String? ?? 'INR';

  List<String> get permissions {
    final list = selectedArena?['permissions'] as List<dynamic>?;
    if (list == null) return const [];
    return list.map((e) => e.toString()).toList();
  }

  bool hasPermission(String code) => permissions.contains(code);

  static Color _parseColor(String hex, Color fallback) {
    try {
      final buffer = StringBuffer();
      if (hex.length == 6 || hex.length == 7) buffer.write('ff');
      buffer.write(hex.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  TenantState copyWith({
    Map<String, dynamic>? selectedArena,
    List<Map<String, dynamic>>? accessibleArenas,
  }) {
    return TenantState(
      selectedArena: selectedArena ?? this.selectedArena,
      accessibleArenas: accessibleArenas ?? this.accessibleArenas,
    );
  }
}

final tenantControllerProvider = NotifierProvider<TenantControllerNotifier, TenantState>(TenantControllerNotifier.new);

class TenantControllerNotifier extends Notifier<TenantState> {
  @override
  TenantState build() {
    final authState = ref.watch(authControllerProvider);
    final rawContext = authState.userContext;

    if (rawContext == null) {
      return const TenantState();
    }

    final rawArenas = rawContext['arenas'] as List<dynamic>?;
    if (rawArenas == null || rawArenas.isEmpty) {
      return const TenantState();
    }

    final arenas = rawArenas.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final selected = state.selectedArena ?? arenas.first;

    return TenantState(
      accessibleArenas: arenas,
      selectedArena: selected,
    );
  }

  void selectArena(Map<String, dynamic> arena) {
    state = state.copyWith(selectedArena: arena);
  }
}
