import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/auth_models.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/crypto_service.dart';
import '../services/secure_storage_service.dart';
import 'auth_state.dart';

/// Riverpod StateNotifier managing the user's authentication and vault lock lifecycle
class AuthNotifier extends StateNotifier<AuthState> {
  final SecureStorageService secureStorage;
  final CryptoService cryptoService;
  final AuthService authService;
  final BiometricService? biometricService;

  AuthNotifier({
    required this.secureStorage,
    required this.cryptoService,
    required this.authService,
    this.biometricService,
    AuthState? initialState,
  }) : super(initialState ?? const AuthState.initial());

  // ---------------------------------------------------------------------------
  // Check Initial Authentication Status on Launch
  // ---------------------------------------------------------------------------

  /// Checks secure storage for persisted tokens and session key
  Future<void> checkAuthStatus() async {
    try {
      final String? accessToken = await secureStorage.getAccessToken();
      final String? refreshToken = await secureStorage.getRefreshToken();
      final Map<String, String>? userMeta = await secureStorage.getUserMetadata();

      if (accessToken == null || refreshToken == null || userMeta == null) {
        state = const AuthState.unauthenticated();
        return;
      }

      final UserModel user = UserModel(
        id: userMeta['userId']!,
        email: userMeta['email']!,
        salt: userMeta['salt']!,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      final List<int>? sessionKey = await secureStorage.getSessionKey();

      if (sessionKey != null && sessionKey.isNotEmpty) {
        state = AuthState.authenticated(
          user: user,
          accessToken: accessToken,
          refreshToken: refreshToken,
          sessionKey: sessionKey,
        );
      } else {
        // Logged in with tokens, but session encryption key is locked
        state = AuthState.locked(
          user: user,
          accessToken: accessToken,
          refreshToken: refreshToken,
        );
      }
    } catch (e) {
      state = AuthState.error(
        message: 'Failed to restore authentication session: ${e.toString()}',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Login
  // ---------------------------------------------------------------------------

  /// Logs in user, fetches tokens & profile, derives master session key, and persists securely
  Future<bool> login({
    required String email,
    required String password,
    String? clientType,
  }) async {
    state = const AuthState.authenticating();

    try {
      final TokenPairModel tokenPair = await authService.login(
        email: email,
        password: password,
        clientType: clientType,
      );

      final UserModel? user = tokenPair.user;
      if (user == null) {
        throw Exception('Server did not return user profile on login');
      }

      // 1. Derive master 256-bit AES encryption session key from user salt & master password
      final List<int> sessionKeyBytes = await cryptoService.deriveMasterKey(
        masterPassword: password,
        saltBase64: user.salt,
      );

      // 2. Persist tokens and metadata securely
      await secureStorage.saveTokens(
        accessToken: tokenPair.accessToken,
        refreshToken: tokenPair.refreshToken,
      );
      await secureStorage.saveUserMetadata(
        userId: user.id,
        email: user.email,
        salt: user.salt,
      );
      await secureStorage.saveSessionKey(sessionKeyBytes);

      // 3. Transition to fully authenticated state
      state = AuthState.authenticated(
        user: user,
        accessToken: tokenPair.accessToken,
        refreshToken: tokenPair.refreshToken,
        sessionKey: sessionKeyBytes,
      );

      return true;
    } catch (e) {
      final message = e is Exception
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      state = AuthState.error(message: message);
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Sign Up / Register
  // ---------------------------------------------------------------------------

  /// Registers user with client-generated cryptographic salt, derives session key, and auto-logs in
  Future<bool> signup({
    required String email,
    required String password,
    String? clientType,
  }) async {
    state = const AuthState.authenticating();

    try {
      // 1. Client-side cryptographically secure 16-byte random salt generation
      final String saltBase64 = cryptoService.generateSalt(16);

      // 2. Derive master encryption key
      final List<int> sessionKeyBytes = await cryptoService.deriveMasterKey(
        masterPassword: password,
        saltBase64: saltBase64,
      );

      // 3. Register user account on backend
      final UserModel registeredUser = await authService.register(
        email: email,
        password: password,
        salt: saltBase64,
      );

      // 4. Authenticate to obtain token pair
      final TokenPairModel tokenPair = await authService.login(
        email: email,
        password: password,
        clientType: clientType,
      );

      // 5. Persist tokens and metadata securely
      await secureStorage.saveTokens(
        accessToken: tokenPair.accessToken,
        refreshToken: tokenPair.refreshToken,
      );
      await secureStorage.saveUserMetadata(
        userId: registeredUser.id,
        email: registeredUser.email,
        salt: registeredUser.salt,
      );
      await secureStorage.saveSessionKey(sessionKeyBytes);

      // 6. Transition to authenticated state
      state = AuthState.authenticated(
        user: registeredUser,
        accessToken: tokenPair.accessToken,
        refreshToken: tokenPair.refreshToken,
        sessionKey: sessionKeyBytes,
      );

      return true;
    } catch (e) {
      final message = e is Exception
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      state = AuthState.error(message: message);
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Vault Locking & Unlocking
  // ---------------------------------------------------------------------------

  /// Derives and restores master session key using the master password
  Future<bool> unlockVault(String masterPassword) async {
    final UserModel? user = state.user;
    if (user == null || state.accessToken == null || state.refreshToken == null) {
      state = const AuthState.unauthenticated(message: 'No active user session to unlock');
      return false;
    }

    try {
      // Derive master encryption key with user salt
      final List<int> sessionKeyBytes = await cryptoService.deriveMasterKey(
        masterPassword: masterPassword,
        saltBase64: user.salt,
      );

      await secureStorage.saveSessionKey(sessionKeyBytes);

      state = AuthState.authenticated(
        user: user,
        accessToken: state.accessToken!,
        refreshToken: state.refreshToken!,
        sessionKey: sessionKeyBytes,
      );

      return true;
    } catch (e) {
      final message = e is Exception
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      state = state.copyWith(errorMessage: message);
      return false;
    }
  }

  /// Unlocks the vault using device biometrics / PIN (Task 10.1)
  Future<bool> unlockWithBiometrics() async {
    final UserModel? user = state.user;
    if (user == null || state.accessToken == null || state.refreshToken == null) {
      return false;
    }

    if (biometricService == null) return false;

    try {
      final sessionKeyBytes = await biometricService!.unlockWithBiometrics(userId: user.id);
      if (sessionKeyBytes == null || sessionKeyBytes.isEmpty) {
        return false;
      }

      await secureStorage.saveSessionKey(sessionKeyBytes);

      state = AuthState.authenticated(
        user: user,
        accessToken: state.accessToken!,
        refreshToken: state.refreshToken!,
        sessionKey: sessionKeyBytes,
      );

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Biometric unlock failed: $e');
      }
      return false;
    }
  }

  /// Enables biometric unlock for current session key
  Future<void> enableBiometricUnlock() async {
    final user = state.user;
    final sessionKey = state.sessionKey;
    if (user != null && sessionKey != null && biometricService != null) {
      await biometricService!.enableBiometricUnlock(sessionKey, userId: user.id);
    }
  }

  /// Disables biometric unlock
  Future<void> disableBiometricUnlock() async {
    final user = state.user;
    if (user != null && biometricService != null) {
      await biometricService!.disableBiometricUnlock(userId: user.id);
    }
  }

  /// Locks the vault: clears session key in memory and secure storage without ending session
  Future<void> lockVault() async {
    final UserModel? user = state.user;
    final String? access = state.accessToken;
    final String? refresh = state.refreshToken;

    await secureStorage.clearSessionKey();

    if (user != null && access != null && refresh != null) {
      state = AuthState.locked(
        user: user,
        accessToken: access,
        refreshToken: refresh,
      );
    } else {
      state = const AuthState.unauthenticated();
    }
  }

  // ---------------------------------------------------------------------------
  // Token Rotation (Called by 401 Interceptor)
  // ---------------------------------------------------------------------------

  /// Updates access and refresh tokens after silent token rotation
  Future<void> updateTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await secureStorage.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );

    if (state.user != null) {
      state = state.copyWith(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Logout
  // ---------------------------------------------------------------------------

  /// Revokes session on backend and wipes all local secure storage credentials
  Future<void> logout() async {
    final String? refreshToken = state.refreshToken;

    if (refreshToken != null && refreshToken.isNotEmpty) {
      await authService.logout(refreshToken: refreshToken);
    }

    await secureStorage.clearAll();
    state = const AuthState.unauthenticated();
  }

  /// Forces immediate local logout without network calls (used when refresh token is invalid or revoked)
  Future<void> forceLogout() async {
    await secureStorage.clearAll();
    state = const AuthState.unauthenticated();
  }

  // ---------------------------------------------------------------------------
  // Clear Error
  // ---------------------------------------------------------------------------

  void clearError() {
    if (state.hasError) {
      state = state.copyWith(clearError: true);
    }
  }
}
