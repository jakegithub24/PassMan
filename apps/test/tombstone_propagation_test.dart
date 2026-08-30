import 'package:apps/models/encrypted_vault_entry.dart';
import 'package:apps/models/local_vault_cache_entry.dart';
import 'package:apps/providers/providers.dart';
import 'package:apps/repositories/vault_cache_repository.dart';
import 'package:apps/services/crypto_service.dart';
import 'package:apps/services/vault_api_service.dart';
import 'package:flutter_test/flutter_test.dart';

class TombstoneCentralServer {
  final Map<String, EncryptedVaultEntry> entries = {};
  DateTime serverClock = DateTime.utc(2026, 8, 30, 14, 0);

  VaultApiService createClient() => _TombstoneClientApiService(this);
}

class _TombstoneClientApiService extends VaultApiService {
  final TombstoneCentralServer server;

  _TombstoneClientApiService(this.server);

  @override
  Future<EncryptedVaultEntry> createEntry(String encryptedData) async {
    server.serverClock = server.serverClock.add(const Duration(seconds: 10));
    final id = 'tombstone-item-${server.entries.length + 1}';
    final entry = EncryptedVaultEntry(
      id: id,
      userId: 'test-user-456',
      encryptedData: encryptedData,
      updatedAt: server.serverClock,
    );
    server.entries[id] = entry;
    return entry;
  }

  @override
  Future<EncryptedVaultEntry> updateEntry(String entryId, String encryptedData) async {
    server.serverClock = server.serverClock.add(const Duration(seconds: 10));
    final existing = server.entries[entryId];
    final entry = EncryptedVaultEntry(
      id: entryId,
      userId: 'test-user-456',
      encryptedData: encryptedData,
      updatedAt: server.serverClock,
      deletedAt: existing?.deletedAt,
    );
    server.entries[entryId] = entry;
    return entry;
  }

  @override
  Future<bool> deleteEntry(String entryId) async {
    server.serverClock = server.serverClock.add(const Duration(seconds: 10));
    final existing = server.entries[entryId];
    if (existing != null) {
      server.entries[entryId] = EncryptedVaultEntry(
        id: entryId,
        userId: existing.userId,
        encryptedData: existing.encryptedData,
        updatedAt: server.serverClock,
        deletedAt: server.serverClock, // Server tombstone timestamp
      );
    }
    return true;
  }

  @override
  Future<VaultSyncResult> syncEntries({DateTime? since, int limit = 500}) async {
    final list = server.entries.values.where((e) {
      if (since == null) return true;
      return e.updatedAt.isAfter(since);
    }).toList();

    return VaultSyncResult(
      entries: list,
      serverTime: server.serverClock,
    );
  }
}

class InMemoryTombstoneRepo implements IVaultCacheRepository {
  final Map<String, LocalVaultCacheEntry> table = {};

  @override
  bool get isOpen => true;

  @override
  Future<void> init({String? customPath}) async {}

  @override
  Future<void> saveEntry(LocalVaultCacheEntry entry) async => table[entry.id] = entry;

  @override
  Future<void> saveEntries(List<LocalVaultCacheEntry> entries) async {
    for (final e in entries) {
      table[e.id] = e;
    }
  }

  @override
  Future<LocalVaultCacheEntry?> getEntry(String id) async => table[id];

  @override
  Future<List<LocalVaultCacheEntry>> getAllEntries({bool includeDeleted = false}) async {
    final list = table.values.where((e) => includeDeleted || !e.isDeleted).toList();
    list.sort((a, b) => b.serverUpdatedDateTime.compareTo(a.serverUpdatedDateTime));
    return list;
  }

  @override
  Future<void> markDeleted(String id) async {
    final existing = table[id];
    if (existing != null) {
      table[id] = existing.copyWith(
        deleted: 1,
        isPendingSync: 1,
        serverUpdatedAt: DateTime.now().toUtc().toIso8601String(),
      );
    }
  }

  @override
  Future<List<LocalVaultCacheEntry>> getPendingSyncEntries() async {
    return table.values.where((e) => e.isPending).toList();
  }

  @override
  Future<void> clearPendingSync(String id, {String? serverUpdatedAt}) async {
    final existing = table[id];
    if (existing != null) {
      table[id] = existing.copyWith(
        isPendingSync: 0,
        serverUpdatedAt: serverUpdatedAt ?? existing.serverUpdatedAt,
      );
    }
  }

  @override
  Future<void> deletePermanent(String id) async => table.remove(id);

  @override
  Future<void> clearAll() async => table.clear();

  @override
  Future<void> close() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CryptoService cryptoService;
  late List<int> sessionKey;

