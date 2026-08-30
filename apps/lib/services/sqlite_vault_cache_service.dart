import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sql;
import '../models/local_vault_cache_entry.dart';

/// Concrete SQLite implementation for Android / Desktop caching matching MVP.md §3.
/// Manages table `local_vault_cache` with columns:
///   id (TEXT PRIMARY KEY)
///   encrypted_data (TEXT)
///   iv (TEXT)
///   tag (TEXT)
///   server_updated_at (TEXT)
///   deleted (INTEGER)
///   is_pending_sync (INTEGER)
class SqliteVaultCacheService {
  sql.Database? _db;

  SqliteVaultCacheService({sql.Database? db}) {
    _db = db;
  }

  /// Whether the SQLite database is initialized and open
  bool get isOpen => _db != null && _db!.isOpen;

  /// Explicitly sets or overrides underlying database instance
  void setDatabase(sql.Database db) {
    _db = db;
  }

  /// Initializes the SQLite database and executes table DDL
  Future<void> init({String? customPath}) async {
    if (kIsWeb) {
      return; // Handled by Hive on web
    }

    if (_db == null || !_db!.isOpen) {
      final String path = customPath ?? p.join(await sql.getDatabasesPath(), 'passman_vault.db');

      _db = await sql.openDatabase(
        path,
        version: 1,
        onCreate: (sql.Database db, int version) async {
          await db.execute(LocalVaultCacheEntry.createTableSql);
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_local_vault_cache_updated 
            ON ${LocalVaultCacheEntry.tableName} (server_updated_at DESC)
          ''');
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_local_vault_cache_pending 
            ON ${LocalVaultCacheEntry.tableName} (is_pending_sync)
          ''');
        },
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Write / Upsert Operations
  // ---------------------------------------------------------------------------

  /// Upserts a single LocalVaultCacheEntry
  Future<void> saveEntry(LocalVaultCacheEntry entry) async {
    final db = _getDb();
    await db.insert(
      LocalVaultCacheEntry.tableName,
      entry.toMap(),
      conflictAlgorithm: sql.ConflictAlgorithm.replace,
    );
  }

  /// Batch upserts multiple LocalVaultCacheEntry records in a single transaction
  Future<void> saveEntries(List<LocalVaultCacheEntry> entries) async {
    if (entries.isEmpty) return;
    final db = _getDb();
    final batch = db.batch();

    for (final entry in entries) {
      batch.insert(
        LocalVaultCacheEntry.tableName,
        entry.toMap(),
        conflictAlgorithm: sql.ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  // ---------------------------------------------------------------------------
  // Read Operations
  // ---------------------------------------------------------------------------

  /// Fetches a single entry by ID
  Future<LocalVaultCacheEntry?> getEntry(String id) async {
    final db = _getDb();
    final List<Map<String, dynamic>> rows = await db.query(
      LocalVaultCacheEntry.tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return LocalVaultCacheEntry.fromMap(rows.first);
  }

  /// Fetches all cache entries sorted by server_updated_at DESC.
  /// If [includeDeleted] is false, excludes tombstoned items (deleted = 1).
  Future<List<LocalVaultCacheEntry>> getAllEntries({bool includeDeleted = false}) async {
    final db = _getDb();
    final List<Map<String, dynamic>> rows = await db.query(
      LocalVaultCacheEntry.tableName,
      where: includeDeleted ? null : 'deleted = 0',
      orderBy: 'server_updated_at DESC',
    );

    return rows.map((r) => LocalVaultCacheEntry.fromMap(r)).toList();
  }

  /// Soft deletes an entry (tombstone) by setting deleted = 1, is_pending_sync = 1,
  /// and advancing server_updated_at to current UTC ISO-8601 timestamp.
  Future<void> markDeleted(String id) async {
    final db = _getDb();
    final nowIso = DateTime.now().toUtc().toIso8601String();

    await db.update(
      LocalVaultCacheEntry.tableName,
      {
        'deleted': 1,
        'is_pending_sync': 1,
        'server_updated_at': nowIso,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------------------------------------------------------------------------
  // Sync Engine Operations
  // ---------------------------------------------------------------------------

  /// Fetches all pending changes awaiting push to server (is_pending_sync = 1)
  Future<List<LocalVaultCacheEntry>> getPendingSyncEntries() async {
    final db = _getDb();
    final List<Map<String, dynamic>> rows = await db.query(
      LocalVaultCacheEntry.tableName,
      where: 'is_pending_sync = 1',
      orderBy: 'server_updated_at ASC',
    );

    return rows.map((r) => LocalVaultCacheEntry.fromMap(r)).toList();
  }

  /// Marks an entry as clean after successful push to server (is_pending_sync = 0)
  Future<void> clearPendingSync(String id, {String? serverUpdatedAt}) async {
    final db = _getDb();
    final updateData = <String, dynamic>{
      'is_pending_sync': 0,
    };
    if (serverUpdatedAt != null) {
      updateData['server_updated_at'] = serverUpdatedAt;
    }

    await db.update(
      LocalVaultCacheEntry.tableName,
      updateData,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Hard deletes an entry permanently (e.g. after tombstone cleanup)
  Future<void> deletePermanent(String id) async {
    final db = _getDb();
    await db.delete(
      LocalVaultCacheEntry.tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Wipes all entries in local_vault_cache on logout or full cache reset
  Future<void> clearAll() async {
    final db = _getDb();
    await db.delete(LocalVaultCacheEntry.tableName);
  }

  /// Closes database connection
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }

  sql.Database _getDb() {
    if (_db == null || !_db!.isOpen) {
      throw StateError('SqliteVaultCacheService is not initialized. Call init() before querying.');
    }
    return _db!;
  }
}
