import 'package:apps/models/auth_models.dart';
import 'package:apps/providers/auth_notifier.dart';
import 'package:apps/providers/auth_providers.dart';
import 'package:apps/providers/auth_state.dart';
import 'package:apps/services/auth_service.dart';
import 'package:apps/services/crypto_service.dart';
import 'package:apps/services/secure_storage_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

// -----------------------------------------------------------------------------
// Mock / Fake Implementations for Deterministic Testing
// -----------------------------------------------------------------------------

class FakeAuthService implements AuthService {
  bool shouldFailLogin = false;
  bool shouldFailSignup = false;
  bool logoutCalled = false;
  String? lastLoggedOutToken;

  UserModel mockUser = UserModel(
    id: 'usr_test_123',
    email: 'test@passman.app',
    salt: 'c2FsdF8xNmJ5dGVzX2FzZGZhcw==',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  TokenPairModel get mockTokenPair => TokenPairModel(
        accessToken: 'mock_jwt_access_token_xyz',
        refreshToken: 'mock_jwt_refresh_token_abc',
        tokenType: 'bearer',
        expiresIn: 600,
        user: mockUser,
      );

  @override
  Future<UserModel> register({
    required String email,
    required String password,
    required String salt,
  }) async {
    if (shouldFailSignup) {
      throw Exception('Email already registered');
    }
    mockUser = UserModel(
      id: 'usr_reg_999',
      email: email,
      salt: salt,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
    return mockUser;
  }

  @override
  Future<TokenPairModel> login({
    required String email,
    required String password,
    String? clientType,
  }) async {
    if (shouldFailLogin) {
      throw Exception('Invalid email or master password');
    }
    return TokenPairModel(
      accessToken: 'access_${email}_token',
      refreshToken: 'refresh_${email}_token',
      tokenType: 'bearer',
      expiresIn: 600,
      user: mockUser,
    );
  }

  @override
  Future<TokenPairModel> refreshToken({
    required String refreshToken,
    String? clientType,
  }) async {
    return TokenPairModel(
      accessToken: 'rotated_access_token',
      refreshToken: 'rotated_refresh_token',
      tokenType: 'bearer',
      expiresIn: 600,
      user: mockUser,
    );
  }

  @override
  Future<void> logout({required String refreshToken}) async {
    logoutCalled = true;
    lastLoggedOutToken = refreshToken;
  }

  @override
  Future<UserModel> getMe({required String accessToken}) async {
    return mockUser;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  late SecureStorageService secureStorage;
  late CryptoService cryptoService;
  late FakeAuthService authService;
  late AuthNotifier authNotifier;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    secureStorage = SecureStorageService();
    // Fast crypto iterations in tests for high execution speed
    cryptoService = CryptoService(pbkdf2Iterations: 100);
    authService = FakeAuthService();

    authNotifier = AuthNotifier(
      secureStorage: secureStorage,
      cryptoService: cryptoService,
      authService: authService,
    );
  });

  group('AuthState Model Unit Tests', () {
    test('initial state has correct default properties', () {
      const state = AuthState.initial();
      expect(state.status, AuthStatus.initial);
      expect(state.isInitial, isTrue);
      expect(state.isAuthenticated, isFalse);
      expect(state.isLocked, isFalse);
      expect(state.isAuthenticating, isFalse);
      expect(state.user, isNull);
      expect(state.accessToken, isNull);
      expect(state.hasSessionKey, isFalse);
      expect(state.hasError, isFalse);
    });

    test('authenticated state getters return true', () {
      final user = UserModel(
        id: 'u1',
        email: 'alice@passman.app',
        salt: 'salt123',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final state = AuthState.authenticated(
        user: user,
        accessToken: 'token_123',
        refreshToken: 'refresh_123',
        sessionKey: [1, 2, 3, 4],
      );

      expect(state.status, AuthStatus.authenticated);
      expect(state.isAuthenticated, isTrue);
      expect(state.isLocked, isFalse);
      expect(state.hasSessionKey, isTrue);
      expect(state.accessToken, 'token_123');
      expect(state.refreshToken, 'refresh_123');
      expect(state.user?.email, 'alice@passman.app');
    });

    test('locked state getters return true and sessionKey is null', () {
      final user = UserModel(
        id: 'u1',
        email: 'alice@passman.app',
        salt: 'salt123',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final state = AuthState.locked(
        user: user,
        accessToken: 'token_123',
        refreshToken: 'refresh_123',
      );

      expect(state.status, AuthStatus.locked);
      expect(state.isLocked, isTrue);
      expect(state.isAuthenticated, isFalse);
      expect(state.hasSessionKey, isFalse);
    });

    test('copyWith updates fields and clears sessionKey / errors properly', () {
      final user = UserModel(
        id: 'u1',
        email: 'alice@passman.app',
        salt: 'salt123',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      var state = AuthState.authenticated(
        user: user,
        accessToken: 'token_old',
        refreshToken: 'refresh_old',
        sessionKey: [1, 2, 3],
      );

      // Rotate tokens
      state = state.copyWith(
        accessToken: 'token_new',
        refreshToken: 'refresh_new',
      );
      expect(state.accessToken, 'token_new');
      expect(state.refreshToken, 'refresh_new');
      expect(state.sessionKey, [1, 2, 3]);

      // Lock vault
      state = state.copyWith(
        status: AuthStatus.locked,
        clearSessionKey: true,
      );
      expect(state.isLocked, isTrue);
      expect(state.sessionKey, isNull);

      // Set error and then clear error
      state = state.copyWith(errorMessage: 'Network timeout');
      expect(state.hasError, isTrue);
      state = state.copyWith(clearError: true);
      expect(state.hasError, isFalse);
    });

    test('equality and hashCode match for identical state contents', () {
      final user1 = UserModel(
        id: 'u1',
        email: 'alice@passman.app',
        salt: 'salt123',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final user2 = UserModel(
        id: 'u1',
        email: 'alice@passman.app',
        salt: 'salt123',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );

      final state1 = AuthState.authenticated(
        user: user1,
        accessToken: 'token',
        refreshToken: 'refresh',
        sessionKey: [1, 2, 3],
      );
      final state2 = AuthState.authenticated(
        user: user2,
        accessToken: 'token',
        refreshToken: 'refresh',
        sessionKey: [1, 2, 3],
      );

      expect(state1, equals(state2));
      expect(state1.hashCode, equals(state2.hashCode));
    });
  });

  group('AuthNotifier Authentication Flow Tests', () {
    test('checkAuthStatus when storage is empty resolves to unauthenticated', () async {
      await authNotifier.checkAuthStatus();
      expect(authNotifier.state.status, AuthStatus.unauthenticated);
      expect(authNotifier.state.isUnauthenticated, isTrue);
    });

    test('checkAuthStatus restores authenticated state when tokens & session key exist', () async {
      await secureStorage.saveTokens(
        accessToken: 'stored_access_token',
        refreshToken: 'stored_refresh_token',
      );
      await secureStorage.saveUserMetadata(
        userId: 'usr_stored_1',
        email: 'stored@passman.app',
        salt: 'c2FsdF8xNmJ5dGVzX2FzZGZhcw==',
      );
      await secureStorage.saveSessionKey([10, 20, 30, 40]);

      await authNotifier.checkAuthStatus();

      expect(authNotifier.state.status, AuthStatus.authenticated);
      expect(authNotifier.state.isAuthenticated, isTrue);
      expect(authNotifier.state.user?.email, 'stored@passman.app');
      expect(authNotifier.state.accessToken, 'stored_access_token');
      expect(authNotifier.state.sessionKey, [10, 20, 30, 40]);
    });

    test('checkAuthStatus restores locked state when tokens exist but session key is missing', () async {
      await secureStorage.saveTokens(
        accessToken: 'stored_access_token',
        refreshToken: 'stored_refresh_token',
      );
      await secureStorage.saveUserMetadata(
        userId: 'usr_stored_1',
        email: 'stored@passman.app',
        salt: 'c2FsdF8xNmJ5dGVzX2FzZGZhcw==',
      );
      // No session key saved

      await authNotifier.checkAuthStatus();

      expect(authNotifier.state.status, AuthStatus.locked);
      expect(authNotifier.state.isLocked, isTrue);
      expect(authNotifier.state.hasSessionKey, isFalse);
      expect(authNotifier.state.user?.email, 'stored@passman.app');
    });

    test('login success authenticates, derives master key, and persists securely', () async {
      final success = await authNotifier.login(
        email: 'test@passman.app',
        password: 'SuperSecretPassword123!',
      );

      expect(success, isTrue);
      expect(authNotifier.state.status, AuthStatus.authenticated);
      expect(authNotifier.state.isAuthenticated, isTrue);
      expect(authNotifier.state.user?.email, 'test@passman.app');
      expect(authNotifier.state.accessToken, 'access_test@passman.app_token');
      expect(authNotifier.state.hasSessionKey, isTrue);
      expect(authNotifier.state.sessionKey?.length, 32); // 256-bit AES Key

      // Verify persistent storage
      expect(await secureStorage.getAccessToken(), 'access_test@passman.app_token');
      expect(await secureStorage.getRefreshToken(), 'refresh_test@passman.app_token');
      expect(await secureStorage.getSessionKey(), isNotNull);
      final meta = await secureStorage.getUserMetadata();
      expect(meta?['email'], 'test@passman.app');
    });

    test('login failure sets error state and returns false', () async {
      authService.shouldFailLogin = true;

      final success = await authNotifier.login(
        email: 'bad@passman.app',
        password: 'WrongPassword!',
      );

      expect(success, isFalse);
      expect(authNotifier.state.status, AuthStatus.error);
      expect(authNotifier.state.hasError, isTrue);
      expect(authNotifier.state.errorMessage, 'Invalid email or master password');
    });

    test('signup success generates salt, derives master key, registers, and authenticates', () async {
      final success = await authNotifier.signup(
        email: 'newuser@passman.app',
        password: 'StrongMasterPassword2026!',
      );

      expect(success, isTrue);
      expect(authNotifier.state.status, AuthStatus.authenticated);
      expect(authNotifier.state.isAuthenticated, isTrue);
      expect(authNotifier.state.user?.email, 'newuser@passman.app');
      expect(authNotifier.state.hasSessionKey, isTrue);
      expect(authNotifier.state.sessionKey?.length, 32);

      // Verify salt and tokens persisted in secure storage
      final storedMeta = await secureStorage.getUserMetadata();
      expect(storedMeta?['email'], 'newuser@passman.app');
      expect(storedMeta?['salt'], isNotEmpty);
      expect(await secureStorage.getAccessToken(), isNotEmpty);
    });

    test('signup failure sets error state and returns false', () async {
      authService.shouldFailSignup = true;

      final success = await authNotifier.signup(
        email: 'existing@passman.app',
        password: 'Password123!',
      );

      expect(success, isFalse);
      expect(authNotifier.state.status, AuthStatus.error);
      expect(authNotifier.state.errorMessage, 'Email already registered');
    });

    test('lockVault clears session key in state and storage while retaining tokens', () async {
      // First login
      await authNotifier.login(
        email: 'test@passman.app',
        password: 'Password123!',
      );
      expect(authNotifier.state.isAuthenticated, isTrue);
      expect(authNotifier.state.hasSessionKey, isTrue);

      // Lock vault
      await authNotifier.lockVault();

      expect(authNotifier.state.status, AuthStatus.locked);
      expect(authNotifier.state.isLocked, isTrue);
      expect(authNotifier.state.hasSessionKey, isFalse);
      expect(authNotifier.state.accessToken, isNotNull);
      expect(authNotifier.state.user?.email, 'test@passman.app');

      // Verify session key cleared from secure storage
      expect(await secureStorage.getSessionKey(), isNull);
      // Verify tokens and user metadata are still in secure storage
      expect(await secureStorage.getAccessToken(), isNotNull);
    });

    test('unlockVault with master password restores session key and authenticated state', () async {
      // Setup locked state
      await authNotifier.login(
        email: 'test@passman.app',
        password: 'Password123!',
      );
      await authNotifier.lockVault();
      expect(authNotifier.state.isLocked, isTrue);

      // Unlock
      final success = await authNotifier.unlockVault('Password123!');
      expect(success, isTrue);
      expect(authNotifier.state.status, AuthStatus.authenticated);
      expect(authNotifier.state.isAuthenticated, isTrue);
      expect(authNotifier.state.hasSessionKey, isTrue);
      expect(authNotifier.state.sessionKey?.length, 32);

      // Verify session key restored in secure storage
      expect(await secureStorage.getSessionKey(), isNotNull);
    });

    test('updateTokens updates tokens in memory and secure storage', () async {
      await authNotifier.login(
        email: 'test@passman.app',
        password: 'Password123!',
      );

      await authNotifier.updateTokens(
        accessToken: 'fresh_access_token_999',
        refreshToken: 'fresh_refresh_token_999',
      );

      expect(authNotifier.state.accessToken, 'fresh_access_token_999');
      expect(authNotifier.state.refreshToken, 'fresh_refresh_token_999');
      expect(await secureStorage.getAccessToken(), 'fresh_access_token_999');
      expect(await secureStorage.getRefreshToken(), 'fresh_refresh_token_999');
    });

    test('logout revokes session on server and wipes secure storage', () async {
      await authNotifier.login(
        email: 'test@passman.app',
        password: 'Password123!',
      );

      await authNotifier.logout();

      expect(authNotifier.state.status, AuthStatus.unauthenticated);
      expect(authNotifier.state.user, isNull);
      expect(authNotifier.state.accessToken, isNull);
      expect(authNotifier.state.sessionKey, isNull);
      expect(authService.logoutCalled, isTrue);
      expect(authService.lastLoggedOutToken, 'refresh_test@passman.app_token');

      // Verify complete storage wipeout
      expect(await secureStorage.getAccessToken(), isNull);
      expect(await secureStorage.getRefreshToken(), isNull);
      expect(await secureStorage.getSessionKey(), isNull);
      expect(await secureStorage.getUserMetadata(), isNull);
    });

    test('clearError removes error message', () {
      authNotifier.state = const AuthState.error(message: 'Something went wrong');
      expect(authNotifier.state.hasError, isTrue);

      authNotifier.clearError();
      expect(authNotifier.state.hasError, isFalse);
      expect(authNotifier.state.errorMessage, isNull);
    });
  });

  group('Riverpod Container Provider Integration Tests', () {
    test('ProviderContainer exposes auth providers and reflects notifier state', () async {
      final container = ProviderContainer(
        overrides: [
          secureStorageServiceProvider.overrideWithValue(secureStorage),
          cryptoServiceProvider.overrideWithValue(cryptoService),
          authServiceProvider.overrideWithValue(authService),
        ],
      );
      addTearDown(container.dispose);

      // Initially unauthenticated
      expect(container.read(isAuthenticatedProvider), isFalse);
      expect(container.read(isVaultLockedProvider), isFalse);
      expect(container.read(currentUserProvider), isNull);

      // Perform login via notifier
      final notifier = container.read(authStateProvider.notifier);
      final loggedIn = await notifier.login(
        email: 'test@passman.app',
        password: 'Password123!',
      );

      expect(loggedIn, isTrue);
      expect(container.read(isAuthenticatedProvider), isTrue);
      expect(container.read(isVaultLockedProvider), isFalse);
      expect(container.read(currentUserProvider)?.email, 'test@passman.app');
      expect(container.read(accessTokenProvider), 'access_test@passman.app_token');
      expect(container.read(sessionKeyProvider)?.length, 32);

      // Perform lock
      await notifier.lockVault();
      expect(container.read(isAuthenticatedProvider), isFalse);
      expect(container.read(isVaultLockedProvider), isTrue);
      expect(container.read(sessionKeyProvider), isNull);
    });
  });
}
