import 'package:flutter/foundation.dart';
import '../models/local_vault_cache_entry.dart';
import '../services/hive_vault_cache_service.dart';
import '../services/sqlite_vault_cache_service.dart';

/// Platform-agnostic contract for local encrypted vault caching (MVP.md §3 / Task 8.4)
abstract class IVaultCacheRepository {
  /// Whether the underlying persistence store is initialized and open
  bool get isOpen;

  /// Initializes the repository store
  Future<void> init({String? customPath});

  /// Upserts a single cached vault entry
  Future<void> saveEntry(LocalVaultCacheEntry entry);

  /// Batch upserts multiple cached vault entries
  Future<void> saveEntries(List<LocalVaultCacheEntry> entries);

  /// Fetches a single entry by ID
  Future<LocalVaultCacheEntry?> getEntry(String id);

  /// Fetches all cached vault entries sorted by server_updated_at DESC
  Future<List<LocalVaultCacheEntry>> getAllEntries({bool includeDeleted = false});

  /// Soft-deletes a cached entry (sets deleted = 1, is_pending_sync = 1, advances server_updated_at)
  Future<void> markDeleted(String id);

  /// Fetches all pending changes awaiting push to server (is_pending_sync = 1)
  Future<List<LocalVaultCacheEntry>> getPendingSyncEntries();

  /// Clears pending sync flag on successful server push (is_pending_sync = 0)
  Future<void> clearPendingSync(String id, {String? serverUpdatedAt});

  /// Hard-deletes an entry permanently
  Future<void> deletePermanent(String id);

  /// Wipes all entries on logout / cache reset
  Future<void> clearAll();

  /// Closes underlying storage
  Future<void> close();
}

/// SQLite-backed implementation of IVaultCacheRepository (Android / Desktop)
class SqliteVaultCacheRepository implements IVaultCacheRepository {
  final SqliteVaultCacheService _service;

  SqliteVaultCacheRepository({SqliteVaultCacheService? service})
      : _service = service ?? SqliteVaultCacheService();

  @override
  bool get isOpen => _service.isOpen;

  @override
  Future<void> init({String? customPath}) => _service.init(customPath: customPath);

  @override
  Future<void> saveEntry(LocalVaultCacheEntry entry) => _service.saveEntry(entry);

  @override
  Future<void> saveEntries(List<LocalVaultCacheEntry> entries) => _service.saveEntries(entries);

  @override
  Future<LocalVaultCacheEntry?> getEntry(String id) => _service.getEntry(id);

  @override
  Future<List<LocalVaultCacheEntry>> getAllEntries({bool includeDeleted = false}) =>
      _service.getAllEntries(includeDeleted: includeDeleted);

  @override
  Future<void> markDeleted(String id) => _service.markDeleted(id);

  @override
  Future<List<LocalVaultCacheEntry>> getPendingSyncEntries() =>
      _service.getPendingSyncEntries();

  @override
  Future<void> clearPendingSync(String id, {String? serverUpdatedAt}) =>
      _service.clearPendingSync(id, serverUpdatedAt: serverUpdatedAt);

  @override
  Future<void> deletePermanent(String id) => _service.deletePermanent(id);

  @override
  Future<void> clearAll() => _service.clearAll();

  @override
  Future<void> close() => _service.close();
}

/// Hive-backed implementation of IVaultCacheRepository (Web / In-Memory / Cross-platform)
class HiveVaultCacheRepository implements IVaultCacheRepository {
  final HiveVaultCacheService _service;

  HiveVaultCacheRepository({HiveVaultCacheService? service})
      : _service = service ?? HiveVaultCacheService();

  @override
  bool get isOpen => _service.isOpen;

  @override
  Future<void> init({String? customPath}) => _service.init(customPath: customPath);

  @override
  Future<void> saveEntry(LocalVaultCacheEntry entry) => _service.saveEntry(entry);

  @override
  Future<void> saveEntries(List<LocalVaultCacheEntry> entries) => _service.saveEntries(entries);

  @override
  Future<LocalVaultCacheEntry?> getEntry(String id) => _service.getEntry(id);

  @override
  Future<List<LocalVaultCacheEntry>> getAllEntries({bool includeDeleted = false}) =>
      _service.getAllEntries(includeDeleted: includeDeleted);

  @override
  Future<void> markDeleted(String id) => _service.markDeleted(id);

  @override
  Future<List<LocalVaultCacheEntry>> getPendingSyncEntries() =>
      _service.getPendingSyncEntries();

  @override
  Future<void> clearPendingSync(String id, {String? serverUpdatedAt}) =>
      _service.clearPendingSync(id, serverUpdatedAt: serverUpdatedAt);

  @override
  Future<void> deletePermanent(String id) => _service.deletePermanent(id);

  @override
  Future<void> clearAll() => _service.clearAll();

  @override
  Future<void> close() => _service.close();
}

/// Unified factory that creates the platform-appropriate IVaultCacheRepository
class VaultCacheRepository {
  static IVaultCacheRepository create({
    SqliteVaultCacheService? sqliteService,
    HiveVaultCacheService? hiveService,
  }) {
    if (kIsWeb) {
      return HiveVaultCacheRepository(service: hiveService);
    } else {
      return SqliteVaultCacheRepository(service: sqliteService);
    }
  }
}
