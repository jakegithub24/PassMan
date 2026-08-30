import '../models/encrypted_vault_entry.dart';
import '../models/local_vault_cache_entry.dart';

/// Outcome of Last-Write-Wins (LWW) conflict evaluation (MVP.md §6 / Task 9.3)
enum MergeAction {
  /// Overwrite/insert local cache with incoming server entry
  applyServer,

  /// Apply tombstone deletion to local cache
  applyTombstone,

  /// Keep local entry intact because local edit is newer and pending push
  keepLocalPending,

  /// No change needed (identical timestamps)
  noop,
}

class LwwMergeResult {
  final MergeAction action;
  final LocalVaultCacheEntry? resultingEntry;
  final String? entryId;
  final String reason;

  const LwwMergeResult({
    required this.action,
    this.resultingEntry,
    this.entryId,
    required this.reason,
  });
}

/// Pure Last-Write-Wins (LWW) conflict resolution engine
class LwwMergeResolver {
  /// Evaluates conflict between an incoming server entry and existing local cache entry
  static LwwMergeResult resolve({
    LocalVaultCacheEntry? localEntry,
    required LocalVaultCacheEntry serverEntry,
  }) {
    // 1. If entry does not exist locally -> insert server entry
    if (localEntry == null) {
      if (serverEntry.isDeleted) {
        return LwwMergeResult(
          action: MergeAction.applyTombstone,
          resultingEntry: serverEntry.copyWith(isPendingSync: 0),
          entryId: serverEntry.id,
          reason: 'Remote tombstone for non-existent local item',
        );
      }
      return LwwMergeResult(
        action: MergeAction.applyServer,
        resultingEntry: serverEntry.copyWith(isPendingSync: 0),
        entryId: serverEntry.id,
        reason: 'New remote entry inserted into local cache',
      );
    }

    final localTime = localEntry.serverUpdatedDateTime;
    final serverTime = serverEntry.serverUpdatedDateTime;

    // 2. Incoming server entry is a tombstone
    if (serverEntry.isDeleted) {
      // If local edit is strictly newer and pending push -> local wins, keep local edit
      if (localEntry.isPending && localTime.isAfter(serverTime)) {
        return LwwMergeResult(
          action: MergeAction.keepLocalPending,
          resultingEntry: localEntry,
          entryId: localEntry.id,
          reason: 'Local modification is newer than server tombstone (queue push)',
        );
      }

      // Server tombstone is newer or local is clean -> tombstone wins
      return LwwMergeResult(
        action: MergeAction.applyTombstone,
        resultingEntry: serverEntry.copyWith(isPendingSync: 0),
        entryId: localEntry.id,
        reason: 'Server tombstone applied (deleted locally)',
      );
    }

    // 3. Local entry is clean (is_pending_sync == 0) -> always accept server update
    if (!localEntry.isPending) {
      return LwwMergeResult(
        action: MergeAction.applyServer,
        resultingEntry: serverEntry.copyWith(isPendingSync: 0),
        entryId: serverEntry.id,
        reason: 'Local entry is clean, overwritten by authoritative server entry',
      );
    }

    // 4. Local entry is pending sync (is_pending_sync == 1) -> evaluate timestamps
    if (serverTime.isAfter(localTime)) {
      // Server is newer -> server wins (overwrites local dirty edit)
      return LwwMergeResult(
        action: MergeAction.applyServer,
        resultingEntry: serverEntry.copyWith(isPendingSync: 0),
        entryId: serverEntry.id,
        reason: 'Server timestamp is newer than local edit (server overwrite)',
      );
    } else {
      // Local edit is newer or equal -> local wins, maintain is_pending_sync = 1
      return LwwMergeResult(
        action: MergeAction.keepLocalPending,
        resultingEntry: localEntry,
        entryId: localEntry.id,
        reason: 'Local modification is newer than server timestamp (queue push)',
      );
    }
  }

  /// Convenience resolver from EncryptedVaultEntry
  static LwwMergeResult resolveFromEncrypted({
    LocalVaultCacheEntry? localEntry,
    required EncryptedVaultEntry remoteEntry,
  }) {
    final serverCacheEntry = LocalVaultCacheEntry.fromEncryptedVaultEntry(
      remoteEntry,
      isPendingSync: false,
    );
    return resolve(
      localEntry: localEntry,
      serverEntry: serverCacheEntry,
    );
  }
}
