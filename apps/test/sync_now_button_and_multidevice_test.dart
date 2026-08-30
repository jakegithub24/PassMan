import 'dart:convert';
import 'package:apps/models/encrypted_vault_entry.dart';
import 'package:apps/models/local_vault_cache_entry.dart';
import 'package:apps/models/vault_item.dart';
import 'package:apps/providers/providers.dart';
import 'package:apps/repositories/vault_cache_repository.dart';
import 'package:apps/screens/vault_list_screen.dart';
import 'package:apps/services/crypto_service.dart';
import 'package:apps/services/vault_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class SharedTestServer {
  final Map<String, EncryptedVaultEntry> serverDb = {};
  DateTime serverTime = DateTime.utc(2026, 8, 30, 10, 0);

  VaultApiService createClient() {
    return _SharedTestVaultApiService(this);
  }
}

class _SharedTestVaultApiService extends VaultApiService {
  final SharedTestServer _server;

  _SharedTestVaultApiService(this._server);

  @override
  Future<EncryptedVaultEntry> createEntry(String encryptedData) async {
    _server.serverTime = _server.serverTime.add(const Duration(minutes: 1));
    String id = 'server-entry-${_server.serverDb.length + 1}';
    try {
      final decoded = jsonDecode(encryptedData) as Map<String, dynamic>;
      if (decoded.containsKey('id') && decoded['id'] != null) {
        id = decoded['id'] as String;
      }
    } catch (_) {}

    final entry = EncryptedVaultEntry(
      id: id,
      userId: 'test-user',
      encryptedData: encryptedData,
      updatedAt: _server.serverTime,
    );
    _server.serverDb[id] = entry;
    return entry;
  }

  @override
  Future<EncryptedVaultEntry> updateEntry(String entryId, String encryptedData) async {
    _server.serverTime = _server.serverTime.add(const Duration(minutes: 1));
    final existing = _server.serverDb[entryId];
    final entry = EncryptedVaultEntry(
      id: entryId,
      userId: 'test-user',
      encryptedData: encryptedData,
      updatedAt: _server.serverTime,
      deletedAt: existing?.deletedAt,
    );
    _server.serverDb[entryId] = entry;
    return entry;
  }

  @override
  Future<bool> deleteEntry(String entryId) async {
    _server.serverTime = _server.serverTime.add(const Duration(minutes: 1));
    final existing = _server.serverDb[entryId];
    if (existing != null) {
      _server.serverDb[entryId] = EncryptedVaultEntry(
        id: entryId,
        userId: existing.userId,
        encryptedData: existing.encryptedData,
        updatedAt: _server.serverTime,
        deletedAt: _server.serverTime,
      );
    }
    return true;
  }

  @override
  Future<VaultSyncResult> syncEntries({DateTime? since, int limit = 500}) async {
    final entries = _server.serverDb.values.where((e) {
      if (since == null) return true;
      return e.updatedAt.isAfter(since);
    }).toList();

    return VaultSyncResult(
      entries: entries,
      serverTime: _server.serverTime,
    );
  }
}

class MemoryDeviceCacheRepo implements IVaultCacheRepository {
  final Map<String, LocalVaultCacheEntry> store = {};

  @override
  bool get isOpen => true;

  @override
  Future<void> init({String? customPath}) async {}

