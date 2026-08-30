import 'package:apps/models/local_vault_cache_entry.dart';
import 'package:apps/services/sqlite_vault_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Initialize FFI for headless testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late SqliteVaultCacheService cacheService;

  setUp(() async {
    // Open in-memory SQLite database
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (Database db, int version) async {
          await db.execute(LocalVaultCacheEntry.createTableSql);
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_local_vault_cache_updated 
            ON ${LocalVaultCacheEntry.tableName} (server_updated_at DESC)
          ''');
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_local_vault_cache_pending 
            ON ${LocalVaultCacheEntry.tableName} (is_pending_sync)
          ''');
        },
      ),
    );

    cacheService = SqliteVaultCacheService(db: db);
  });

  tearDown(() async {
    await cacheService.close();
  });

  group('SqliteVaultCacheService (Task 8.2 / sqflite Android Implementation)', () {
    test('saveEntry and getEntry stores and retrieves LocalVaultCacheEntry correctly', () async {
      const entry = LocalVaultCacheEntry(
        id: 'entry-1',
        encryptedData: 'cipher-text-12345',
        iv: 'iv-123',
        tag: 'tag-456',
        serverUpdatedAt: '2026-08-30T14:00:00.000Z',
        deleted: 0,
        isPendingSync: 1,
      );

      await cacheService.saveEntry(entry);

      final fetched = await cacheService.getEntry('entry-1');
      expect(fetched, isNotNull);
      expect(fetched!.id, equals('entry-1'));
      expect(fetched.encryptedData, equals('cipher-text-12345'));
      expect(fetched.iv, equals('iv-123'));
      expect(fetched.tag, equals('tag-456'));
      expect(fetched.serverUpdatedAt, equals('2026-08-30T14:00:00.000Z'));
      expect(fetched.deleted, equals(0));
      expect(fetched.isPendingSync, equals(1));
      expect(fetched.isDeleted, isFalse);
      expect(fetched.isPending, isTrue);
    });

    test('saveEntries batch-inserts multiple records', () async {
      final entries = [
        const LocalVaultCacheEntry(
          id: 'item-1',
          encryptedData: 'cipher-1',
          iv: 'iv-1',
          tag: 'tag-1',
          serverUpdatedAt: '2026-08-30T10:00:00.000Z',
        ),
        const LocalVaultCacheEntry(
          id: 'item-2',
          encryptedData: 'cipher-2',
          iv: 'iv-2',
          tag: 'tag-2',
          serverUpdatedAt: '2026-08-30T11:00:00.000Z',
        ),
        const LocalVaultCacheEntry(
          id: 'item-3',
          encryptedData: 'cipher-3',
          iv: 'iv-3',
          tag: 'tag-3',
          serverUpdatedAt: '2026-08-30T12:00:00.000Z',
        ),
      ];

      await cacheService.saveEntries(entries);

      final all = await cacheService.getAllEntries();
      expect(all.length, equals(3));
      // Ordered by server_updated_at DESC
      expect(all.first.id, equals('item-3'));
      expect(all.last.id, equals('item-1'));
    });

    test('getAllEntries filters out deleted tombstones by default and includes when requested', () async {
      await cacheService.saveEntry(const LocalVaultCacheEntry(
        id: 'active-1',
        encryptedData: 'c1',
        iv: 'i1',
        tag: 't1',
        serverUpdatedAt: '2026-08-30T10:00:00.000Z',
        deleted: 0,
      ));

      await cacheService.saveEntry(const LocalVaultCacheEntry(
        id: 'deleted-1',
        encryptedData: 'c2',
        iv: 'i2',
        tag: 't2',
        serverUpdatedAt: '2026-08-30T12:00:00.000Z',
        deleted: 1,
      ));

      // Without deleted
      final activeList = await cacheService.getAllEntries(includeDeleted: false);
      expect(activeList.length, equals(1));
      expect(activeList.first.id, equals('active-1'));

      // With deleted tombstones
      final allList = await cacheService.getAllEntries(includeDeleted: true);
      expect(allList.length, equals(2));
      expect(allList.first.id, equals('deleted-1'));
    });

    test('markDeleted soft-deletes item, sets is_pending_sync = 1, and advances server_updated_at', () async {
      await cacheService.saveEntry(const LocalVaultCacheEntry(
        id: 'item-to-delete',
        encryptedData: 'c-del',
        iv: 'iv',
        tag: 'tag',
        serverUpdatedAt: '2026-08-30T08:00:00.000Z',
        deleted: 0,
        isPendingSync: 0,
      ));

      await cacheService.markDeleted('item-to-delete');

      final fetched = await cacheService.getEntry('item-to-delete');
      expect(fetched, isNotNull);
      expect(fetched!.deleted, equals(1));
      expect(fetched.isDeleted, isTrue);
      expect(fetched.isPendingSync, equals(1));
      expect(fetched.isPending, isTrue);
      expect(fetched.serverUpdatedAt, isNot(equals('2026-08-30T08:00:00.000Z')));
    });

    test('getPendingSyncEntries and clearPendingSync manage push queue status', () async {
      await cacheService.saveEntry(const LocalVaultCacheEntry(
        id: 'synced-item',
        encryptedData: 'c-synced',
        iv: 'iv',
        tag: 'tag',
        serverUpdatedAt: '2026-08-30T09:00:00.000Z',
        isPendingSync: 0,
      ));

      await cacheService.saveEntry(const LocalVaultCacheEntry(
        id: 'pending-item-1',
        encryptedData: 'c-pend-1',
        iv: 'iv',
        tag: 'tag',
        serverUpdatedAt: '2026-08-30T10:00:00.000Z',
        isPendingSync: 1,
      ));

      await cacheService.saveEntry(const LocalVaultCacheEntry(
        id: 'pending-item-2',
        encryptedData: 'c-pend-2',
        iv: 'iv',
        tag: 'tag',
        serverUpdatedAt: '2026-08-30T11:00:00.000Z',
        isPendingSync: 1,
      ));

      final pending = await cacheService.getPendingSyncEntries();
      expect(pending.length, equals(2));
      expect(pending.first.id, equals('pending-item-1'));
      expect(pending.last.id, equals('pending-item-2'));

      // Clear pending status on item-1
      await cacheService.clearPendingSync(
        'pending-item-1',
        serverUpdatedAt: '2026-08-30T15:00:00.000Z',
      );

      final remaining = await cacheService.getPendingSyncEntries();
      expect(remaining.length, equals(1));
      expect(remaining.first.id, equals('pending-item-2'));

      final updated = await cacheService.getEntry('pending-item-1');
      expect(updated!.isPendingSync, equals(0));
      expect(updated.serverUpdatedAt, equals('2026-08-30T15:00:00.000Z'));
    });

    test('deletePermanent removes row from database table', () async {
      await cacheService.saveEntry(const LocalVaultCacheEntry(
        id: 'perm-delete-target',
        encryptedData: 'data',
        iv: 'iv',
        tag: 'tag',
        serverUpdatedAt: '2026-08-30T10:00:00.000Z',
      ));

      await cacheService.deletePermanent('perm-delete-target');

      final result = await cacheService.getEntry('perm-delete-target');
      expect(result, isNull);
    });

    test('clearAll wipes all records from local_vault_cache table', () async {
      await cacheService.saveEntries([
        const LocalVaultCacheEntry(
          id: 'i1',
          encryptedData: 'd1',
          iv: 'i1',
          tag: 't1',
          serverUpdatedAt: '2026-08-30T10:00:00.000Z',
        ),
        const LocalVaultCacheEntry(
          id: 'i2',
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
