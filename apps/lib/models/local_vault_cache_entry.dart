import 'dart:convert';
import 'encrypted_vault_entry.dart';

/// Shared local cache entry model matching MVP.md §3:
/// local_vault_cache:
///   id                 TEXT PRIMARY KEY
///   encrypted_data     TEXT   -- ciphertext, as received from server
///   iv                 TEXT
///   tag                TEXT
///   server_updated_at  TEXT
///   deleted            INTEGER  -- 1 = tombstoned, hide from UI
///   is_pending_sync    INTEGER  -- 1 = local change awaiting push
class LocalVaultCacheEntry {
  static const String tableName = 'local_vault_cache';

  static const String createTableSql = '''
CREATE TABLE IF NOT EXISTS local_vault_cache (
  id TEXT PRIMARY KEY,
  encrypted_data TEXT NOT NULL,
  iv TEXT NOT NULL,
  tag TEXT NOT NULL,
  server_updated_at TEXT NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0,
  is_pending_sync INTEGER NOT NULL DEFAULT 0
);
''';

  final String id;
  final String encryptedData;
  final String iv;
  final String tag;
  final String serverUpdatedAt;
  final int deleted;
  final int isPendingSync;

  const LocalVaultCacheEntry({
    required this.id,
    required this.encryptedData,
    required this.iv,
    required this.tag,
    required this.serverUpdatedAt,
    this.deleted = 0,
    this.isPendingSync = 0,
  });

  /// 1 = tombstoned, hide from UI
  bool get isDeleted => deleted == 1;

  /// 1 = local change awaiting push
  bool get isPending => isPendingSync == 1;

  /// Parses server_updated_at string to DateTime (UTC)
  DateTime get serverUpdatedDateTime {
    return DateTime.tryParse(serverUpdatedAt)?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  /// Reconstructs the canonical zero-knowledge JSON envelope {"ciphertext": "...", "iv": "...", "tag": "..."}
  String get envelopeJson {
    return jsonEncode({
      'ciphertext': encryptedData,
      'iv': iv,
      'tag': tag,
    });
  }

  /// Deserializes from a SQLite Map / Hive Map
  factory LocalVaultCacheEntry.fromMap(Map<String, dynamic> map) {
    // Extract deleted as int (handling bool or null)
    final rawDeleted = map['deleted'];
    final int deletedVal = rawDeleted is bool
        ? (rawDeleted ? 1 : 0)
        : (rawDeleted is num ? rawDeleted.toInt() : 0);

    // Extract is_pending_sync as int (handling bool or null)
    final rawPending = map['is_pending_sync'] ?? map['isPendingSync'];
    final int pendingVal = rawPending is bool
        ? (rawPending ? 1 : 0)
        : (rawPending is num ? rawPending.toInt() : 0);

    return LocalVaultCacheEntry(
      id: map['id'] as String,
      encryptedData: (map['encrypted_data'] ?? map['encryptedData']) as String? ?? '',
      iv: (map['iv'] ?? '') as String,
      tag: (map['tag'] ?? '') as String,
      serverUpdatedAt: (map['server_updated_at'] ?? map['serverUpdatedAt']) as String? ??
          DateTime.now().toUtc().toIso8601String(),
      deleted: deletedVal,
      isPendingSync: pendingVal,
    );
  }

  /// Serializes to exact SQLite / Hive table map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'encrypted_data': encryptedData,
      'iv': iv,
      'tag': tag,
      'server_updated_at': serverUpdatedAt,
      'deleted': deleted,
      'is_pending_sync': isPendingSync,
    };
  }

  /// Creates a LocalVaultCacheEntry from an encrypted JSON envelope string
  factory LocalVaultCacheEntry.fromEncryptedPayload({
    required String id,
    required String encryptedJson,
    String? serverUpdatedAt,
    bool isDeleted = false,
    bool isPendingSync = false,
  }) {
    String ciphertext = '';
    String iv = '';
    String tag = '';

    try {
      final decoded = jsonDecode(encryptedJson) as Map<String, dynamic>;
      ciphertext = decoded['ciphertext'] as String? ?? '';
      iv = decoded['iv'] as String? ?? '';
      tag = decoded['tag'] as String? ?? '';
    } catch (_) {
      // Fallback if raw string
      ciphertext = encryptedJson;
    }

    return LocalVaultCacheEntry(
      id: id,
      encryptedData: ciphertext,
      iv: iv,
      tag: tag,
      serverUpdatedAt: serverUpdatedAt ?? DateTime.now().toUtc().toIso8601String(),
      deleted: isDeleted ? 1 : 0,
      isPendingSync: isPendingSync ? 1 : 0,
    );
  }

  /// Bridges from EncryptedVaultEntry (which stores JSON envelope in encryptedData)
  factory LocalVaultCacheEntry.fromEncryptedVaultEntry(
    EncryptedVaultEntry entry, {
    bool isPendingSync = false,
  }) {
    return LocalVaultCacheEntry.fromEncryptedPayload(
      id: entry.id,
      encryptedJson: entry.encryptedData,
      serverUpdatedAt: entry.updatedAt.toUtc().toIso8601String(),
      isDeleted: entry.isDeleted,
      isPendingSync: isPendingSync,
    );
  }

  /// Converts to EncryptedVaultEntry for compatibility with CryptoService & backend models
  EncryptedVaultEntry toEncryptedVaultEntry({String userId = ''}) {
    return EncryptedVaultEntry(
      id: id,
      userId: userId,
      encryptedData: envelopeJson,
      updatedAt: serverUpdatedDateTime,
      deletedAt: isDeleted ? serverUpdatedDateTime : null,
    );
  }

  LocalVaultCacheEntry copyWith({
    String? id,
    String? encryptedData,
    String? iv,
    String? tag,
    String? serverUpdatedAt,
    int? deleted,
    int? isPendingSync,
  }) {
    return LocalVaultCacheEntry(
      id: id ?? this.id,
      encryptedData: encryptedData ?? this.encryptedData,
      iv: iv ?? this.iv,
      tag: tag ?? this.tag,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      deleted: deleted ?? this.deleted,
      isPendingSync: isPendingSync ?? this.isPendingSync,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalVaultCacheEntry &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          encryptedData == other.encryptedData &&
          iv == other.iv &&
          tag == other.tag &&
          serverUpdatedAt == other.serverUpdatedAt &&
          deleted == other.deleted &&
          isPendingSync == other.isPendingSync;

  @override
  int get hashCode =>
      id.hashCode ^
      encryptedData.hashCode ^
      iv.hashCode ^
      tag.hashCode ^
      serverUpdatedAt.hashCode ^
      deleted.hashCode ^
      isPendingSync.hashCode;

  @override
  String toString() {
    return 'LocalVaultCacheEntry(id: $id, encryptedDataLen: ${encryptedData.length}, iv: $iv, tag: $tag, serverUpdatedAt: $serverUpdatedAt, deleted: $deleted, isPendingSync: $isPendingSync)';
  }
}