  @override
  Future<void> saveEntry(LocalVaultCacheEntry entry) async => store[entry.id] = entry;

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
        isPendingSync: 1,
        serverUpdatedAt: DateTime.now().toUtc().toIso8601String(),
      );
    }
  }

  @override
  Future<List<LocalVaultCacheEntry>> getPendingSyncEntries() async {
    return store.values.where((e) => e.isPending).toList();
  }

  @override
  Future<void> clearPendingSync(String id, {String? serverUpdatedAt}) async {
    final existing = store[id];
    if (existing != null) {
      store[id] = existing.copyWith(
        isPendingSync: 0,
        serverUpdatedAt: serverUpdatedAt ?? existing.serverUpdatedAt,
      );
    }
  }

  @override
  Future<void> deletePermanent(String id) async => store.remove(id);

  @override
  Future<void> clearAll() async => store.clear();

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
      masterPassword: 'SharedMasterPassword123!',
      saltBase64: cryptoService.generateSalt(),
    );
  });

  group('Sync Now Button & Two-Device End-to-End Sync (Task 9.5 / Phase 5 Exit Criteria)', () {
    testWidgets('Sync Now button in VaultListScreen triggers sync and shows tooltip', (tester) async {
      final cacheRepo = MemoryDeviceCacheRepo();
      final vaultNotifier = VaultNotifier(
        cacheRepository: cacheRepo,
        cryptoService: cryptoService,
        getSessionKey: () => sessionKey,
        getUserId: () => 'u1',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultStateProvider.overrideWith((ref) => vaultNotifier),
            sessionKeyProvider.overrideWithValue(sessionKey),
          ],
          child: const MaterialApp(
            home: VaultListScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find Sync Now button
      final syncButton = find.byTooltip('Sync Now');
      expect(syncButton, findsWidgets);

      // Tap Sync Now
      await tester.tap(syncButton.first);
      await tester.pumpAndSettle();

      expect(vaultNotifier.state.status, equals(VaultStatus.ready));
    });

    test('Two-device sync test: Device A modifies offline, syncs; Device B syncs and reflects changes (Exit Criteria)', () async {
      final sharedServer = SharedTestServer();

      // 1. Setup Device A
      final cacheA = MemoryDeviceCacheRepo();
      final clientA = sharedServer.createClient();
      final notifierA = VaultNotifier(
        cacheRepository: cacheA,
        cryptoService: cryptoService,
        vaultApiService: clientA,
        getSessionKey: () => sessionKey,
        getUserId: () => 'user-1',
      );

      // 2. Setup Device B
      final cacheB = MemoryDeviceCacheRepo();
      final clientB = sharedServer.createClient();
      final notifierB = VaultNotifier(
        cacheRepository: cacheB,
        cryptoService: cryptoService,
        vaultApiService: clientB,
        getSessionKey: () => sessionKey,
        getUserId: () => 'user-1',
      );

      // Step A: Device A creates entry while online
      final addedItem = await notifierA.addEntry(
        title: 'Initial GitHub Account',
        username: 'dev@company.com',
        password: 'PasswordOriginal123!',
        category: 'logins',
      );
      expect(addedItem, isNotNull);

      // Step B: Device B syncs and receives Initial GitHub Account
      await notifierB.loadVault(syncRemote: true);
      expect(notifierB.state.items.length, equals(1));
      expect(notifierB.state.items.first.title, equals('Initial GitHub Account'));

      // Step C: Device A modifies entry offline
      final entryA = (await cacheA.getAllEntries()).first;
      final updatedItem = VaultItem(
        id: entryA.id,
        title: 'Updated GitHub Enterprise',
        username: 'dev@company.com',
        password: 'NewSuperSecretPass#99',
        category: 'logins',
        updatedAt: DateTime.now().toUtc(),
      );
      // Simulate offline update on Device A cache
      final encUpdated = await cryptoService.encryptVaultPayload(
        plaintext: jsonEncode(updatedItem.toJson()),
        keyBytes: sessionKey,
      );
      await cacheA.saveEntry(LocalVaultCacheEntry.fromEncryptedPayload(
        id: entryA.id,
        encryptedJson: encUpdated,
        serverUpdatedAt: DateTime.now().toUtc().toIso8601String(),
        isPendingSync: true, // Pending offline edit
      ));

      // Step D: Device A triggers "Sync Now" -> pushes pending mutation to server
      await notifierA.syncWithServer();

      // Step E: Device B triggers "Sync Now" -> delta-fetches updated entry
      await notifierB.syncWithServer();

      expect(notifierB.state.items.length, equals(1));
      expect(notifierB.state.items.first.title, equals('Updated GitHub Enterprise'));
      expect(notifierB.state.items.first.password, equals('NewSuperSecretPass#99'));

      // Step F: Device A deletes entry offline
      await cacheA.markDeleted(entryA.id);
      expect((await cacheA.getPendingSyncEntries()).length, equals(1));

      // Device A syncs deletion
      await notifierA.syncWithServer();

      // Device B triggers "Sync Now" -> deletion reflected on Device B
      await notifierB.syncWithServer();
      expect(notifierB.state.items.isEmpty, isTrue);
    });
  });
}
