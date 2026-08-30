import 'dart:convert';
import 'package:apps/models/local_vault_cache_entry.dart';
import 'package:apps/models/vault_item.dart';
import 'package:apps/providers/vault_notifier.dart';
import 'package:apps/providers/vault_state.dart';
import 'package:apps/repositories/vault_cache_repository.dart';
import 'package:apps/services/crypto_service.dart';
import 'package:apps/services/vault_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeMemoryVaultCacheRepository implements IVaultCacheRepository {
  final Map<String, LocalVaultCacheEntry> _store = {};

  @override
  bool get isOpen => true;

  @override
  Future<void> init({String? customPath}) async {}

  @override
  Future<void> saveEntry(LocalVaultCacheEntry entry) async {
    _store[entry.id] = entry;
  }

  @override
  Future<void> saveEntries(List<LocalVaultCacheEntry> entries) async {
    for (final e in entries) {
      _store[e.id] = e;
    }
  }

  @override
  Future<LocalVaultCacheEntry?> getEntry(String id) async {
    return _store[id];
  }

  @override
  Future<List<LocalVaultCacheEntry>> getAllEntries({bool includeDeleted = false}) async {
    final list = _store.values.where((e) => includeDeleted || !e.isDeleted).toList();
    list.sort((a, b) => b.serverUpdatedDateTime.compareTo(a.serverUpdatedDateTime));
    return list;
  }

  @override
  Future<void> markDeleted(String id) async {
    final existing = _store[id];
    if (existing != null) {
      _store[id] = existing.copyWith(
        deleted: 1,
        isPendingSync: 1,
        serverUpdatedAt: DateTime.now().toUtc().toIso8601String(),
      );
    }
  }

  @override
  Future<List<LocalVaultCacheEntry>> getPendingSyncEntries() async {
    final list = _store.values.where((e) => e.isPending).toList();
    list.sort((a, b) => a.serverUpdatedDateTime.compareTo(b.serverUpdatedDateTime));
    return list;
  }

  @override
  Future<void> clearPendingSync(String id, {String? serverUpdatedAt}) async {
    final existing = _store[id];
    if (existing != null) {
      _store[id] = existing.copyWith(
        isPendingSync: 0,
        serverUpdatedAt: serverUpdatedAt ?? existing.serverUpdatedAt,
      );
    }
  }

  @override
  Future<void> deletePermanent(String id) async {
    _store.remove(id);
  }

  @override
  Future<void> clearAll() async {
    _store.clear();
  }

  @override
  Future<void> close() async {}
}

class FakeOfflineVaultApiService extends VaultApiService {
  bool networkKilled = false;
  int syncCallCount = 0;

