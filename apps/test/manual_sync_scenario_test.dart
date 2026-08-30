import 'dart:convert';
import 'package:apps/models/encrypted_vault_entry.dart';
import 'package:apps/models/local_vault_cache_entry.dart';
import 'package:apps/models/vault_item.dart';
import 'package:apps/providers/providers.dart';
import 'package:apps/repositories/vault_cache_repository.dart';
import 'package:apps/services/crypto_service.dart';
import 'package:apps/services/vault_api_service.dart';
import 'package:flutter_test/flutter_test.dart';

class CentralMockServer {
  final Map<String, EncryptedVaultEntry> db = {};
  DateTime currentTime = DateTime.utc(2026, 8, 30, 12, 0);

  VaultApiService createClient({bool startsOffline = false}) {
    return _DeviceClientApiService(this, isOnline: !startsOffline);
  }
}

class _DeviceClientApiService extends VaultApiService {
  final CentralMockServer _server;
  bool isOnline;

  _DeviceClientApiService(this._server, {required this.isOnline});

  @override
  Future<EncryptedVaultEntry> createEntry(String encryptedData) async {
    if (!isOnline) {
      throw Exception('Network unreachable (Device Offline)');
    }
    _server.currentTime = _server.currentTime.add(const Duration(seconds: 5));
    String id = 'entry-${_server.db.length + 1}';
    try {
      final map = jsonDecode(encryptedData) as Map<String, dynamic>;
      if (map.containsKey('id') && map['id'] != null) {
        id = map['id'] as String;
      }
    } catch (_) {}

    final entry = EncryptedVaultEntry(
      id: id,
      userId: 'sync-user-123',
      encryptedData: encryptedData,
      updatedAt: _server.currentTime,
    );
    _server.db[id] = entry;
    return entry;
  }

  @override
  Future<EncryptedVaultEntry> updateEntry(String entryId, String encryptedData) async {
    if (!isOnline) {
      throw Exception('Network unreachable (Device Offline)');
    }
    _server.currentTime = _server.currentTime.add(const Duration(seconds: 5));
    final existing = _server.db[entryId];
    final entry = EncryptedVaultEntry(
      id: entryId,
      userId: 'sync-user-123',
      encryptedData: encryptedData,
      updatedAt: _server.currentTime,
      deletedAt: existing?.deletedAt,
    );
    _server.db[entryId] = entry;
    return entry;
  }

  @override
  Future<bool> deleteEntry(String entryId) async {
    if (!isOnline) {
      throw Exception('Network unreachable (Device Offline)');
    }
    _server.currentTime = _server.currentTime.add(const Duration(seconds: 5));
    final existing = _server.db[entryId];
    if (existing != null) {
      _server.db[entryId] = EncryptedVaultEntry(
        id: entryId,
        userId: existing.userId,
        encryptedData: existing.encryptedData,
        updatedAt: _server.currentTime,
        deletedAt: _server.currentTime,
      );
    }
    return true;
  }

  @override
  Future<VaultSyncResult> syncEntries({DateTime? since, int limit = 500}) async {
    if (!isOnline) {
      throw Exception('Network unreachable (Device Offline)');
    }
    final results = _server.db.values.where((e) {
      if (since == null) return true;
      return e.updatedAt.isAfter(since);
    }).toList();

    return VaultSyncResult(
      entries: results,
      serverTime: _server.currentTime,
    );
  }
}

