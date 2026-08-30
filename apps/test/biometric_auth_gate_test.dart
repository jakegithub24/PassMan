import 'package:apps/models/auth_models.dart';
import 'package:apps/providers/auth_notifier.dart';
import 'package:apps/providers/auth_providers.dart';
import 'package:apps/providers/auth_state.dart';
import 'package:apps/screens/app_lock_gate.dart';
import 'package:apps/screens/biometric_lock_screen.dart';
import 'package:apps/services/auth_service.dart';
import 'package:apps/services/biometric_service.dart';
import 'package:apps/services/crypto_service.dart';
import 'package:apps/services/secure_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

class MockLocalAuthentication extends Fake implements LocalAuthentication {
  bool isSupported = true;
  bool canCheck = true;
  bool shouldAuthenticateSucceed = true;
  List<BiometricType> biometrics = [BiometricType.fingerprint, BiometricType.face];
  int authCalls = 0;

  @override
  Future<bool> isDeviceSupported() async => isSupported;

  @override
  Future<bool> get canCheckBiometrics async => canCheck;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => biometrics;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<Object> authMessages = const <Object>[],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    authCalls++;
    return shouldAuthenticateSucceed;
  }
}

class FakeTestAuthService extends Fake implements AuthService {
  @override
  Future<void> logout({String? refreshToken}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  late MockLocalAuthentication mockLocalAuth;
  late SecureStorageService secureStorage;
  late CryptoService cryptoService;
  late BiometricService biometricService;

  final testUser = UserModel(
    id: 'test-user-123',
    email: 'biometric.user@passman.app',
    salt: 'test-salt-base64',
    createdAt: DateTime.utc(2026, 8, 30),
    updatedAt: DateTime.utc(2026, 8, 30),
  );

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    mockLocalAuth = MockLocalAuthentication();
    secureStorage = SecureStorageService();
    cryptoService = CryptoService(pbkdf2Iterations: 1000);
    biometricService = BiometricService(
      localAuth: mockLocalAuth,
      secureStorage: secureStorage,
    );
  });

  group('BiometricService Unit Tests (Task 10.1 / MVP.md §5, §7)', () {
    test('Hardware capability checks (canAuthenticate & getAvailableBiometrics)', () async {
      expect(await biometricService.canAuthenticate(), isTrue);
      final biometrics = await biometricService.getAvailableBiometrics();
      expect(biometrics, contains(BiometricType.fingerprint));
      expect(biometrics, contains(BiometricType.face));

      mockLocalAuth.isSupported = false;
      mockLocalAuth.canCheck = false;
      expect(await biometricService.canAuthenticate(), isFalse);
    });

    test('Enabling, checking status, and recovering session key with biometrics', () async {
      final sampleKey = List<int>.generate(32, (i) => i + 1);

      // Initially disabled
      expect(await biometricService.isBiometricUnlockEnabled(userId: testUser.id), isFalse);

      // Enable biometrics
      await biometricService.enableBiometricUnlock(sampleKey, userId: testUser.id);
      expect(await biometricService.isBiometricUnlockEnabled(userId: testUser.id), isTrue);

      // Unlock with successful authentication
      final recoveredKey = await biometricService.unlockWithBiometrics(userId: testUser.id);
      expect(recoveredKey, equals(sampleKey));
      expect(mockLocalAuth.authCalls, equals(1));

      // Unlock when authentication fails / is cancelled
      mockLocalAuth.shouldAuthenticateSucceed = false;
      final failedKey = await biometricService.unlockWithBiometrics(userId: testUser.id);
      expect(failedKey, isNull);

      // Disable biometrics
      await biometricService.disableBiometricUnlock(userId: testUser.id);
      expect(await biometricService.isBiometricUnlockEnabled(userId: testUser.id), isFalse);
      expect(await biometricService.unlockWithBiometrics(userId: testUser.id), isNull);
    });
  });

  group('BiometricLockScreen & AppLockGate Widget Tests (Task 10.1)', () {
    testWidgets('AppLockGate renders BiometricLockScreen when AuthStatus.locked', (tester) async {
      final authNotifier = AuthNotifier(
        secureStorage: secureStorage,
        cryptoService: cryptoService,
        authService: FakeTestAuthService(),
        biometricService: biometricService,
        initialState: AuthState.locked(
          user: testUser,
          accessToken: 'access-123',
          refreshToken: 'refresh-123',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith((ref) => authNotifier),
            biometricServiceProvider.overrideWithValue(biometricService),
          ],
          child: const MaterialApp(
            home: AppLockGate(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Vault Locked'), findsOneWidget);
      expect(find.text('biometric.user@passman.app'), findsOneWidget);
      expect(find.text('Unlock with Biometrics'), findsOneWidget);
      expect(find.text('Unlock with Password'), findsOneWidget);
    });

    testWidgets('BiometricLockScreen master password unlock works on valid input', (tester) async {
      final derivedKey = await cryptoService.deriveMasterKey(
        masterPassword: 'CorrectPassword123!',
        saltBase64: testUser.salt,
      );

      final authNotifier = AuthNotifier(
        secureStorage: secureStorage,
        cryptoService: cryptoService,
        authService: FakeTestAuthService(),
        biometricService: biometricService,
        initialState: AuthState.locked(
          user: testUser,
          accessToken: 'access-123',
          refreshToken: 'refresh-123',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith((ref) => authNotifier),
            biometricServiceProvider.overrideWithValue(biometricService),
          ],
          child: const MaterialApp(
            home: BiometricLockScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter Master Password
      await tester.enterText(find.byType(TextFormField), 'CorrectPassword123!');
      await tester.tap(find.text('Unlock with Password'));
      await tester.pumpAndSettle();

      expect(authNotifier.state.status, equals(AuthStatus.authenticated));
      expect(authNotifier.state.sessionKey, equals(derivedKey));
    });

    testWidgets('BiometricLockScreen logout button resets session', (tester) async {
      final authNotifier = AuthNotifier(
        secureStorage: secureStorage,
        cryptoService: cryptoService,
        authService: FakeTestAuthService(),
        biometricService: biometricService,
        initialState: AuthState.locked(
          user: testUser,
          accessToken: 'access-123',
          refreshToken: 'refresh-123',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith((ref) => authNotifier),
            biometricServiceProvider.overrideWithValue(biometricService),
          ],
          child: const MaterialApp(
            home: BiometricLockScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Log out of this account'));
      await tester.pumpAndSettle();

      expect(authNotifier.state.status, equals(AuthStatus.unauthenticated));
    });
  });
}
