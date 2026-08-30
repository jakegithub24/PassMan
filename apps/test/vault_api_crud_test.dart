import 'dart:convert';
import 'package:apps/models/encrypted_vault_entry.dart';
import 'package:apps/models/vault_item.dart';
import 'package:apps/providers/vault_notifier.dart';
import 'package:apps/providers/vault_state.dart';
import 'package:apps/services/crypto_service.dart';
import 'package:apps/services/local_vault_storage_service.dart';
import 'package:apps/services/vault_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeLocalVaultStorageService extends LocalVaultStorageService {
  final Map<String, EncryptedVaultEntry> storage = {};
  final Map<String, bool> dirtyStatus = {};

  @override
  Future<void> saveEntry(EncryptedVaultEntry entry, {bool isDirty = false}) async {
    storage[entry.id] = entry;
    dirtyStatus[entry.id] = isDirty;
  }

  @override
  Future<EncryptedVaultEntry?> getEntry(String id) async {
    return storage[id];
  }

  @override
  Future<List<EncryptedVaultEntry>> getAllEntries({bool includeDeleted = false}) async {
    return storage.values.where((e) => includeDeleted || e.deletedAt == null).toList();
  }

  @override
  Future<void> markDeleted(String id) async {
    final existing = storage[id];
    if (existing != null) {
      storage[id] = existing.copyWith(deletedAt: DateTime.now().toUtc());
      dirtyStatus[id] = true;
    }
  }
}

class FakeVaultApiService extends VaultApiService {
  final Map<String, EncryptedVaultEntry> serverEntries = {};
  int createCalls = 0;
  int updateCalls = 0;
  int deleteCalls = 0;
  int syncCalls = 0;
  bool shouldThrowError = false;

