import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sql;

import '../models/encrypted_vault_entry.dart';

/// Offline-first local database service for encrypted vault entries.
/// Employs SQLite on Android/Desktop and Hive Box on Web.
class LocalVaultStorageService {
  sql.Database? _sqliteDb;
  Box<Map>? _hiveBox;

  static const String tableName = 'local_vault_entries';
  static const String webBoxName = 'passman_vault_entries';

  LocalVaultStorageService({sql.Database? sqliteDb, Box<Map>? hiveBox}) {
    _sqliteDb = sqliteDb;
    _hiveBox = hiveBox;
  }

  /// Initializes storage backend depending on runtime platform.
  Future<void> init() async {
    if (kIsWeb) {
      if (_hiveBox == null || !_hiveBox!.isOpen) {
        _hiveBox = await Hive.openBox<Map>(webBoxName);
      }
    } else {
      if (_sqliteDb == null || !_sqliteDb!.isOpen) {
        final String dbPath = await sql.getDatabasesPath();
        final String path = p.join(dbPath, 'passman_vault.db');

        _sqliteDb = await sql.openDatabase(
          path,
          version: 1,
          onCreate: (sql.Database db, int version) async {
            await db.execute('''
              CREATE TABLE $tableName (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                encrypted_data TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                deleted_at TEXT,
                is_dirty INTEGER NOT NULL DEFAULT 0
              )
            ''');
            await db.execute('''
              CREATE INDEX idx_local_vault_updated_at ON $tableName (updated_at DESC)
            ''');
          },
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Write / Upsert Operations
  // ---------------------------------------------------------------------------

  Future<void> saveEntry(EncryptedVaultEntry entry, {bool isDirty = false}) async {
    if (kIsWeb || _hiveBox != null) {
      final Map<String, dynamic> data = entry.toJson();
      data['is_dirty'] = isDirty ? 1 : 0;
      await _hiveBox!.put(entry.id, data);
    } else {
      final db = _sqliteDb!;
      await db.insert(
        tableName,
        {
          ...entry.toSqlite(),
          'is_dirty': isDirty ? 1 : 0,
        },
        conflictAlgorithm: sql.ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> saveEntries(List<EncryptedVaultEntry> entries, {bool isDirty = false}) async {
    if (entries.isEmpty) return;

    if (kIsWeb || _hiveBox != null) {
      final Map<String, Map<String, dynamic>> map = {};
      for (final e in entries) {
        final d = e.toJson();
        d['is_dirty'] = isDirty ? 1 : 0;
        map[e.id] = d;
      }
      await _hiveBox!.putAll(map);
    } else {
      final db = _sqliteDb!;
      final batch = db.batch();
      for (final e in entries) {
        batch.insert(
          tableName,
          {
            ...e.toSqlite(),
            'is_dirty': isDirty ? 1 : 0,
          },
          conflictAlgorithm: sql.ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Read Operations
  // ---------------------------------------------------------------------------

  Future<EncryptedVaultEntry?> getEntry(String id) async {
    if (kIsWeb || _hiveBox != null) {
      final raw = _hiveBox!.get(id);
      if (raw == null) return null;
      return EncryptedVaultEntry.fromJson(Map<String, dynamic>.from(raw));
    } else {
      final db = _sqliteDb!;
      final List<Map<String, dynamic>> results = await db.query(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (results.isEmpty) return null;
      return EncryptedVaultEntry.fromSqlite(results.first);
    }
  }

  Future<List<EncryptedVaultEntry>> getAllEntries({bool includeDeleted = false}) async {
    if (kIsWeb || _hiveBox != null) {
      final List<EncryptedVaultEntry> list = [];
      for (final raw in _hiveBox!.values) {
        final entry = EncryptedVaultEntry.fromJson(Map<String, dynamic>.from(raw));
        if (includeDeleted || !entry.isDeleted) {
          list.add(entry);
        }
      }
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    } else {
      final db = _sqliteDb!;
      final List<Map<String, dynamic>> results = await db.query(
        tableName,
        where: includeDeleted ? null : 'deleted_at IS NULL',
        orderBy: 'updated_at DESC',
      );
      return results.map((m) => EncryptedVaultEntry.fromSqlite(m)).toList();
    }
  }

  // ---------------------------------------------------------------------------
  // Soft Delete Operation
  // ---------------------------------------------------------------------------

  Future<void> markDeleted(String id) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();

    if (kIsWeb || _hiveBox != null) {
      final raw = _hiveBox!.get(id);
      if (raw != null) {
        final map = Map<String, dynamic>.from(raw);
        map['deleted_at'] = nowIso;
        map['updated_at'] = nowIso;
        map['is_dirty'] = 1;
        await _hiveBox!.put(id, map);
      }
    } else {
      final db = _sqliteDb!;
      await db.update(
        tableName,
        {
          'deleted_at': nowIso,
          'updated_at': nowIso,
          'is_dirty': 1,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Offline Sync Tracking (Dirty Flags)
  // ---------------------------------------------------------------------------

  Future<List<EncryptedVaultEntry>> getDirtyEntries() async {
    if (kIsWeb || _hiveBox != null) {
      final List<EncryptedVaultEntry> list = [];
      for (final raw in _hiveBox!.values) {
        final map = Map<String, dynamic>.from(raw);
        if (map['is_dirty'] == 1) {
          list.add(EncryptedVaultEntry.fromJson(map));
        }
      }
      return list;
    } else {
      final db = _sqliteDb!;
      final List<Map<String, dynamic>> results = await db.query(
        tableName,
        where: 'is_dirty = 1',
        orderBy: 'updated_at ASC',
      );
      return results.map((m) => EncryptedVaultEntry.fromSqlite(m)).toList();
    }
  }

  Future<void> clearDirty(List<String> entryIds) async {
    if (entryIds.isEmpty) return;

    if (kIsWeb || _hiveBox != null) {
      for (final id in entryIds) {
        final raw = _hiveBox!.get(id);
        if (raw != null) {
          final map = Map<String, dynamic>.from(raw);
          map['is_dirty'] = 0;
          await _hiveBox!.put(id, map);
        }
      }
    } else {
      final db = _sqliteDb!;
      final batch = db.batch();
      for (final id in entryIds) {
        batch.update(
          tableName,
          {'is_dirty': 0},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      await batch.commit(noResult: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Wipeout (Logout)
  // ---------------------------------------------------------------------------

  Future<void> clearAll() async {
    if (kIsWeb || _hiveBox != null) {
      await _hiveBox?.clear();
    } else if (_sqliteDb != null) {
      await _sqliteDb!.delete(tableName);
    }
  }
}