  @override
  Future<VaultSyncResult> syncEntries({DateTime? since, int limit = 500}) async {
    syncCallCount++;
    if (networkKilled) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/vault/sync'),
        type: DioExceptionType.connectionError,
        message: 'No internet connection / network killed',
      );
    }
    return VaultSyncResult(
      entries: const [],
      serverTime: DateTime.now().toUtc(),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CryptoService cryptoService;
  late FakeMemoryVaultCacheRepository cacheRepo;
  late FakeOfflineVaultApiService apiService;
  late List<int> sessionKey;

  setUp(() async {
    cryptoService = CryptoService(pbkdf2Iterations: 1000);
    sessionKey = await cryptoService.deriveMasterKey(
      masterPassword: 'MasterPassword123!',
      saltBase64: cryptoService.generateSalt(),
    );

    cacheRepo = FakeMemoryVaultCacheRepository();
    apiService = FakeOfflineVaultApiService();
  });

  group('App Launch Cache-First & Offline Resilience (Task 8.5 / Phase 8 Exit Criteria)', () {
    test('app launch reads cache first and renders ready state instantly with cached items', () async {
      // Pre-populate local cache with 2 encrypted items
      final cachedItem1 = VaultItem(
        id: 'cached-1',
        title: 'Offline Gmail',
        username: 'user@gmail.com',
        password: 'GmailPassword123!',
        updatedAt: DateTime.utc(2026, 8, 30, 10, 0),
      );
      final cachedItem2 = VaultItem(
        id: 'cached-2',
        title: 'Offline Banking Card',
        username: 'Personal Account',
        password: '5544',
        updatedAt: DateTime.utc(2026, 8, 30, 11, 0),
      );

      for (final item in [cachedItem1, cachedItem2]) {
        final encJson = await cryptoService.encryptVaultPayload(
          plaintext: jsonEncode(item.toJson()),
          keyBytes: sessionKey,
        );
        await cacheRepo.saveEntry(LocalVaultCacheEntry.fromEncryptedPayload(
          id: item.id,
          encryptedJson: encJson,
          serverUpdatedAt: item.updatedAt.toUtc().toIso8601String(),
        ));
      }

      final vaultNotifier = VaultNotifier(
        cacheRepository: cacheRepo,
        cryptoService: cryptoService,
        vaultApiService: apiService,
        getSessionKey: () => sessionKey,
        getUserId: () => 'user-1',
      );

      // Trigger app launch load
      await vaultNotifier.loadVault();

      // Verify immediate ready state and decrypted items from cache
      expect(vaultNotifier.state.status, equals(VaultStatus.ready));
      expect(vaultNotifier.state.items.length, equals(2));
      expect(vaultNotifier.state.items.map((i) => i.title), containsAll(['Offline Gmail', 'Offline Banking Card']));
      expect(vaultNotifier.state.items.first.password, equals('Offline Banking Card' == vaultNotifier.state.items.first.title ? '5544' : 'GmailPassword123!'));
    });

    test('killing network access still displays last-synced vault instantly (Phase 8 Exit Criteria)', () async {
      // Simulate network being completely severed
      apiService.networkKilled = true;

      // Populate local cache
      final lastSyncedItem = VaultItem(
        id: 'last-synced-1',
        title: 'Work AWS Console',
        username: 'aws_admin',
        password: 'AwsSecretRootPassword#1',
        updatedAt: DateTime.utc(2026, 8, 30, 12, 0),
      );

      final encJson = await cryptoService.encryptVaultPayload(
        plaintext: jsonEncode(lastSyncedItem.toJson()),
        keyBytes: sessionKey,
      );
      await cacheRepo.saveEntry(LocalVaultCacheEntry.fromEncryptedPayload(
        id: lastSyncedItem.id,
        encryptedJson: encJson,
        serverUpdatedAt: lastSyncedItem.updatedAt.toUtc().toIso8601String(),
      ));

      final vaultNotifier = VaultNotifier(
        cacheRepository: cacheRepo,
        cryptoService: cryptoService,
        vaultApiService: apiService,
        getSessionKey: () => sessionKey,
        getUserId: () => 'user-1',
      );

      // Launch app with dead network
      await vaultNotifier.loadVault();

      // Must still be ready with last-synced entries
      expect(vaultNotifier.state.status, equals(VaultStatus.ready));
      expect(vaultNotifier.state.items.length, equals(1));
      expect(vaultNotifier.state.items.first.title, equals('Work AWS Console'));
      expect(vaultNotifier.state.items.first.password, equals('AwsSecretRootPassword#1'));
      expect(apiService.syncCallCount, equals(1));
    });

    test('locked vault status when session key is missing', () async {
      final vaultNotifier = VaultNotifier(
        cacheRepository: cacheRepo,
        cryptoService: cryptoService,
        vaultApiService: apiService,
        getSessionKey: () => null,
        getUserId: () => 'user-1',
      );

      await vaultNotifier.loadVault();
      expect(vaultNotifier.state.status, equals(VaultStatus.locked));
      expect(vaultNotifier.state.items.isEmpty, isTrue);
    });
  });
}
