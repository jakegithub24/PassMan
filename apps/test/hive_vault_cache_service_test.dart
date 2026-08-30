import 'dart:io';
import 'package:apps/models/local_vault_cache_entry.dart';
import 'package:apps/services/hive_vault_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late HiveVaultCacheService cacheService;
  late Box<Map> box;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_vault_test_');
    Hive.init(tempDir.path);
    box = await Hive.openBox<Map>('test_local_vault_cache');
    cacheService = HiveVaultCacheService(box: box);
  });

  tearDown(() async {
    await cacheService.close();
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('HiveVaultCacheService (Task 8.3 / Hive Web Implementation)', () {
    test('saveEntry and getEntry stores and retrieves LocalVaultCacheEntry correctly', () async {
      const entry = LocalVaultCacheEntry(
        id: 'hive-entry-1',
        encryptedData: 'web-cipher-text-12345',
        iv: 'web-iv-123',
        tag: 'web-tag-456',
        serverUpdatedAt: '2026-08-30T16:00:00.000Z',
        deleted: 0,
        isPendingSync: 1,
      );

      await cacheService.saveEntry(entry);

      final fetched = await cacheService.getEntry('hive-entry-1');
      expect(fetched, isNotNull);
      expect(fetched!.id, equals('hive-entry-1'));
      expect(fetched.encryptedData, equals('web-cipher-text-12345'));
      expect(fetched.iv, equals('web-iv-123'));
      expect(fetched.tag, equals('web-tag-456'));
      expect(fetched.serverUpdatedAt, equals('2026-08-30T16:00:00.000Z'));
      expect(fetched.deleted, equals(0));
      expect(fetched.isPendingSync, equals(1));
      expect(fetched.isDeleted, isFalse);
      expect(fetched.isPending, isTrue);
    });

    test('saveEntries batch-inserts multiple records into Hive box', () async {
      final entries = [
        const LocalVaultCacheEntry(
          id: 'web-item-1',
          encryptedData: 'web-c1',
          iv: 'web-i1',
          tag: 'web-t1',
          serverUpdatedAt: '2026-08-30T10:00:00.000Z',
        ),
        const LocalVaultCacheEntry(
          id: 'web-item-2',
          encryptedData: 'web-c2',
          iv: 'web-i2',
          tag: 'web-t2',
          serverUpdatedAt: '2026-08-30T11:00:00.000Z',
        ),
        const LocalVaultCacheEntry(
          id: 'web-item-3',
          encryptedData: 'web-c3',
          iv: 'web-i3',
          tag: 'web-t3',
          serverUpdatedAt: '2026-08-30T12:00:00.000Z',
        ),
      ];

      await cacheService.saveEntries(entries);

      final all = await cacheService.getAllEntries();
      expect(all.length, equals(3));
      // Ordered by server_updated_at DESC
      expect(all.first.id, equals('web-item-3'));
      expect(all.last.id, equals('web-item-1'));
    });

    test('getAllEntries filters out deleted tombstones by default and includes when requested', () async {
      await cacheService.saveEntry(const LocalVaultCacheEntry(
        id: 'web-active-1',
        encryptedData: 'c1',
        iv: 'i1',
        tag: 't1',
        serverUpdatedAt: '2026-08-30T10:00:00.000Z',
        deleted: 0,
      ));

      await cacheService.saveEntry(const LocalVaultCacheEntry(
        id: 'web-deleted-1',
        encryptedData: 'c2',
        iv: 'i2',
        tag: 't2',
        serverUpdatedAt: '2026-08-30T12:00:00.000Z',
        deleted: 1,
      ));

      // Without deleted
      final activeList = await cacheService.getAllEntries(includeDeleted: false);
      expect(activeList.length, equals(1));
      expect(activeList.first.id, equals('web-active-1'));

      // With deleted tombstones
      final allList = await cacheService.getAllEntries(includeDeleted: true);
      expect(allList.length, equals(2));
      expect(allList.first.id, equals('web-deleted-1'));
    });

    test('markDeleted soft-deletes item, sets is_pending_sync = 1, and advances server_updated_at', () async {
      await cacheService.saveEntry(const LocalVaultCacheEntry(
        id: 'web-item-to-delete',
        encryptedData: 'c-del',
        iv: 'iv',
        tag: 'tag',
        serverUpdatedAt: '2026-08-30T08:00:00.000Z',
        deleted: 0,
        isPendingSync: 0,
      ));

      await cacheService.markDeleted('web-item-to-delete');

      final fetched = await cacheService.getEntry('web-item-to-delete');
      expect(fetched, isNotNull);
      expect(fetched!.deleted, equals(1));
      expect(fetched.isDeleted, isTrue);
      expect(fetched.isPendingSync, equals(1));
      expect(fetched.isPending, isTrue);
      expect(fetched.serverUpdatedAt, isNot(equals('2026-08-30T08:00:00.000Z')));
    });

    test('getPendingSyncEntries and clearPendingSync manage push queue status', () async {
      await cacheService.saveEntry(const LocalVaultCacheEntry(
        id: 'web-synced-item',
        encryptedData: 'c-synced',
        iv: 'iv',
        tag: 'tag',
        serverUpdatedAt: '2026-08-30T09:00:00.000Z',
        isPendingSync: 0,
      ));

      await cacheService.saveEntry(const LocalVaultCacheEntry(
        id: 'web-pending-1',
        encryptedData: 'c-pend-1',
        iv: 'iv',
        tag: 'tag',
        serverUpdatedAt: '2026-08-30T10:00:00.000Z',
        isPendingSync: 1,
      ));

      await cacheService.saveEntry(const LocalVaultCacheEntry(
        id: 'web-pending-2',
        encryptedData: 'c-pend-2',
        iv: 'iv',
        tag: 'tag',
        serverUpdatedAt: '2026-08-30T11:00:00.000Z',
        isPendingSync: 1,
      ));

      final pending = await cacheService.getPendingSyncEntries();
      expect(pending.length, equals(2));
      expect(pending.first.id, equals('web-pending-1'));
      expect(pending.last.id, equals('web-pending-2'));

      // Clear pending status on web-pending-1
      await cacheService.clearPendingSync(
        'web-pending-1',
        serverUpdatedAt: '2026-08-30T15:00:00.000Z',
      );

      final remaining = await cacheService.getPendingSyncEntries();
      expect(remaining.length, equals(1));
      expect(remaining.first.id, equals('web-pending-2'));

      final updated = await cacheService.getEntry('web-pending-1');
      expect(updated!.isPendingSync, equals(0));
      expect(updated.serverUpdatedAt, equals('2026-08-30T15:00:00.000Z'));
    });

    test('deletePermanent removes item from Hive box', () async {
      await cacheService.saveEntry(const LocalVaultCacheEntry(
        id: 'web-perm-target',
        encryptedData: 'data',
        iv: 'iv',
        tag: 'tag',
        serverUpdatedAt: '2026-08-30T10:00:00.000Z',
      ));

      await cacheService.deletePermanent('web-perm-target');

      final result = await cacheService.getEntry('web-perm-target');
      expect(result, isNull);
    });

    test('clearAll wipes all records from Hive box', () async {
      await cacheService.saveEntries([
        const LocalVaultCacheEntry(
          id: 'w1',
          encryptedData: 'd1',
          iv: 'i1',
          tag: 't1',
          serverUpdatedAt: '2026-08-30T10:00:00.000Z',
        ),
        const LocalVaultCacheEntry(
          id: 'w2',
          encryptedData: 'd2',
          iv: 'i2',
          tag: 't2',
          serverUpdatedAt: '2026-08-30T11:00:00.000Z',
        ),
      ]);

      expect((await cacheService.getAllEntries(includeDeleted: true)).length, equals(2));

      await cacheService.clearAll();

      expect((await cacheService.getAllEntries(includeDeleted: true)).isEmpty, isTrue);
    });
  });
}
