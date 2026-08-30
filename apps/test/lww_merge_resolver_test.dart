import 'package:apps/models/local_vault_cache_entry.dart';
import 'package:apps/services/lww_merge_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LWW Merge Resolver Tests (Task 9.3 / MVP.md §6)', () {
    test('1. New remote entry (not in local cache) -> applyServer', () {
      const serverEntry = LocalVaultCacheEntry(
        id: 'new-server-item',
        encryptedData: 'server-payload',
        iv: 'iv1',
        tag: 'tag1',
        serverUpdatedAt: '2026-08-30T12:00:00.000Z',
        deleted: 0,
      );

      final result = LwwMergeResolver.resolve(
        localEntry: null,
        serverEntry: serverEntry,
      );

      expect(result.action, equals(MergeAction.applyServer));
      expect(result.resultingEntry, isNotNull);
      expect(result.resultingEntry!.id, equals('new-server-item'));
      expect(result.resultingEntry!.isPendingSync, equals(0));
    });

    test('2. Remote tombstone for clean local entry -> applyTombstone', () {
      const localEntry = LocalVaultCacheEntry(
        id: 'item-1',
        encryptedData: 'local-old',
        iv: 'iv1',
        tag: 'tag1',
        serverUpdatedAt: '2026-08-30T10:00:00.000Z',
        deleted: 0,
        isPendingSync: 0,
      );

      const serverTombstone = LocalVaultCacheEntry(
        id: 'item-1',
        encryptedData: '',
        iv: '',
        tag: '',
        serverUpdatedAt: '2026-08-30T11:00:00.000Z',
        deleted: 1,
      );

      final result = LwwMergeResolver.resolve(
        localEntry: localEntry,
        serverEntry: serverTombstone,
      );

      expect(result.action, equals(MergeAction.applyTombstone));
      expect(result.entryId, equals('item-1'));
    });

    test('3. Server newer than local dirty entry -> applyServer (server overwrites)', () {
      const localDirtyEntry = LocalVaultCacheEntry(
        id: 'item-2',
        encryptedData: 'local-dirty-edit',
        iv: 'iv1',
        tag: 'tag1',
        serverUpdatedAt: '2026-08-30T10:00:00.000Z',
        deleted: 0,
        isPendingSync: 1,
      );

      const serverNewerEntry = LocalVaultCacheEntry(
        id: 'item-2',
        encryptedData: 'server-newer-update',
        iv: 'iv2',
        tag: 'tag2',
        serverUpdatedAt: '2026-08-30T12:00:00.000Z',
        deleted: 0,
      );

      final result = LwwMergeResolver.resolve(
        localEntry: localDirtyEntry,
        serverEntry: serverNewerEntry,
      );

      expect(result.action, equals(MergeAction.applyServer));
      expect(result.resultingEntry!.encryptedData, equals('server-newer-update'));
      expect(result.resultingEntry!.isPendingSync, equals(0));
    });

    test('4. Local newer than server entry -> keepLocalPending (local wins, queues push)', () {
      const localNewerDirty = LocalVaultCacheEntry(
        id: 'item-3',
        encryptedData: 'local-latest-edit',
        iv: 'iv1',
        tag: 'tag1',
        serverUpdatedAt: '2026-08-30T15:00:00.000Z',
        deleted: 0,
        isPendingSync: 1,
      );

      const serverOlderEntry = LocalVaultCacheEntry(
        id: 'item-3',
        encryptedData: 'server-old-update',
        iv: 'iv2',
        tag: 'tag2',
        serverUpdatedAt: '2026-08-30T12:00:00.000Z',
        deleted: 0,
      );

      final result = LwwMergeResolver.resolve(
        localEntry: localNewerDirty,
        serverEntry: serverOlderEntry,
      );

      expect(result.action, equals(MergeAction.keepLocalPending));
      expect(result.resultingEntry!.encryptedData, equals('local-latest-edit'));
      expect(result.resultingEntry!.isPendingSync, equals(1));
    });

    test('5. Local newer than server tombstone -> keepLocalPending (local resurrected, queues push)', () {
      const localNewerDirty = LocalVaultCacheEntry(
        id: 'item-4',
        encryptedData: 'resurrected-data',
        iv: 'iv1',
        tag: 'tag1',
        serverUpdatedAt: '2026-08-30T16:00:00.000Z',
        deleted: 0,
        isPendingSync: 1,
      );

      const serverOlderTombstone = LocalVaultCacheEntry(
        id: 'item-4',
        encryptedData: '',
        iv: '',
        tag: '',
        serverUpdatedAt: '2026-08-30T14:00:00.000Z',
        deleted: 1,
      );

      final result = LwwMergeResolver.resolve(
        localEntry: localNewerDirty,
        serverEntry: serverOlderTombstone,
      );

      expect(result.action, equals(MergeAction.keepLocalPending));
      expect(result.resultingEntry!.isDeleted, isFalse);
      expect(result.resultingEntry!.isPendingSync, equals(1));
    });
  });
}
