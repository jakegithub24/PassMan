import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:apps/models/encrypted_vault_entry.dart';
import 'package:apps/services/local_vault_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Initialize FFI for in-memory SQLite testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late LocalVaultStorageService storageService;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (Database db, int version) async {
          await db.execute('''
            CREATE TABLE ${LocalVaultStorageService.tableName} (
              id TEXT PRIMARY KEY,
              user_id TEXT NOT NULL,
              encrypted_data TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              deleted_at TEXT,
              is_dirty INTEGER NOT NULL DEFAULT 0
            )
          ''');
        },
      ),
    );
    storageService = LocalVaultStorageService(sqliteDb: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('LocalVaultStorageService SQLite Tests', () {
    test('saveEntry and getEntry', () async {
      final now = DateTime.now().toUtc();
      final entry = EncryptedVaultEntry(
        id: 'entry-1',
        userId: 'user-1',
        encryptedData: '{"ciphertext":"c1","iv":"iv1","tag":"t1"}',
        updatedAt: now,
      );

      await storageService.saveEntry(entry, isDirty: true);

      final retrieved = await storageService.getEntry('entry-1');
      expect(retrieved, isNotNull);
      expect(retrieved!.id, equals('entry-1'));
      expect(retrieved.userId, equals('user-1'));
      expect(retrieved.encryptedData, equals(entry.encryptedData));
      expect(retrieved.isDeleted, isFalse);

      final dirtyList = await storageService.getDirtyEntries();
      expect(dirtyList.length, equals(1));
      expect(dirtyList.first.id, equals('entry-1'));
    });

    test('bulk saveEntries and getAllEntries filtering', () async {
      final now = DateTime.now().toUtc();
      final e1 = EncryptedVaultEntry(
        id: 'e1',
        userId: 'u1',
        encryptedData: 'c1',
        updatedAt: now,
      );
      final e2 = EncryptedVaultEntry(
        id: 'e2',
        userId: 'u1',
        encryptedData: 'c2',
        updatedAt: now.add(const Duration(seconds: 1)),
      );

      await storageService.saveEntries([e1, e2], isDirty: false);

      final allActive = await storageService.getAllEntries();
      expect(allActive.length, equals(2));
      expect(allActive.first.id, equals('e2')); // Ordered by updatedAt DESC

      // Soft delete e1
      await storageService.markDeleted('e1');

      final activeAfterDelete = await storageService.getAllEntries(includeDeleted: false);
      expect(activeAfterDelete.length, equals(1));
      expect(activeAfterDelete.first.id, equals('e2'));

      final allIncludingDeleted = await storageService.getAllEntries(includeDeleted: true);
      expect(allIncludingDeleted.length, equals(2));

      // e1 should now be dirty
      final dirty = await storageService.getDirtyEntries();
      expect(dirty.length, equals(1));
      expect(dirty.first.id, equals('e1'));
    });

    test('clearDirty clears synchronization flags', () async {
      final now = DateTime.now().toUtc();
      final e1 = EncryptedVaultEntry(id: 'e1', userId: 'u1', encryptedData: 'c1', updatedAt: now);
      final e2 = EncryptedVaultEntry(id: 'e2', userId: 'u1', encryptedData: 'c2', updatedAt: now);

      await storageService.saveEntry(e1, isDirty: true);
      await storageService.saveEntry(e2, isDirty: true);

      expect((await storageService.getDirtyEntries()).length, equals(2));

      await storageService.clearDirty(['e1']);

      final remainingDirty = await storageService.getDirtyEntries();
      expect(remainingDirty.length, equals(1));
      expect(remainingDirty.first.id, equals('e2'));
    });

    test('clearAll wipes database table', () async {
      final now = DateTime.now().toUtc();
      final e1 = EncryptedVaultEntry(id: 'e1', userId: 'u1', encryptedData: 'c1', updatedAt: now);
      await storageService.saveEntry(e1);

      expect((await storageService.getAllEntries()).length, equals(1));

      await storageService.clearAll();
      expect((await storageService.getAllEntries()).length, equals(0));
    });
  });
}
