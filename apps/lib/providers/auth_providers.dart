import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/auth_models.dart';
import '../network/dio_client.dart';
import '../services/auth_service.dart';
import '../services/crypto_service.dart';
import '../services/secure_storage_service.dart';
import 'auth_notifier.dart';
import 'auth_state.dart';

// -----------------------------------------------------------------------------
// Service & Network Providers
// -----------------------------------------------------------------------------

/// Provider for SecureStorageService handling tokens, metadata, and session key persistence
final secureStorageServiceProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

/// Provider for configured Dio HTTP client with JWT-attach interceptor
final dioClientProvider = Provider<Dio>((ref) {
  final secureStorage = ref.watch(secureStorageServiceProvider);
  return DioClientFactory.createDio(secureStorage: secureStorage);
});

/// Provider for CryptoService handling PBKDF2 key derivation and AES-256-GCM
final cryptoServiceProvider = Provider<CryptoService>((ref) {
  return CryptoService();
});

/// Provider for AuthService handling REST calls to backend authentication endpoints
final authServiceProvider = Provider<AuthService>((ref) {
  final dio = ref.watch(dioClientProvider);
  return AuthService(dio: dio);
});

// -----------------------------------------------------------------------------
// Auth State Management Provider
// -----------------------------------------------------------------------------

/// Main authentication state notifier provider
final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final secureStorage = ref.watch(secureStorageServiceProvider);
  final cryptoService = ref.watch(cryptoServiceProvider);
  final authService = ref.watch(authServiceProvider);

  final notifier = AuthNotifier(
    secureStorage: secureStorage,
    cryptoService: cryptoService,
    authService: authService,
  );

  // Initialize and check persistent auth session on provider creation
  notifier.checkAuthStatus();

  return notifier;
});

// -----------------------------------------------------------------------------
// Granular Selectors / Convenience Providers
// -----------------------------------------------------------------------------

/// Provides currently authenticated user profile (or null if unauthenticated)
final currentUserProvider = Provider<UserModel?>((ref) {
  return ref.watch(authStateProvider).user;
});

/// Provides boolean whether current user session is fully authenticated and unlocked
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authStateProvider).isAuthenticated;
});

/// Provides boolean whether vault is locked (logged in but session key cleared)
final isVaultLockedProvider = Provider<bool>((ref) {
  return ref.watch(authStateProvider).isLocked;
});

/// Provides current authentication status enum
final authStatusProvider = Provider<AuthStatus>((ref) {
  return ref.watch(authStateProvider).status;
});

/// Provides active master encryption session key (or null if locked/unauthenticated)
final sessionKeyProvider = Provider<List<int>?>((ref) {
  return ref.watch(authStateProvider).sessionKey;
});

/// Provides active access token for API requests
final accessTokenProvider = Provider<String?>((ref) {
  return ref.watch(authStateProvider).accessToken;
});