  setUp(() async {
    cryptoService = CryptoService(pbkdf2Iterations: 1000);
    sessionKey = await cryptoService.deriveMasterKey(
      masterPassword: 'TombstonePassword2026!',
      saltBase64: cryptoService.generateSalt(),
    );
  });

  group('Task 11.4: Delete Propagation Across Devices (Tombstone)', () {
    test('Device A deletes item -> tombstone syncs to Server -> Device B reflects deletion immediately', () async {
      final server = TombstoneCentralServer();

      // Device A setup
      final repoA = InMemoryTombstoneRepo();
      final clientA = server.createClient();
      final notifierA = VaultNotifier(
        cacheRepository: repoA,
        cryptoService: cryptoService,
        vaultApiService: clientA,
        getSessionKey: () => sessionKey,
        getUserId: () => 'test-user-456',
      );

      // Device B setup
      final repoB = InMemoryTombstoneRepo();
      final clientB = server.createClient();
      final notifierB = VaultNotifier(
        cacheRepository: repoB,
        cryptoService: cryptoService,
        vaultApiService: clientB,
        getSessionKey: () => sessionKey,
        getUserId: () => 'test-user-456',
      );

      // 1. Device A creates 3 items online
      final item1 = await notifierA.addEntry(
        title: 'Legacy Server SSH Key',
        username: 'root@legacy.host',
        password: 'OldRootPass123!',
      );
      final item2 = await notifierA.addEntry(
        title: 'Production Database Credential',
        username: 'db_admin',
        password: 'PostgresSecret456!',
      );
      final item3 = await notifierA.addEntry(
        title: 'Marketing Twitter',
        username: 'marketing_team',
        password: 'TwitterPass789!',
      );

      expect(item1, isNotNull);
      expect(item2, isNotNull);
      expect(item3, isNotNull);
      expect(server.entries.length, equals(3));

      // 2. Device B syncs initial vault
      await notifierB.loadVault(syncRemote: true);
      expect(notifierB.state.items.length, equals(3));

      // 3. Device A deletes item 1 ('Legacy Server SSH Key')
      final deleteSuccess = await notifierA.deleteEntry(item1!.id);
      expect(deleteSuccess, isTrue);
      expect(notifierA.state.items.length, equals(2));
      expect(notifierA.state.items.any((i) => i.id == item1.id), isFalse);

      // Verify server has tombstone for item1
      expect(server.entries[item1.id]!.deletedAt, isNotNull);

      // 4. Device B syncs with server (delta fetch receives tombstone)
      await notifierB.syncWithServer();

      // 5. Verify Device B immediately removes item1 from state and marks tombstone in local cache
      expect(notifierB.state.items.length, equals(2));
      expect(notifierB.state.items.any((i) => i.id == item1.id), isFalse);

      // Verify surviving items on Device B
      final titlesOnB = notifierB.state.items.map((i) => i.title).toSet();
      expect(titlesOnB, contains('Production Database Credential'));
      expect(titlesOnB, contains('Marketing Twitter'));

      // Verify Device B local cache has tombstone recorded
      final cachedItem1OnB = await repoB.getEntry(item1.id);
      expect(cachedItem1OnB, isNotNull);
      expect(cachedItem1OnB!.isDeleted, isTrue);
    });

    test('Multiple concurrent device deletes propagate clean tombstones without ghost items', () async {
      final server = TombstoneCentralServer();

      final repoA = InMemoryTombstoneRepo();
      final notifierA = VaultNotifier(
        cacheRepository: repoA,
        cryptoService: cryptoService,
        vaultApiService: server.createClient(),
        getSessionKey: () => sessionKey,
        getUserId: () => 'test-user-456',
      );

      final repoB = InMemoryTombstoneRepo();
      final notifierB = VaultNotifier(
        cacheRepository: repoB,
        cryptoService: cryptoService,
        vaultApiService: server.createClient(),
        getSessionKey: () => sessionKey,
        getUserId: () => 'test-user-456',
      );

      // Add item on A
      final item = (await notifierA.addEntry(
        title: 'Temporary Token',
        username: 'temp',
        password: 'TemporaryPassword!',
      ))!;

      // Sync B
      await notifierB.loadVault(syncRemote: true);
      expect(notifierB.state.items.length, equals(1));

      // Device B deletes the item
      await notifierB.deleteEntry(item.id);
      expect(notifierB.state.items.isEmpty, isTrue);

      // Device A syncs and deletes locally too
      await notifierA.syncWithServer();
      expect(notifierA.state.items.isEmpty, isTrue);
    });
  });
}
