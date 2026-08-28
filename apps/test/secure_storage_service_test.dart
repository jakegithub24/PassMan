import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:apps/services/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Set up mock platform channel values for flutter_secure_storage
  FlutterSecureStorage.setMockInitialValues({});

  late SecureStorageService storageService;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    storageService = SecureStorageService();
  });

  group('SecureStorageService Tests', () {
    test('saveTokens and retrieve tokens', () async {
      const access = 'test_access_token_123';
      const refresh = 'test_refresh_token_456';

      await storageService.saveTokens(accessToken: access, refreshToken: refresh);

      expect(await storageService.getAccessToken(), equals(access));
      expect(await storageService.getRefreshToken(), equals(refresh));

      await storageService.saveAccessToken('updated_access_token');
      expect(await storageService.getAccessToken(), equals('updated_access_token'));

      await storageService.clearTokens();
      expect(await storageService.getAccessToken(), isNull);
      expect(await storageService.getRefreshToken(), isNull);
    });

    test('saveSessionKey, getSessionKey, and clearSessionKey (Vault Lock)', () async {
      final keyBytes = List<int>.generate(32, (i) => i * 2);

      await storageService.saveSessionKey(keyBytes);
      final retrieved = await storageService.getSessionKey();

      expect(retrieved, isNotNull);
      expect(retrieved, equals(keyBytes));

      // Vault Lock: clearing session key leaves tokens untouched
      await storageService.saveTokens(accessToken: 'acc', refreshToken: 'ref');
      await storageService.clearSessionKey();

      expect(await storageService.getSessionKey(), isNull);
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

    test('clearAll wipes all credentials and metadata on Logout', () async {
      await storageService.saveTokens(accessToken: 'acc', refreshToken: 'ref');
      await storageService.saveSessionKey([1, 2, 3, 4]);
      await storageService.saveUserMetadata(userId: 'u1', email: 'e1', salt: 's1');

      await storageService.clearAll();

      expect(await storageService.getAccessToken(), isNull);
      expect(await storageService.getRefreshToken(), isNull);
      expect(await storageService.getSessionKey(), isNull);
      expect(await storageService.getUserMetadata(), isNull);
    });
  });
}
