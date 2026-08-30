import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_providers.dart';
import '../providers/auth_state.dart';
import 'biometric_lock_screen.dart';
import 'login_signup_screen.dart';
import 'vault_list_screen.dart';

/// Root navigation gate managing screen display based on AuthStatus (Task 10.1)
class AppLockGate extends ConsumerWidget {
  const AppLockGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    // Watch auto-lock service when authenticated
    if (authState.isAuthenticated) {
      ref.watch(autoLockServiceProvider);
    }

    final child = switch (authState.status) {
      AuthStatus.authenticated => const VaultListScreen(),
      AuthStatus.locked => const BiometricLockScreen(),
      AuthStatus.unauthenticated ||
      AuthStatus.authenticating ||
      AuthStatus.error ||
      AuthStatus.initial =>
        const LoginSignupScreen(),
    };

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        if (authState.isAuthenticated) {
          ref.read(autoLockServiceProvider).resetInactivityTimer();
        }
      },
      onPointerMove: (_) {
        if (authState.isAuthenticated) {
          ref.read(autoLockServiceProvider).resetInactivityTimer();
        }
      },
      child: child,
    );
  }
}
