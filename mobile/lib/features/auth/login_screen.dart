import 'package:arena_os/app/theme/arena_colors.dart';
import 'package:arena_os/features/auth/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onLoginPressed() {
    if (_formKey.currentState?.validate() ?? false) {
      ref.read(authControllerProvider.notifier).signIn(
            _emailController.text.trim(),
            _passwordController.text,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isAuthenticating = authState.status == AuthStatus.authenticating;

    return Scaffold(
      backgroundColor: const Color(0xFF07070A),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(28.0),
                decoration: BoxDecoration(
                  color: const Color(0xFF11131A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7CFF4F).withValues(alpha: 0.05),
                      blurRadius: 24,
                      spreadRadius: 2,
                    )
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Cyber Brand Badge & Header
                      Center(
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: const Color(0xFF7CFF4F).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF7CFF4F)),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF7CFF4F).withValues(alpha: 0.3),
                                blurRadius: 16,
                              )
                            ],
                          ),
                          child: const Center(
                            child: Text(
                              'AOS',
                              style: TextStyle(
                                color: Color(0xFF7CFF4F),
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Center(
                        child: Text(
                          'ARENA OS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2.0,
                          ),
                        ),
                      ),
                      const Center(
                        child: Text(
                          'COMMERCIAL VENUE OPERATING SYSTEM',
                          style: TextStyle(
                            color: Color(0x73E8EAF0),
                            fontSize: 10,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      if (authState.errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: ArenaColors.danger.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: ArenaColors.danger),
                          ),
                          child: Text(
                            authState.errorMessage!,
                            style: const TextStyle(color: ArenaColors.danger, fontSize: 13),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Email Field
                      TextFormField(
                        controller: _emailController,
                        style: const TextStyle(color: Colors.white),
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'STAFF EMAIL',
                          labelStyle: const TextStyle(color: Color(0x73E8EAF0), fontSize: 12),
                          filled: true,
                          fillColor: const Color(0xFF181B22),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFF7CFF4F)),
                          ),
                          prefixIcon: const Icon(Icons.email_outlined, color: Color(0x73E8EAF0)),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Email is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Password Field
                      TextFormField(
                        controller: _passwordController,
                        style: const TextStyle(color: Colors.white),
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'PASSWORD',
                          labelStyle: const TextStyle(color: Color(0x73E8EAF0), fontSize: 12),
                          filled: true,
                          fillColor: const Color(0xFF181B22),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFF7CFF4F)),
                          ),
                          prefixIcon: const Icon(Icons.lock_outline, color: Color(0x73E8EAF0)),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Password is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),

                      // Sign In Button
                      ElevatedButton(
                        onPressed: isAuthenticating ? null : _onLoginPressed,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7CFF4F),
                          foregroundColor: const Color(0xFF07070A),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 4,
                        ),
                        child: isAuthenticating
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF07070A),
                                ),
                              )
                            : const Text(
                                'AUTHENTICATE STAFF',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  letterSpacing: 1.2,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
