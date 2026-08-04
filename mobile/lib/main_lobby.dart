import 'package:arena_os/features/lobby_ui/lobby_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Design-parity entrypoint for Lobby OS (no Supabase bootstrap).
///
///   flutter run -t lib/main_lobby.dart
///
/// Leaves `main_development.dart` / auth epic bootstrapping untouched.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: LobbyOsApp()));
}
