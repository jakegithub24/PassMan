import 'dart:convert';
import 'package:apps/models/encrypted_vault_entry.dart';
import 'package:apps/models/local_vault_cache_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalVaultCacheEntry (Task 8.1 / MVP.md §3)', () {
    test('defines shared table name and CREATE TABLE SQL schema matching MVP.md §3', () {
      expect(LocalVaultCacheEntry.tableName, equals('local_vault_cache'));

      final sql = LocalVaultCacheEntry.createTableSql;
      expect(sql, contains('CREATE TABLE IF NOT EXISTS local_vault_cache'));
      expect(sql, contains('id TEXT PRIMARY KEY'));
      expect(sql, contains('encrypted_data TEXT NOT NULL'));
      expect(sql, contains('iv TEXT NOT NULL'));
      expect(sql, contains('tag TEXT NOT NULL'));
      expect(sql, contains('server_updated_at TEXT NOT NULL'));
      expect(sql, contains('deleted INTEGER NOT NULL DEFAULT 0'));
      expect(sql, contains('is_pending_sync INTEGER NOT NULL DEFAULT 0'));
    });

    test('serializes to and deserializes from SQLite/Hive map correctly', () {
      const entry = LocalVaultCacheEntry(
        id: 'entry-uuid-1',
        encryptedData: 'dGVzdF9jaXBoZXJ0ZXh0X2J5dGVz',
        iv: '1234567890abcdef',
        tag: 'fedcba0987654321',
        serverUpdatedAt: '2026-08-30T20:00:00.000Z',
        deleted: 0,
        isPendingSync: 1,
      );

      final map = entry.toMap();
      expect(map['id'], equals('entry-uuid-1'));
      expect(map['encrypted_data'], equals('dGVzdF9jaXBoZXJ0ZXh0X2J5dGVz'));
      expect(map['iv'], equals('1234567890abcdef'));
      expect(map['tag'], equals('fedcba0987654321'));
      expect(map['server_updated_at'], equals('2026-08-30T20:00:00.000Z'));
      expect(map['deleted'], equals(0));
      expect(map['is_pending_sync'], equals(1));

      final deserialized = LocalVaultCacheEntry.fromMap(map);
      expect(deserialized.id, equals(entry.id));
      expect(deserialized.encryptedData, equals(entry.encryptedData));
      expect(deserialized.iv, equals(entry.iv));
      expect(deserialized.tag, equals(entry.tag));
      expect(deserialized.serverUpdatedAt, equals(entry.serverUpdatedAt));
      expect(deserialized.deleted, equals(0));
      expect(deserialized.isPendingSync, equals(1));
      expect(deserialized.isDeleted, isFalse);
      expect(deserialized.isPending, isTrue);
      expect(deserialized, equals(entry));
    });

    test('fromEncryptedPayload parses zero-knowledge JSON envelope {"ciphertext", "iv", "tag"}', () {
      final envelope = jsonEncode({
        'ciphertext': 'cipher-payload-abc',
        'iv': 'iv-bytes-123',
        'tag': 'tag-bytes-456',
      });

      final entry = LocalVaultCacheEntry.fromEncryptedPayload(
        id: 'vault-item-1',
        encryptedJson: envelope,
        serverUpdatedAt: '2026-08-30T22:30:00.000Z',
        isDeleted: false,
        isPendingSync: true,
      );

      expect(entry.id, equals('vault-item-1'));
      expect(entry.encryptedData, equals('cipher-payload-abc'));
      expect(entry.iv, equals('iv-bytes-123'));
      expect(entry.tag, equals('tag-bytes-456'));
      expect(entry.serverUpdatedAt, equals('2026-08-30T22:30:00.000Z'));
      expect(entry.isDeleted, isFalse);
      expect(entry.isPending, isTrue);

      // Reconstructed envelopeJson must match
      final reconstructed = jsonDecode(entry.envelopeJson) as Map<String, dynamic>;
      expect(reconstructed['ciphertext'], equals('cipher-payload-abc'));
      expect(reconstructed['iv'], equals('iv-bytes-123'));
      expect(reconstructed['tag'], equals('tag-bytes-456'));
    });

    test('bridges to and from EncryptedVaultEntry smoothly', () {
      final originalEnvelope = jsonEncode({
        'ciphertext': 'enc-data-xyz',
        'iv': 'iv-111',
        'tag': 'tag-222',
      });

      final encryptedVaultEntry = EncryptedVaultEntry(
        id: 'entry-99',
        userId: 'user-77',
        encryptedData: originalEnvelope,
        updatedAt: DateTime.utc(2026, 8, 30, 15, 0),
        deletedAt: null,
      );

      // Convert EncryptedVaultEntry -> LocalVaultCacheEntry
      final cacheEntry = LocalVaultCacheEntry.fromEncryptedVaultEntry(
        encryptedVaultEntry,
        isPendingSync: true,
      );

      expect(cacheEntry.id, equals('entry-99'));
      expect(cacheEntry.encryptedData, equals('enc-data-xyz'));
      expect(cacheEntry.iv, equals('iv-111'));
      expect(cacheEntry.tag, equals('tag-222'));
      expect(cacheEntry.isDeleted, isFalse);
      expect(cacheEntry.isPending, isTrue);

      // Convert LocalVaultCacheEntry -> EncryptedVaultEntry
      final restored = cacheEntry.toEncryptedVaultEntry(userId: 'user-77');
      expect(restored.id, equals('entry-99'));
      expect(restored.userId, equals('user-77'));
      expect(restored.isDeleted, isFalse);

      final restoredEnvelope = jsonDecode(restored.encryptedData) as Map<String, dynamic>;
      expect(restoredEnvelope['ciphertext'], equals('enc-data-xyz'));
      expect(restoredEnvelope['iv'], equals('iv-111'));
      expect(restoredEnvelope['tag'], equals('tag-222'));
    });

    test('tombstoned deleted entry handles deleted flag = 1', () {
      const tombstone = LocalVaultCacheEntry(
        id: 'tombstone-item',
        encryptedData: '',
        iv: '',
        tag: '',
        serverUpdatedAt: '2026-08-30T18:00:00.000Z',
        deleted: 1,
        isPendingSync: 1,
      );

      expect(tombstone.isDeleted, isTrue);
      expect(tombstone.isPending, isTrue);

      final map = tombstone.toMap();
      expect(map['deleted'], equals(1));
      expect(map['is_pending_sync'], equals(1));

      final restored = LocalVaultCacheEntry.fromMap(map);
      expect(restored.isDeleted, isTrue);
    });

    test('copyWith produces updated copy with unchanged fields preserved', () {
      const original = LocalVaultCacheEntry(
        id: 'item-10',
        encryptedData: 'abc',
        iv: 'def',
        tag: 'ghi',
        serverUpdatedAt: '2026-08-30T10:00:00.000Z',
        deleted: 0,
        isPendingSync: 0,
      );

      final modified = original.copyWith(
        isPendingSync: 1,
        serverUpdatedAt: '2026-08-30T12:00:00.000Z',
      );

      expect(modified.id, equals('item-10'));
      expect(modified.encryptedData, equals('abc'));
      expect(modified.iv, equals('def'));
      expect(modified.tag, equals('ghi'));
      expect(modified.isPendingSync, equals(1));
      expect(modified.serverUpdatedAt, equals('2026-08-30T12:00:00.000Z'));
      expect(modified.deleted, equals(0));
    });
  });
}
