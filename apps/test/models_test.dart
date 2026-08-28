import 'package:flutter_test/flutter_test.dart';
import 'package:apps/models/models.dart';

void main() {
  group('Client Models Unit Tests', () {
    test('EncryptedVaultEntry serialization round-trip', () {
      final now = DateTime.now().toUtc();
      final entry = EncryptedVaultEntry(
        id: 'entry-1234',
        userId: 'user-5678',
        encryptedData: '{"ciphertext":"abc","iv":"def","tag":"ghi"}',
        updatedAt: now,
        deletedAt: null,
      );

      expect(entry.isDeleted, isFalse);

      final jsonMap = entry.toJson();
      final fromJson = EncryptedVaultEntry.fromJson(jsonMap);

      expect(fromJson.id, equals(entry.id));
      expect(fromJson.userId, equals(entry.userId));
      expect(fromJson.encryptedData, equals(entry.encryptedData));
      expect(fromJson.isDeleted, isFalse);

      final sqliteMap = entry.toSqlite();
      final fromSqlite = EncryptedVaultEntry.fromSqlite(sqliteMap);
      expect(fromSqlite.id, equals(entry.id));
    });

    test('VaultItem decrypted model serialization and copyWith', () {
      final now = DateTime.now().toUtc();
      final item = VaultItem(
        id: 'item-1',
        title: 'Google Account',
        username: 'johndoe@gmail.com',
        password: 'SuperSecretPassword!',
        url: 'https://accounts.google.com',
        notes: 'Recovery email on backup file',
        category: 'logins',
        updatedAt: now,
      );

      expect(item.isDeleted, isFalse);

      final json = item.toDecryptedJson();
      final restored = VaultItem.fromDecryptedJson(json);

      expect(restored.id, equals(item.id));
      expect(restored.title, equals(item.title));
      expect(restored.username, equals(item.username));
      expect(restored.password, equals(item.password));
      expect(restored.url, equals(item.url));
      expect(restored.notes, equals(item.notes));

      final updated = item.copyWith(title: 'Google Main');
      expect(updated.title, equals('Google Main'));
      expect(updated.id, equals(item.id));
    });

    test('SyncState flags and transitions', () {
      const initial = SyncState();
      expect(initial.status, equals(SyncStatus.idle));
      expect(initial.isSyncing, isFalse);
      expect(initial.hasError, isFalse);

      final syncing = initial.copyWith(status: SyncStatus.syncing);
      expect(syncing.isSyncing, isTrue);

      final success = syncing.copyWith(
        status: SyncStatus.success,
        lastSyncedAt: DateTime.now().toUtc(),
        pendingUploadsCount: 0,
      );
      expect(success.isSyncing, isFalse);
      expect(success.lastSyncedAt, isNotNull);
      expect(success.pendingUploadsCount, equals(0));
    });

    test('UserModel and TokenPairModel JSON parsing', () {
      final tokenJson = {
        'access_token': 'mock_acc',
        'refresh_token': 'mock_ref',
        'token_type': 'bearer',
        'expires_in': 600,
        'user': {
          'id': 'user-1',
          'email': 'user@example.com',
          'salt': 'dGVzdA==',
          'created_at': '2026-08-28T10:00:00.000Z',
          'updated_at': '2026-08-28T10:00:00.000Z',
        },
      };

      final pair = TokenPairModel.fromJson(tokenJson);
      expect(pair.accessToken, equals('mock_acc'));
      expect(pair.refreshToken, equals('mock_ref'));
      expect(pair.expiresIn, equals(600));
      expect(pair.user, isNotNull);
      expect(pair.user!.email, equals('user@example.com'));
    });
  });
}
