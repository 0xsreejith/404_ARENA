import 'package:arena_os/features/lobby_ui/lobby_controller.dart';
import 'package:arena_os/features/lobby_ui/screens/login_screen.dart';
import 'package:arena_os/features/lobby_ui/screens/staff_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Visual Lobby OS shell driven by design-fixture data.
///
/// MaterialApp is only for text direction / MediaQuery / theme scaffolding —
/// Lobby screens use custom widgets (no AppBar / NavigationBar chrome).
class LobbyOsApp extends ConsumerWidget {
  const LobbyOsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(lobbyUiProvider.select((s) => s.signedIn));
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF07070A),
        useMaterial3: true,
        splashFactory: NoSplash.splashFactory,
        highlightColor: const Color(0x00000000),
        hoverColor: const Color(0x00000000),
      ),
      home: signedIn ? const StaffShell() : const LoginScreen(),
    );
  }
}
