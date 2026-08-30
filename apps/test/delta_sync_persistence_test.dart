import 'dart:convert';
import 'package:apps/models/encrypted_vault_entry.dart';
import 'package:apps/models/local_vault_cache_entry.dart';
import 'package:apps/models/vault_item.dart';
import 'package:apps/providers/vault_notifier.dart';
import 'package:apps/repositories/vault_cache_repository.dart';
import 'package:apps/services/crypto_service.dart';
import 'package:apps/services/secure_storage_service.dart';
import 'package:apps/services/vault_api_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeTrackingVaultApiService extends VaultApiService {
  DateTime? lastPassedSince;
  List<EncryptedVaultEntry> returnEntries = [];
  DateTime serverTime = DateTime.utc(2026, 8, 30, 18, 0);

  @override
  Future<VaultSyncResult> syncEntries({DateTime? since, int limit = 500}) async {
    lastPassedSince = since;
    return VaultSyncResult(
      entries: returnEntries,
      serverTime: serverTime,
    );
  }
}

class FakeMemoryCacheRepo implements IVaultCacheRepository {
  final Map<String, LocalVaultCacheEntry> store = {};

  @override
  bool get isOpen => true;

  @override
  Future<void> init({String? customPath}) async {}

  @override
  Future<void> saveEntry(LocalVaultCacheEntry entry) async {
    store[entry.id] = entry;
  }

  @override
  Future<void> saveEntries(List<LocalVaultCacheEntry> entries) async {
    for (final e in entries) {
      store[e.id] = e;
    }
  }

  @override
  Future<LocalVaultCacheEntry?> getEntry(String id) async => store[id];

  @override
  Future<List<LocalVaultCacheEntry>> getAllEntries({bool includeDeleted = false}) async {
    final list = store.values.where((e) => includeDeleted || !e.isDeleted).toList();
    list.sort((a, b) => b.serverUpdatedDateTime.compareTo(a.serverUpdatedDateTime));
    return list;
  }

  @override
  Future<void> markDeleted(String id) async {
    final existing = store[id];
    if (existing != null) {
      store[id] = existing.copyWith(
        deleted: 1,
        serverUpdatedAt: DateTime.now().toUtc().toIso8601String(),
      );
    }
  }

  @override
  Future<List<LocalVaultCacheEntry>> getPendingSyncEntries() async => [];

  @override
  Future<void> clearPendingSync(String id, {String? serverUpdatedAt}) async {}

  @override
  Future<void> deletePermanent(String id) async => store.remove(id);

  @override
  Future<void> clearAll() async => store.clear();

  @override
  Future<void> close() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  late SecureStorageService secureStorage;
  late CryptoService cryptoService;
  late FakeMemoryCacheRepo cacheRepo;
  late FakeTrackingVaultApiService apiService;
  late List<int> sessionKey;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    secureStorage = SecureStorageService();
    cryptoService = CryptoService(pbkdf2Iterations: 1000);
    cacheRepo = FakeMemoryCacheRepo();
    apiService = FakeTrackingVaultApiService();

    sessionKey = await cryptoService.deriveMasterKey(
      masterPassword: 'MasterPassword123!',
      saltBase64: cryptoService.generateSalt(),
    );
  });

  group('Delta Fetch & last_synced_at Persistence (Task 9.2 / MVP.md §6)', () {
    test('SecureStorageService saves, retrieves, and clears last_synced_at timestamp', () async {
      expect(await secureStorage.getLastSyncedAt(userId: 'u1'), isNull);

      final syncTime = DateTime.utc(2026, 8, 30, 15, 30, 0);
      await secureStorage.saveLastSyncedAt(syncTime, userId: 'u1');

      final fetched = await secureStorage.getLastSyncedAt(userId: 'u1');
      expect(fetched, isNotNull);
      expect(fetched!.toIso8601String(), equals(syncTime.toIso8601String()));

      await secureStorage.clearLastSyncedAt(userId: 'u1');
      expect(await secureStorage.getLastSyncedAt(userId: 'u1'), isNull);
    });

    test('Initial sync passes since = null and persists server timestamp', () async {
      final item = VaultItem(
        id: 'remote-1',
        title: 'Remote Delta Item',
        username: 'remote@user.com',
        password: 'Password999!',
        updatedAt: DateTime.utc(2026, 8, 30, 14, 0),
      );
      final encPayload = await cryptoService.encryptVaultPayload(
        plaintext: jsonEncode(item.toJson()),
        keyBytes: sessionKey,
      );

      apiService.returnEntries = [
        EncryptedVaultEntry(
          id: item.id,
          userId: 'u1',
          encryptedData: encPayload,
          updatedAt: item.updatedAt,
        ),
      ];
      apiService.serverTime = DateTime.utc(2026, 8, 30, 18, 45, 0);

      final notifier = VaultNotifier(
        cacheRepository: cacheRepo,
        secureStorage: secureStorage,
        cryptoService: cryptoService,
        vaultApiService: apiService,
        getSessionKey: () => sessionKey,
        getUserId: () => 'u1',
      );

      await notifier.loadVault(syncRemote: true);

      // Verify since was null on first sync
      expect(apiService.lastPassedSince, isNull);

      // Verify serverTime was persisted in secure storage
      final persistedLastSync = await secureStorage.getLastSyncedAt(userId: 'u1');
      expect(persistedLastSync, isNotNull);
      expect(persistedLastSync!.toIso8601String(), equals(apiService.serverTime.toIso8601String()));

      // Verify item was stored in cache and decrypted into state
      expect(notifier.state.items.length, equals(1));
      expect(notifier.state.items.first.title, equals('Remote Delta Item'));
    });

    test('Subsequent sync sends persisted last_synced_at as since query parameter', () async {
      final initialSyncTime = DateTime.utc(2026, 8, 30, 12, 0, 0);
      await secureStorage.saveLastSyncedAt(initialSyncTime, userId: 'u1');

      apiService.serverTime = DateTime.utc(2026, 8, 30, 19, 0, 0);
      apiService.returnEntries = [];

      final notifier = VaultNotifier(
        cacheRepository: cacheRepo,
        secureStorage: secureStorage,
        cryptoService: cryptoService,
        vaultApiService: apiService,
        getSessionKey: () => sessionKey,
        getUserId: () => 'u1',
      );

      await notifier.syncWithServer();

      // Verify since was sent with initialSyncTime
      expect(apiService.lastPassedSince, isNotNull);
      expect(apiService.lastPassedSince!.toIso8601String(), equals(initialSyncTime.toIso8601String()));

      // Verify last_synced_at updated to new serverTime
      final updatedLastSync = await secureStorage.getLastSyncedAt(userId: 'u1');
      expect(updatedLastSync!.toIso8601String(), equals(apiService.serverTime.toIso8601String()));
    });
  });
}