class InMemorySyncDeviceRepo implements IVaultCacheRepository {
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
      masterPassword: 'MasterPassword2026!@#',
      saltBase64: cryptoService.generateSalt(),
    );
  });

  group('Task 11.3: Offline Edit → Reconnect → Sync → Verify on Second Device', () {
    test('Simulates end-to-end multi-device sync lifecycle: offline edits on Device A propagate to Device B', () async {
      final centralServer = CentralMockServer();

      // Setup Device A
      final cacheA = InMemorySyncDeviceRepo();
      final clientA = centralServer.createClient() as _DeviceClientApiService;
      final notifierA = VaultNotifier(
        cacheRepository: cacheA,
        cryptoService: cryptoService,
        vaultApiService: clientA,
        getSessionKey: () => sessionKey,
        getUserId: () => 'sync-user-123',
      );

      // Setup Device B
      final cacheB = InMemorySyncDeviceRepo();
      final clientB = centralServer.createClient() as _DeviceClientApiService;
      final notifierB = VaultNotifier(
        cacheRepository: cacheB,
        cryptoService: cryptoService,
        vaultApiService: clientB,
        getSessionKey: () => sessionKey,
        getUserId: () => 'sync-user-123',
      );

      // 1. Initial State: Device A creates entry while online
      final initialItem = await notifierA.addEntry(
        title: 'Work AWS Console',
        username: 'admin@work.io',
        password: 'InitialPassword123!',
        notes: 'MFA on Hardware Token 1',
        category: 'cloud',
      );
      expect(initialItem, isNotNull);
      expect(centralServer.db.length, equals(1));

      // 2. Device B syncs initial vault
      await notifierB.loadVault(syncRemote: true);
      expect(notifierB.state.items.length, equals(1));
      expect(notifierB.state.items.first.title, equals('Work AWS Console'));
      expect(notifierB.state.items.first.password, equals('InitialPassword123!'));

      // 3. Device A GOES OFFLINE
      clientA.isOnline = false;

      // Device A edits the existing entry while offline
      final localEntryA = (await cacheA.getAllEntries()).first;
      final editedItem = VaultItem(
        id: localEntryA.id,
        title: 'Work AWS Root Account',
        username: 'root@work.io',
        password: 'RotatedSuperPassword2026#',
        notes: 'MFA on Hardware Key YubiKey 5',
        category: 'cloud',
        updatedAt: DateTime.now().toUtc(),
      );

      final encEdited = await cryptoService.encryptVaultPayload(
        plaintext: jsonEncode(editedItem.toJson()),
        keyBytes: sessionKey,
      );

      await cacheA.saveEntry(LocalVaultCacheEntry.fromEncryptedPayload(
        id: localEntryA.id,
        encryptedJson: encEdited,
        serverUpdatedAt: DateTime.now().toUtc().toIso8601String(),
        isPendingSync: true, // Marked as pending sync
      ));

      // Device A adds a new entry while offline
      final offlineNewItem = VaultItem(
        id: 'offline-item-002',
        title: 'Personal ProtonMail',
        username: 'me@proton.me',
        password: 'ProtonPassword9988!',
        category: 'email',
        updatedAt: DateTime.now().toUtc(),
      );
      final encOfflineNew = await cryptoService.encryptVaultPayload(
        plaintext: jsonEncode(offlineNewItem.toJson()),
        keyBytes: sessionKey,
      );
      await cacheA.saveEntry(LocalVaultCacheEntry.fromEncryptedPayload(
        id: offlineNewItem.id,
        encryptedJson: encOfflineNew,
        serverUpdatedAt: DateTime.now().toUtc().toIso8601String(),
        isPendingSync: true, // Marked as pending sync
      ));

      // Verify Device A has 2 items locally and 2 pending sync entries
      final pendingEntries = await cacheA.getPendingSyncEntries();
      expect(pendingEntries.length, equals(2));

      // 4. Device A RECONNECTS TO NETWORK
      clientA.isOnline = true;

      // Device A triggers Sync (Push queue dispatches 2 pending mutations)
      await notifierA.syncWithServer();

      // Pending flags are cleared on Device A
      expect((await cacheA.getPendingSyncEntries()).isEmpty, isTrue);
      expect(centralServer.db.length, equals(2));

      // 5. Device B SYNC (Delta sync fetches updated and new entries)
      await notifierB.syncWithServer();

      // 6. VERIFY ON SECOND DEVICE (Device B)
      expect(notifierB.state.items.length, equals(2));

      final item1OnB = notifierB.state.items.firstWhere((i) => i.id == localEntryA.id);
      expect(item1OnB.title, equals('Work AWS Root Account'));
      expect(item1OnB.username, equals('root@work.io'));
      expect(item1OnB.password, equals('RotatedSuperPassword2026#'));
      expect(item1OnB.notes, equals('MFA on Hardware Key YubiKey 5'));

      final item2OnB = notifierB.state.items.firstWhere((i) => i.id == 'offline-item-002');
      expect(item2OnB.title, equals('Personal ProtonMail'));
      expect(item2OnB.username, equals('me@proton.me'));
      expect(item2OnB.password, equals('ProtonPassword9988!'));
    });
  });
}
