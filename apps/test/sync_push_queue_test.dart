import 'package:apps/models/encrypted_vault_entry.dart';
import 'package:apps/models/local_vault_cache_entry.dart';
import 'package:apps/repositories/vault_cache_repository.dart';
import 'package:apps/services/sync_push_queue_service.dart';
import 'package:apps/services/vault_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class MockPushVaultApiService extends VaultApiService {
  final List<String> createdPayloads = [];
  final Map<String, String> updatedEntries = {};
  final List<String> deletedIds = [];
  bool failNext = false;
  bool return404OnPut = false;

  @override
  Future<EncryptedVaultEntry> createEntry(String encryptedData) async {
    if (failNext) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/vault/entries'),
        message: 'Network offline',
      );
    }
    createdPayloads.add(encryptedData);
    return EncryptedVaultEntry(
      id: 'server-created-id',
      userId: 'u1',
      encryptedData: encryptedData,
      updatedAt: DateTime.utc(2026, 8, 30, 20, 0),
    );
  }

  @override
  Future<EncryptedVaultEntry> updateEntry(String entryId, String encryptedData) async {
    if (failNext) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/vault/entries/$entryId'),
        message: 'Network offline',
      );
    }
    if (return404OnPut) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/vault/entries/$entryId'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/vault/entries/$entryId'),
          statusCode: 404,
        ),
      );
    }
    updatedEntries[entryId] = encryptedData;
    return EncryptedVaultEntry(
      id: entryId,
      userId: 'u1',
      encryptedData: encryptedData,
      updatedAt: DateTime.utc(2026, 8, 30, 20, 30),
    );
  }

  @override
  Future<bool> deleteEntry(String entryId) async {
    if (failNext) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/vault/entries/$entryId'),
        message: 'Network offline',
      );
    }
    deletedIds.add(entryId);
    return true;
  }
}

class FakeMemoryPushCacheRepo implements IVaultCacheRepository {
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
    return store.values.where((e) => includeDeleted || !e.isDeleted).toList();
  }

  @override
  Future<void> markDeleted(String id) async {
    final existing = store[id];
    if (existing != null) {
      store[id] = existing.copyWith(
        deleted: 1,
        isPendingSync: 1,
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

  late FakeMemoryPushCacheRepo cacheRepo;
  late MockPushVaultApiService apiService;
  late SyncPushQueueService pushQueue;

  setUp(() {
    cacheRepo = FakeMemoryPushCacheRepo();
    apiService = MockPushVaultApiService();
    pushQueue = SyncPushQueueService(
      cacheRepository: cacheRepo,
      vaultApiService: apiService,
    );
  });

  group('Sync Push Queue Service (Task 9.4 / MVP.md §6)', () {
    test('Pushes active pending entry via PUT and marks clean on success', () async {
      await cacheRepo.saveEntry(const LocalVaultCacheEntry(
        id: 'edit-1',
        encryptedData: 'c-new-edit',
        iv: 'iv1',
        tag: 'tag1',
        serverUpdatedAt: '2026-08-30T10:00:00.000Z',
        deleted: 0,
        isPendingSync: 1,
      ));

      final result = await pushQueue.processPendingQueue();

      expect(result.totalPending, equals(1));
      expect(result.successCount, equals(1));
      expect(result.failureCount, equals(0));
      expect(apiService.updatedEntries.containsKey('edit-1'), isTrue);

      final updatedEntry = await cacheRepo.getEntry('edit-1');
      expect(updatedEntry!.isPendingSync, equals(0));
      expect(updatedEntry.serverUpdatedAt, equals('2026-08-30T20:30:00.000Z'));
    });

    test('Pushes offline-created entry (PUT returns 404) via POST and marks clean', () async {
      apiService.return404OnPut = true;

      await cacheRepo.saveEntry(const LocalVaultCacheEntry(
        id: 'new-offline-entry',
        encryptedData: 'c-offline-created',
        iv: 'iv1',
        tag: 'tag1',
        serverUpdatedAt: '2026-08-30T12:00:00.000Z',
        deleted: 0,
        isPendingSync: 1,
      ));

      final result = await pushQueue.processPendingQueue();

      expect(result.totalPending, equals(1));
      expect(result.successCount, equals(1));
      expect(apiService.createdPayloads.length, equals(1));

      final updatedEntry = await cacheRepo.getEntry('new-offline-entry');
      expect(updatedEntry!.isPendingSync, equals(0));
    });

    test('Pushes deleted entry (tombstone) via DELETE and marks clean', () async {
      await cacheRepo.saveEntry(const LocalVaultCacheEntry(
        id: 'tombstone-1',
        encryptedData: '',
        iv: '',
        tag: '',
        serverUpdatedAt: '2026-08-30T14:00:00.000Z',
        deleted: 1,
        isPendingSync: 1,
      ));

      final result = await pushQueue.processPendingQueue();

      expect(result.totalPending, equals(1));
      expect(result.successCount, equals(1));
      expect(apiService.deletedIds, contains('tombstone-1'));

      final tombstoneEntry = await cacheRepo.getEntry('tombstone-1');
      expect(tombstoneEntry!.isPendingSync, equals(0));
    });

    test('Network error leaves entry pending for future retry', () async {
      apiService.failNext = true;

      await cacheRepo.saveEntry(const LocalVaultCacheEntry(
        id: 'offline-pending-item',
        encryptedData: 'data',
        iv: 'iv',
        tag: 'tag',
        serverUpdatedAt: '2026-08-30T10:00:00.000Z',
        deleted: 0,
        isPendingSync: 1,
      ));

      final result = await pushQueue.processPendingQueue();

      expect(result.totalPending, equals(1));
      expect(result.successCount, equals(0));
      expect(result.failureCount, equals(1));

      // Must remain pending
      final pendingAfterFail = await cacheRepo.getEntry('offline-pending-item');
      expect(pendingAfterFail!.isPendingSync, equals(1));
    });
  });
}