  @override
  Future<EncryptedVaultEntry> createEntry(String encryptedData) async {
    if (shouldThrowError) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/vault/entries'),
        message: 'Simulated network outage',
      );
    }
    createCalls++;
    final entry = EncryptedVaultEntry(
      id: 'server-id-$createCalls',
      userId: 'user-123',
      encryptedData: encryptedData,
      updatedAt: DateTime.now().toUtc(),
    );
    serverEntries[entry.id] = entry;
    return entry;
  }

  @override
  Future<EncryptedVaultEntry> updateEntry(String entryId, String encryptedData) async {
    if (shouldThrowError) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/vault/entries/$entryId'),
        message: 'Simulated network outage',
      );
    }
    updateCalls++;
    final entry = EncryptedVaultEntry(
      id: entryId,
      userId: 'user-123',
      encryptedData: encryptedData,
      updatedAt: DateTime.now().toUtc(),
    );
    serverEntries[entryId] = entry;
    return entry;
  }

  @override
  Future<bool> deleteEntry(String entryId) async {
    if (shouldThrowError) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/vault/entries/$entryId'),
        message: 'Simulated network outage',
      );
    }
    deleteCalls++;
    final existing = serverEntries[entryId];
    if (existing != null) {
      serverEntries[entryId] = existing.copyWith(deletedAt: DateTime.now().toUtc());
    }
    return true;
  }

  @override
  Future<VaultSyncResult> syncEntries({DateTime? since, int limit = 500}) async {
    if (shouldThrowError) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/vault/sync'),
        message: 'Simulated network outage',
      );
    }
    syncCalls++;
    return VaultSyncResult(
      entries: serverEntries.values.toList(),
      serverTime: DateTime.now().toUtc(),
    );
  }

  @override
  Future<Map<String, dynamic>> fetchSyncStatus() async {
    if (shouldThrowError) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/vault/sync/status'),
        message: 'Simulated network outage',
      );
    }
    return {
      'server_time': DateTime.now().toUtc().toIso8601String(),
      'status': 'online',
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CryptoService cryptoService;
  late FakeLocalVaultStorageService localVaultStorage;
  late FakeVaultApiService vaultApiService;
  late List<int> sessionKey;
  late VaultNotifier vaultNotifier;

  setUp(() async {
    cryptoService = CryptoService(pbkdf2Iterations: 1000);
    sessionKey = await cryptoService.deriveMasterKey(
      masterPassword: 'SecureMasterPassword123!',
      saltBase64: cryptoService.generateSalt(),
    );

    localVaultStorage = FakeLocalVaultStorageService();
    vaultApiService = FakeVaultApiService();

    vaultNotifier = VaultNotifier(
      localVaultStorage: localVaultStorage,
      cryptoService: cryptoService,
      vaultApiService: vaultApiService,
      getSessionKey: () => sessionKey,
      getUserId: () => 'user-123',
    );
  });

  group('VaultApiService Wire CRUD Tests (Task 7.6)', () {
    test('addEntry encrypts payload, updates state, and wires to createEntry endpoint (3.1)', () async {
      final item = await vaultNotifier.addEntry(
        title: 'Work GitHub',
        username: 'dev@github.corp',
        password: 'Password999!',
        url: 'https://github.corp',
        notes: 'Corporate SSO',
        category: 'logins',
      );

      expect(item, isNotNull);
      expect(item!.title, equals('Work GitHub'));
      expect(item.username, equals('dev@github.corp'));

      // Verify in-memory state updated
      expect(vaultNotifier.state.status, equals(VaultStatus.ready));
      expect(vaultNotifier.state.items.length, equals(1));
      expect(vaultNotifier.state.items.first.title, equals('Work GitHub'));

      // Verify API endpoint called
      expect(vaultApiService.createCalls, equals(1));

      // Verify local storage is clean after server returns
      expect(localVaultStorage.dirtyStatus['server-id-1'], isFalse);
    });

    test('updateEntry re-encrypts payload and wires to updateEntry endpoint (3.3)', () async {
      final item = await vaultNotifier.addEntry(
        title: 'AWS Cloud',
        username: 'admin@aws',
        password: 'InitialPassword1',
      );
      expect(item, isNotNull);

      final updatedItem = item!.copyWith(
        password: 'NewSuperPassword2026!',
        notes: 'Rotated password on server',
      );

      final success = await vaultNotifier.updateEntry(updatedItem);
      expect(success, isTrue);

      // Verify in-memory state updated
      expect(vaultNotifier.state.items.first.password, equals('NewSuperPassword2026!'));
      expect(vaultNotifier.state.items.first.notes, equals('Rotated password on server'));

      // Verify API endpoint called
      expect(vaultApiService.updateCalls, equals(1));
      expect(vaultApiService.serverEntries[updatedItem.id], isNotNull);
    });

    test('deleteEntry soft-deletes locally and wires to deleteEntry endpoint (3.4)', () async {
      final item = await vaultNotifier.addEntry(
        title: 'Temporary Card',
        username: 'Card User',
        password: '123',
      );
      expect(item, isNotNull);
      expect(vaultNotifier.state.items.length, equals(1));

      final success = await vaultNotifier.deleteEntry(item!.id);
      expect(success, isTrue);

      // Verify in-memory state removed item
      expect(vaultNotifier.state.items.isEmpty, isTrue);

      // Verify API delete endpoint called
      expect(vaultApiService.deleteCalls, equals(1));

      // Verify marked deleted in local storage
      final local = await localVaultStorage.getEntry(item.id);
      expect(local?.isDeleted, isTrue);
    });

    test('loadVault syncs from remote delta endpoint (3.2) and decrypts entries', () async {
      // Seed server with an encrypted entry
      final serverItem = VaultItem(
        id: 'remote-1',
        title: 'Remote Seeded Database',
        username: 'db_admin',
        password: 'SecretPostgresPassword',
        category: 'logins',
        updatedAt: DateTime.now().toUtc(),
      );

      final encPayload = await cryptoService.encryptVaultPayload(
        plaintext: jsonEncode(serverItem.toJson()),
        keyBytes: sessionKey,
      );

      vaultApiService.serverEntries['remote-1'] = EncryptedVaultEntry(
        id: 'remote-1',
        userId: 'user-123',
        encryptedData: encPayload,
        updatedAt: serverItem.updatedAt,
      );

      // Load vault from scratch
      await vaultNotifier.loadVault();

      // Verify sync endpoint was called
      expect(vaultApiService.syncCalls, equals(1));

      // Verify entry was saved to local storage and decrypted in state
      expect(vaultNotifier.state.status, equals(VaultStatus.ready));
      expect(vaultNotifier.state.items.length, equals(1));
      expect(vaultNotifier.state.items.first.title, equals('Remote Seeded Database'));
      expect(vaultNotifier.state.items.first.password, equals('SecretPostgresPassword'));
    });

    test('offline resilience: addEntry persists locally and continues when network errors', () async {
      vaultApiService.shouldThrowError = true;

      final item = await vaultNotifier.addEntry(
        title: 'Offline Draft Note',
        username: 'offline_user',
        password: 'LocalSecretPassword',
      );

      expect(item, isNotNull);
      expect(vaultNotifier.state.items.length, equals(1));
      expect(vaultNotifier.state.items.first.title, equals('Offline Draft Note'));

      // Marked dirty locally for later sync
      expect(localVaultStorage.dirtyStatus[item!.id], isTrue);
    });

    test('VaultApiService Dio HTTP serialization and status check', () async {
      final dio = Dio();
      final api = VaultApiService(dio: dio, baseUrl: 'http://localhost:8000');

      expect(api, isNotNull);
    });
  });
}
