import 'package:apps/services/secure_storage_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  late SecureStorageService storageService;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    storageService = SecureStorageService();
  });

  group('SecureStorageService Tests (Task 5.5 Token & Session Persistence)', () {
    test('saveTokens and retrieve tokens with atomic persistence', () async {
      const access = 'test_access_token_123';
      const refresh = 'test_refresh_token_456';

      await storageService.saveTokens(accessToken: access, refreshToken: refresh);

      expect(await storageService.getAccessToken(), equals(access));
      expect(await storageService.getRefreshToken(), equals(refresh));
      expect(await storageService.hasValidTokens(), isTrue);

      await storageService.saveAccessToken('updated_access_token');
      expect(await storageService.getAccessToken(), equals('updated_access_token'));

      await storageService.clearTokens();
      expect(await storageService.getAccessToken(), isNull);
      expect(await storageService.getRefreshToken(), isNull);
      expect(await storageService.hasValidTokens(), isFalse);
    });

    test('saveSessionKey, getSessionKey, and clearSessionKey (Vault Lock)', () async {
      final keyBytes = List<int>.generate(32, (i) => i * 2);

      await storageService.saveSessionKey(keyBytes);
      expect(await storageService.hasActiveSessionKey(), isTrue);

      final retrieved = await storageService.getSessionKey();
      expect(retrieved, isNotNull);
      expect(retrieved, equals(keyBytes));

      // Vault Lock: clearing session key leaves tokens untouched
      await storageService.saveTokens(accessToken: 'acc', refreshToken: 'ref');
      await storageService.clearSessionKey();

      expect(await storageService.getSessionKey(), isNull);
      expect(await storageService.hasActiveSessionKey(), isFalse);
      expect(await storageService.getAccessToken(), equals('acc'));
    });

    test('saveUserMetadata and getUserMetadata', () async {
      await storageService.saveUserMetadata(
        userId: 'uuid-1234',
        email: 'user@example.com',
        salt: 'dGVzdF9zYWx0',
      );

      final metadata = await storageService.getUserMetadata();
      expect(metadata, isNotNull);
      expect(metadata!['userId'], equals('uuid-1234'));
      expect(metadata['email'], equals('user@example.com'));
      expect(metadata['salt'], equals('dGVzdF9zYWx0'));
    });

    test('containsKey returns true for existing keys and false for missing keys', () async {
      await storageService.saveTokens(accessToken: 'acc', refreshToken: 'ref');

      expect(await storageService.containsKey(SecureStorageService.keyAccessToken), isTrue);
      expect(await storageService.containsKey(SecureStorageService.keyRefreshToken), isTrue);
      expect(await storageService.containsKey('non_existent_key'), isFalse);
    });

    test('clearAll wipes all credentials and metadata on Logout', () async {
      await storageService.saveTokens(accessToken: 'acc', refreshToken: 'ref');
      await storageService.saveSessionKey([1, 2, 3, 4]);
      await storageService.saveUserMetadata(userId: 'u1', email: 'e1', salt: 's1');

      await storageService.clearAll();

      expect(await storageService.getAccessToken(), isNull);
      expect(await storageService.getRefreshToken(), isNull);
      expect(await storageService.getSessionKey(), isNull);
      expect(await storageService.getUserMetadata(), isNull);
      expect(await storageService.hasValidTokens(), isFalse);
      expect(await storageService.hasActiveSessionKey(), isFalse);
    });
  });
}
