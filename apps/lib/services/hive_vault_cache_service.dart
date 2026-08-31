import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/local_vault_cache_entry.dart';

/// Concrete Hive Box implementation for Web / Cross-platform caching matching MVP.md §3.
/// Stores `local_vault_cache` maps in a Hive box with identical fields and semantics as SQLite:
///   id (String)
///   encrypted_data (String)
///   iv (String)
///   tag (String)
///   server_updated_at (String)
///   deleted (int: 0/1)
///   is_pending_sync (int: 0/1)
class HiveVaultCacheService {
  Box<Map>? _box;
  final String boxName;

  static const String defaultBoxName = 'local_vault_cache';

  HiveVaultCacheService({
    Box<Map>? box,
    this.boxName = defaultBoxName,
  }) {
    _box = box;
  }

  /// Whether the underlying Hive box is open and ready
  bool get isOpen => _box != null && _box!.isOpen;

  /// Explicitly sets or overrides underlying Hive box instance
  void setBox(Box<Map> box) {
    _box = box;
  }

  /// Initializes Hive storage and opens the local_vault_cache box
  Future<void> init({String? customPath, Box<Map>? customBox}) async {
    if (customBox != null) {
      _box = customBox;
      return;
    }

    if (_box == null || !_box!.isOpen) {
      if (!kIsWeb && customPath != null) {
        Hive.init(customPath);
      }
      _box = await Hive.openBox<Map>(boxName);
    }
  }

  Future<Box<Map>> _getBox() async {
    if (_box == null || !_box!.isOpen) {
      await init();
    }
    return _box!;
  }

  // ---------------------------------------------------------------------------
  // Write / Upsert Operations
  // ---------------------------------------------------------------------------

  /// Upserts a single LocalVaultCacheEntry into Hive
  Future<void> saveEntry(LocalVaultCacheEntry entry) async {
    final box = await _getBox();
    await box.put(entry.id, entry.toMap());
  }

  /// Batch upserts multiple LocalVaultCacheEntry records into Hive
  Future<void> saveEntries(List<LocalVaultCacheEntry> entries) async {
    if (entries.isEmpty) return;
    final box = await _getBox();
    final Map<String, Map<String, dynamic>> batchMap = {};

    for (final entry in entries) {
      batchMap[entry.id] = entry.toMap();
    }

    await box.putAll(batchMap);
  }

  // ---------------------------------------------------------------------------
  // Read Operations
  // ---------------------------------------------------------------------------

  /// Fetches a single entry by ID from Hive
  Future<LocalVaultCacheEntry?> getEntry(String id) async {
    final box = await _getBox();
    final raw = box.get(id);
    if (raw == null) return null;

    return LocalVaultCacheEntry.fromMap(Map<String, dynamic>.from(raw));
  }

  /// Fetches all cache entries sorted by server_updated_at DESC.
  /// If [includeDeleted] is false, excludes tombstoned items (deleted = 1).
  Future<List<LocalVaultCacheEntry>> getAllEntries({bool includeDeleted = false}) async {
    final box = await _getBox();
    final List<LocalVaultCacheEntry> list = [];

    for (final raw in box.values) {
      final entry = LocalVaultCacheEntry.fromMap(Map<String, dynamic>.from(raw));
      if (includeDeleted || !entry.isDeleted) {
        list.add(entry);
      }
    }

    list.sort((a, b) => b.serverUpdatedDateTime.compareTo(a.serverUpdatedDateTime));
    return list;
  }

  /// Soft deletes an entry (tombstone) by setting deleted = 1, is_pending_sync = 1,
  /// and advancing server_updated_at to current UTC ISO-8601 timestamp.
  Future<void> markDeleted(String id) async {
    final box = await _getBox();
    final raw = box.get(id);
    final nowIso = DateTime.now().toUtc().toIso8601String();

    if (raw != null) {
      final map = Map<String, dynamic>.from(raw);
      map['deleted'] = 1;
      map['is_pending_sync'] = 1;
      map['server_updated_at'] = nowIso;
      await box.put(id, map);
    } else {
      // Create a tombstone entry if not previously present
      final tombstone = LocalVaultCacheEntry(
        id: id,
        encryptedData: '',
        iv: '',
        tag: '',
        serverUpdatedAt: nowIso,
        deleted: 1,
        isPendingSync: 1,
      );
      await box.put(id, tombstone.toMap());
    }
  }

  // ---------------------------------------------------------------------------
  // Sync Engine Operations
  // ---------------------------------------------------------------------------

  /// Fetches all pending changes awaiting push to server (is_pending_sync = 1)
  /// sorted by server_updated_at ASC
  Future<List<LocalVaultCacheEntry>> getPendingSyncEntries() async {
    final box = await _getBox();
    final List<LocalVaultCacheEntry> pendingList = [];

    for (final raw in box.values) {
      final entry = LocalVaultCacheEntry.fromMap(Map<String, dynamic>.from(raw));
      if (entry.isPending) {
        pendingList.add(entry);
      }
    }

    pendingList.sort((a, b) => a.serverUpdatedDateTime.compareTo(b.serverUpdatedDateTime));
    return pendingList;
  }

  /// Marks an entry as clean after successful push to server (is_pending_sync = 0)
  Future<void> clearPendingSync(String id, {String? serverUpdatedAt}) async {
    final box = await _getBox();
    final raw = box.get(id);
    if (raw == null) return;

    final map = Map<String, dynamic>.from(raw);
    map['is_pending_sync'] = 0;
    if (serverUpdatedAt != null) {
      map['server_updated_at'] = serverUpdatedAt;
    }

    await box.put(id, map);
  }

  /// Hard deletes an entry permanently from Hive
  Future<void> deletePermanent(String id) async {
    final box = await _getBox();
    await box.delete(id);
  }

  /// Wipes all entries from Hive box on logout or full cache reset
  Future<void> clearAll() async {
    final box = await _getBox();
    await box.clear();
  }

  /// Closes the Hive box
  Future<void> close() async {
    if (_box != null && _box!.isOpen) {
      await _box!.close();
      _box = null;
    }
  }
}
