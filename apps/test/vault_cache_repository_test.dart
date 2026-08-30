import 'dart:io';
import 'package:apps/models/local_vault_cache_entry.dart';
import 'package:apps/repositories/vault_cache_repository.dart';
import 'package:apps/services/hive_vault_cache_service.dart';
import 'package:apps/services/sqlite_vault_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database sqliteDb;
  late Directory hiveTempDir;
  late Box<Map> hiveBox;

  late SqliteVaultCacheRepository sqliteRepo;
  late HiveVaultCacheRepository hiveRepo;

  setUp(() async {
    // 1. Setup SQLite in-memory
    sqliteDb = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (Database db, int version) async {
          await db.execute(LocalVaultCacheEntry.createTableSql);
        },
      ),
    );
    sqliteRepo = SqliteVaultCacheRepository(
      service: SqliteVaultCacheService(db: sqliteDb),
    );

    // 2. Setup Hive temp box
    hiveTempDir = await Directory.systemTemp.createTemp('hive_repo_test_');
    Hive.init(hiveTempDir.path);
    hiveBox = await Hive.openBox<Map>('repo_vault_box');
    hiveRepo = HiveVaultCacheRepository(
      service: HiveVaultCacheService(box: hiveBox),
    );
  });

  tearDown(() async {
    await sqliteRepo.close();
    await hiveRepo.close();
    await Hive.close();
    if (hiveTempDir.existsSync()) {
      await hiveTempDir.delete(recursive: true);
    }
  });

  void runGenericRepositoryTests(String name, IVaultCacheRepository Function() getRepo) {
    group('IVaultCacheRepository conformance - $name', () {
      test('saveEntry and getEntry stores and fetches record', () async {
        final repo = getRepo();
        const entry = LocalVaultCacheEntry(
          id: 'repo-item-1',
          encryptedData: 'c-123',
          iv: 'iv-1',
          tag: 'tag-1',
          serverUpdatedAt: '2026-08-30T10:00:00.000Z',
          isPendingSync: 1,
        );

        await repo.saveEntry(entry);

        final fetched = await repo.getEntry('repo-item-1');
        expect(fetched, isNotNull);
        expect(fetched!.id, equals('repo-item-1'));
        expect(fetched.encryptedData, equals('c-123'));
        expect(fetched.isPending, isTrue);
        expect(fetched.isDeleted, isFalse);
      });

      test('saveEntries and getAllEntries sorts by server_updated_at DESC and filters deleted', () async {
        final repo = getRepo();
        final entries = [
          const LocalVaultCacheEntry(
            id: 'e1',
            encryptedData: 'c1',
            iv: 'i1',
            tag: 't1',
            serverUpdatedAt: '2026-08-30T09:00:00.000Z',
            deleted: 0,
          ),
          const LocalVaultCacheEntry(
            id: 'e2',
            encryptedData: 'c2',
            iv: 'i2',
            tag: 't2',
            serverUpdatedAt: '2026-08-30T11:00:00.000Z',
            deleted: 0,
          ),
          const LocalVaultCacheEntry(
            id: 'e3',
            encryptedData: 'c3',
            iv: 'i3',
            tag: 't3',
            serverUpdatedAt: '2026-08-30T12:00:00.000Z',
            deleted: 1, // tombstone
          ),
        ];

        await repo.saveEntries(entries);

        // Active only
        final active = await repo.getAllEntries(includeDeleted: false);
        expect(active.length, equals(2));
        expect(active.first.id, equals('e2'));
        expect(active.last.id, equals('e1'));

        // All including tombstones
        final all = await repo.getAllEntries(includeDeleted: true);
        expect(all.length, equals(3));
        expect(all.first.id, equals('e3'));
      });

      test('markDeleted, getPendingSyncEntries, and clearPendingSync', () async {
        final repo = getRepo();
        await repo.saveEntry(const LocalVaultCacheEntry(
          id: 'target-item',
          encryptedData: 'data',
          iv: 'iv',
          tag: 'tag',
          serverUpdatedAt: '2026-08-30T08:00:00.000Z',
          isPendingSync: 0,
        ));

        await repo.markDeleted('target-item');

        final pending = await repo.getPendingSyncEntries();
        expect(pending.length, equals(1));
        expect(pending.first.id, equals('target-item'));
        expect(pending.first.isDeleted, isTrue);
        expect(pending.first.isPending, isTrue);

        // Clear pending sync
        await repo.clearPendingSync(
          'target-item',
          serverUpdatedAt: '2026-08-30T16:00:00.000Z',
        );

        final pendingAfter = await repo.getPendingSyncEntries();
        expect(pendingAfter.isEmpty, isTrue);
      });

      test('deletePermanent and clearAll wipe items cleanly', () async {
        final repo = getRepo();
        await repo.saveEntries([
          const LocalVaultCacheEntry(
            id: 'del-1',
            encryptedData: 'c1',
            iv: 'i1',
            tag: 't1',
            serverUpdatedAt: '2026-08-30T10:00:00.000Z',
          ),
          const LocalVaultCacheEntry(
            id: 'del-2',
            encryptedData: 'c2',
            iv: 'i2',
            tag: 't2',
            serverUpdatedAt: '2026-08-30T11:00:00.000Z',
          ),
        ]);

        await repo.deletePermanent('del-1');
        expect(await repo.getEntry('del-1'), isNull);
        expect(await repo.getEntry('del-2'), isNotNull);

        await repo.clearAll();
        expect((await repo.getAllEntries(includeDeleted: true)).isEmpty, isTrue);
      });
    });
  }

  // Run suite against both SQLite and Hive implementations
  runGenericRepositoryTests('SqliteVaultCacheRepository', () => sqliteRepo);
  runGenericRepositoryTests('HiveVaultCacheRepository', () => hiveRepo);

  test('VaultCacheRepository.create factory instantiates platform-appropriate repository', () {
    final repo = VaultCacheRepository.create();
    expect(repo, isA<IVaultCacheRepository>());
  });
}
