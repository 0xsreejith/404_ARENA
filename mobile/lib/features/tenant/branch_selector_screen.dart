import 'package:arena_os/features/auth/auth_controller.dart';
import 'package:arena_os/features/lobby_ui/lobby_fonts.dart';
import 'package:arena_os/features/tenant/tenant_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BranchSelectorScreen extends ConsumerWidget {
  const BranchSelectorScreen({required this.onBranchSelected, super.key});

  final VoidCallback onBranchSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantState = ref.watch(tenantControllerProvider);
    final arenas = tenantState.accessibleArenas;
    final primaryColor = tenantState.primaryColor;

    return Scaffold(
      backgroundColor: const Color(0xFF07070A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0D13),
        title: Text(
          'SELECT BRANCH',
          style: LobbyFonts.display(
            color: Colors.white,
            size: 16,
            letterSpacing: 1.5,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white70),
            onPressed: () {
              ref.read(authControllerProvider.notifier).signOut();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ACCESSIBLE VENUES & BRANCHES',
                style: LobbyFonts.display(
                  color: const Color(0x73E8EAF0),
                  size: 12,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  itemCount: arenas.length,
                  separatorBuilder: (BuildContext context, int index) => const SizedBox(height: 12),
                  itemBuilder: (BuildContext context, int index) {
                    final arena = arenas[index];
                    final isSelected = tenantState.selectedArena?['id'] == arena['id'];
                    final roleMap = arena['role'] as Map<String, dynamic>?;
                    final roleName = roleMap?['name'] as String? ?? 'Staff';
                    final currency = arena['currency'] as String? ?? 'INR';
                    final timezone = arena['timezone'] as String? ?? 'Asia/Kolkata';

                    return InkWell(
                      onTap: () {
                        ref.read(tenantControllerProvider.notifier).selectArena(arena);
                        onBranchSelected();
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFF11131A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? primaryColor : Colors.white.withValues(alpha: 0.08),
                            width: isSelected ? 2 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: primaryColor.withValues(alpha: 0.15),
                                    blurRadius: 16,
                                  )
                                ]
                              : const [],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: primaryColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
                              ),
                              child: Icon(
                                Icons.storefront,
                                color: primaryColor,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    arena['name'] as String? ?? 'Branch',
                                    style: LobbyFonts.body(
                                      color: Colors.white,
                                      size: 16,
                                      weight: FontWeight.bold,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Role: $roleName • $currency ($timezone)',
                                    style: LobbyFonts.body(
                                      color: const Color(0x73E8EAF0),
                                      size: 12,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              Icon(Icons.check_circle, color: primaryColor)
                            else
                              const Icon(Icons.chevron_right, color: Color(0x73E8EAF0)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
