import 'dart:convert';
import 'package:apps/models/encrypted_vault_entry.dart';
import 'package:apps/models/vault_item.dart';
import 'package:apps/services/crypto_service.dart';
import 'package:apps/services/local_vault_storage_service.dart';
import 'package:apps/services/secure_storage_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  FlutterSecureStorage.setMockInitialValues({});

  late SecureStorageService secureStorage;
  late CryptoService cryptoService;
  late LocalVaultStorageService localVaultStorage;
  late Database ffiDb;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    secureStorage = SecureStorageService();
    cryptoService = CryptoService(pbkdf2Iterations: 1000);

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

    localVaultStorage = LocalVaultStorageService(sqliteDb: ffiDb);
  });

  tearDown(() async {
    await ffiDb.close();
  });

  group('Task 6.5: Session Key Isolation & Storage Integrity Tests', () {
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
  });
}
