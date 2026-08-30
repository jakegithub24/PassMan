import 'dart:convert';
import 'package:apps/models/auth_models.dart';
import 'package:apps/models/encrypted_vault_entry.dart';
import 'package:apps/models/local_vault_cache_entry.dart';
import 'package:apps/models/vault_item.dart';
import 'package:apps/providers/auth_notifier.dart';
import 'package:apps/providers/auth_state.dart';
import 'package:apps/services/auth_service.dart';
import 'package:apps/services/biometric_service.dart';
import 'package:apps/services/crypto_service.dart';
import 'package:apps/services/local_vault_storage_service.dart';
import 'package:apps/services/secure_storage_service.dart';
import 'package:apps/services/sqlite_vault_cache_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockIsolationLocalAuth extends Fake implements LocalAuthentication {
  bool authenticateResult = true;

  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<bool> get canCheckBiometrics async => true;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<Object> authMessages = const <Object>[],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    return authenticateResult;
  }
}

class FakeIsolationAuthService extends Fake implements AuthService {
  @override
  Future<void> logout({String? refreshToken}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  FlutterSecureStorage.setMockInitialValues({});

  late SecureStorageService secureStorage;
  late CryptoService cryptoService;
  late LocalVaultStorageService localVaultStorage;
  late SqliteVaultCacheService sqliteVaultCache;
  late BiometricService biometricService;
  late MockIsolationLocalAuth mockLocalAuth;
  late Database ffiDb;
  late UserModel testUser;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    secureStorage = SecureStorageService();
    cryptoService = CryptoService(pbkdf2Iterations: 1000);
    testUser = UserModel(
      id: 'user-isolation-007',
      email: 'zero.knowledge@passman.app',
      salt: cryptoService.generateSalt(16),
      createdAt: DateTime.utc(2026, 8, 30),
      updatedAt: DateTime.utc(2026, 8, 30),
    );
    mockLocalAuth = MockIsolationLocalAuth();
    biometricService = BiometricService(
      localAuth: mockLocalAuth,
      secureStorage: secureStorage,
    );

    ffiDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await ffiDb.execute('''
      CREATE TABLE ${LocalVaultStorageService.tableName} (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        encrypted_data TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        is_dirty INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await ffiDb.execute(LocalVaultCacheEntry.createTableSql);

    localVaultStorage = LocalVaultStorageService(sqliteDb: ffiDb);
    sqliteVaultCache = SqliteVaultCacheService(db: ffiDb);
  });

  tearDown(() async {
    await ffiDb.close();
  });

  group('Task 10.3 / 6.5: Session Key Zero-Knowledge Isolation Across Lock/Unlock Cycles', () {
    test('session key is stored solely in SecureStorageService and NEVER in LocalVaultStorageService', () async {
      const masterPassword = 'MasterPassword2026!';
      final salt = cryptoService.generateSalt(16);

      // 1. Derive 256-bit AES master session key
      final sessionKey = await cryptoService.deriveMasterKey(
        masterPassword: masterPassword,
        saltBase64: salt,
      );

      // 2. Persist session key in SecureStorageService
      await secureStorage.saveSessionKey(sessionKey);
      await secureStorage.saveTokens(
        accessToken: 'access_jwt_123',
        refreshToken: 'refresh_jwt_456',
      );

      // 3. Encrypt a VaultItem
      final originalItem = VaultItem(
        id: 'entry-item-001',
        title: 'Primary Google Account',
        username: 'user@gmail.com',
        password: 'UltraSecretPassword#123',
        url: 'https://accounts.google.com',
        notes: 'Recovery codes: 1111-2222-3333',
        updatedAt: DateTime.utc(2026, 8, 29, 12, 0, 0),
      );

      final itemJson = jsonEncode(originalItem.toJson());
      final encryptedJsonEnvelope = await cryptoService.encryptVaultPayload(
        plaintext: itemJson,
        keyBytes: sessionKey,
      );

      // 4. Save encrypted entry to Local SQLite Cache
      final entry = EncryptedVaultEntry(
        id: originalItem.id,
        userId: 'user-uuid-8888',
        encryptedData: encryptedJsonEnvelope,
        updatedAt: originalItem.updatedAt,
      );

      await localVaultStorage.saveEntry(entry);

      // 5. Inspect raw SQLite database rows directly to verify NO plaintext or session key is leaked
      final List<Map<String, dynamic>> rawRows = await ffiDb.query(
        LocalVaultStorageService.tableName,
      );

      expect(rawRows.length, equals(1));
      final rawRow = rawRows.first;

      // Verify schema fields
      expect(rawRow.containsKey('id'), isTrue);
      expect(rawRow.containsKey('user_id'), isTrue);
      expect(rawRow.containsKey('encrypted_data'), isTrue);
      expect(rawRow.containsKey('updated_at'), isTrue);
      expect(rawRow.containsKey('deleted_at'), isTrue);
      expect(rawRow.containsKey('is_dirty'), isTrue);

      // Verify NO column or data in SQLite contains the session key or master password
      final rawRowString = jsonEncode(rawRow);
      expect(rawRowString.contains(masterPassword), isFalse);
      expect(rawRowString.contains(originalItem.password), isFalse);
      expect(rawRowString.contains(originalItem.notes!), isFalse);
      expect(rawRowString.contains(base64Encode(sessionKey)), isFalse);

      // 6. Verify encrypted_data structure is strictly {ciphertext, iv, tag}
      final parsedEnvelope = jsonDecode(rawRow['encrypted_data'] as String) as Map<String, dynamic>;
      expect(parsedEnvelope.keys.toSet(), equals({'ciphertext', 'iv', 'tag'}));

      // 7. Test Vault Lock: clearing session key in SecureStorage leaves local SQLite cache intact
      await secureStorage.clearSessionKey();
      expect(await secureStorage.getSessionKey(), isNull);
      expect(await secureStorage.hasActiveSessionKey(), isFalse);

      // Local SQLite still has the encrypted entry
      final cachedEntry = await localVaultStorage.getEntry('entry-item-001');
      expect(cachedEntry, isNotNull);
      expect(cachedEntry!.encryptedData, equals(encryptedJsonEnvelope));

      // 8. Re-authenticate / Unlock Vault: re-deriving session key restores decryptability
      final rederivedKey = await cryptoService.deriveMasterKey(
        masterPassword: masterPassword,
        saltBase64: salt,
      );
      await secureStorage.saveSessionKey(rederivedKey);

      final decryptedJson = await cryptoService.decryptVaultPayload(
        jsonPayload: cachedEntry.encryptedData,
        keyBytes: (await secureStorage.getSessionKey())!,
      );

      final restoredItem = VaultItem.fromJson(jsonDecode(decryptedJson) as Map<String, dynamic>);
      expect(restoredItem.title, equals(originalItem.title));
      expect(restoredItem.password, equals(originalItem.password));
    });

    test('Zero-knowledge session key isolation across repeated Lock -> Biometric Unlock -> Lock -> Password Unlock cycles', () async {
      const masterPass = 'SuperVaultPassphrase2026!';
      final masterKey = await cryptoService.deriveMasterKey(
        masterPassword: masterPass,
        saltBase64: testUser.salt,
      );

      final authNotifier = AuthNotifier(
        secureStorage: secureStorage,
        cryptoService: cryptoService,
        authService: FakeIsolationAuthService(),
        biometricService: biometricService,
        initialState: AuthState.authenticated(
          user: testUser,
          accessToken: 'access-token-jwt',
          refreshToken: 'refresh-token-jwt',
          sessionKey: masterKey,
        ),
      );

      // 1. Enable biometric unlock with initial session key
      await authNotifier.enableBiometricUnlock();
      expect(await biometricService.isBiometricUnlockEnabled(userId: testUser.id), isTrue);

      // Store a local vault entry in SQLite local_vault_cache
      final item = VaultItem(
        id: 'secure-note-99',
        title: 'Zero Knowledge Bank PIN',
        username: 'zk_user',
        password: 'PIN-SECRET-9988',
        updatedAt: DateTime.utc(2026, 8, 30),
      );
      final encPayload = await cryptoService.encryptVaultPayload(
        plaintext: jsonEncode(item.toJson()),
        keyBytes: masterKey,
      );
      await sqliteVaultCache.saveEntry(LocalVaultCacheEntry.fromEncryptedPayload(
        id: item.id,
        encryptedJson: encPayload,
        serverUpdatedAt: '2026-08-30T10:00:00.000Z',
      ));

      // --- CYCLE 1: LOCK VAULT ---
      await authNotifier.lockVault();
      expect(authNotifier.state.status, equals(AuthStatus.locked));
      expect(authNotifier.state.sessionKey, isNull);
      expect(await secureStorage.getSessionKey(), isNull);
      expect(await secureStorage.hasActiveSessionKey(), isFalse);

      // Verify SQLite table still contains NO plaintext key or passwords
      final tableRowsLock1 = await ffiDb.query(LocalVaultCacheEntry.tableName);
      final tableStrLock1 = jsonEncode(tableRowsLock1);
      expect(tableStrLock1.contains(masterPass), isFalse);
      expect(tableStrLock1.contains('PIN-SECRET-9988'), isFalse);
      expect(tableStrLock1.contains(base64Encode(masterKey)), isFalse);

      // --- CYCLE 2: BIOMETRIC UNLOCK ---
      final bioUnlockSuccess = await authNotifier.unlockWithBiometrics();
      expect(bioUnlockSuccess, isTrue);
      expect(authNotifier.state.status, equals(AuthStatus.authenticated));
      expect(authNotifier.state.sessionKey, equals(masterKey));
      expect(await secureStorage.getSessionKey(), equals(masterKey));

      // Decrypt item to verify integrity
      final cached1 = (await sqliteVaultCache.getEntry('secure-note-99'))!;
      final dec1 = await cryptoService.decryptVaultPayload(
        jsonPayload: cached1.envelopeJson,
        keyBytes: authNotifier.state.sessionKey!,
      );
      expect(jsonDecode(dec1)['password'], equals('PIN-SECRET-9988'));

      // --- CYCLE 3: LOCK VAULT AGAIN ---
      await authNotifier.lockVault();
      expect(authNotifier.state.status, equals(AuthStatus.locked));
      expect(authNotifier.state.sessionKey, isNull);
      expect(await secureStorage.getSessionKey(), isNull);

      // --- CYCLE 4: MASTER PASSWORD UNLOCK ---
      final passUnlockSuccess = await authNotifier.unlockVault(masterPass);
      expect(passUnlockSuccess, isTrue);
      expect(authNotifier.state.status, equals(AuthStatus.authenticated));
      expect(authNotifier.state.sessionKey, equals(masterKey));

      // --- CYCLE 5: LOGOUT / TOTAL WIPEOUT ---
      await authNotifier.logout();
      expect(authNotifier.state.status, equals(AuthStatus.unauthenticated));
      expect(authNotifier.state.sessionKey, isNull);
      expect(await secureStorage.getSessionKey(), isNull);
      expect(await secureStorage.getAccessToken(), isNull);
      expect(await secureStorage.getBiometricSessionKey(userId: testUser.id), isNull);
      expect(await secureStorage.isBiometricEnabled(userId: testUser.id), isFalse);
    });
  });
}
