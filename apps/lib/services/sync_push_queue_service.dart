import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/encrypted_vault_entry.dart';
import '../models/local_vault_cache_entry.dart';
import '../repositories/vault_cache_repository.dart';
import '../services/local_vault_storage_service.dart';
import '../services/vault_api_service.dart';

/// Push Result Summary
class PushQueueResult {
  final int totalPending;
  final int successCount;
  final int failureCount;
  final List<String> errors;

  const PushQueueResult({
    required this.totalPending,
    required this.successCount,
    required this.failureCount,
    required this.errors,
  });

  bool get hasFailures => failureCount > 0;
}

/// Push Queue Processor implementing MVP.md §6 / Task 9.4:
/// Dispatches local pending rows (is_pending_sync=1) to backend CRUD endpoints:
///   - deleted=1 -> DELETE /api/vault/entries/{id}
///   - deleted=0 -> PUT /api/vault/entries/{id} (fallback POST if not found on server)
/// On success: clears is_pending_sync=0 and persists authoritative server timestamp.
class SyncPushQueueService {
  final IVaultCacheRepository? cacheRepository;
  final LocalVaultStorageService? localVaultStorage;
  final VaultApiService vaultApiService;

  SyncPushQueueService({
    this.cacheRepository,
    this.localVaultStorage,
    required this.vaultApiService,
  });

  /// Processes all pending offline changes in sequence
  Future<PushQueueResult> processPendingQueue() async {
    final cacheRepo = cacheRepository;
    final localStorage = localVaultStorage;

    List<LocalVaultCacheEntry> pendingEntries = [];

    if (cacheRepo != null && cacheRepo.isOpen) {
      pendingEntries = await cacheRepo.getPendingSyncEntries();
    } else if (localStorage != null) {
      final dirtyEntries = await localStorage.getDirtyEntries();
      pendingEntries = dirtyEntries.map((e) {
        return LocalVaultCacheEntry.fromEncryptedVaultEntry(e, isPendingSync: true);
      }).toList();
    }

    if (pendingEntries.isEmpty) {
      return const PushQueueResult(
        totalPending: 0,
        successCount: 0,
        failureCount: 0,
        errors: [],
      );
    }

    int successCount = 0;
    int failureCount = 0;
    final List<String> errors = [];

    for (final entry in pendingEntries) {
      try {
        if (entry.isDeleted) {
          // Push soft-deletion to server (DELETE /api/vault/entries/{id})
          try {
            await vaultApiService.deleteEntry(entry.id);
          } on DioException catch (dioError) {
            // If already deleted on server (404), consider successful
            if (dioError.response?.statusCode != 404) {
              rethrow;
            }
          }

          // Clear pending flag
          if (cacheRepo != null && cacheRepo.isOpen) {
            await cacheRepo.clearPendingSync(entry.id);
          }
          if (localStorage != null) {
            await localStorage.clearDirty([entry.id]);
          }
          successCount++;
        } else {
          // Push update (PUT) or creation (POST)
          EncryptedVaultEntry? serverEntry;

          try {
            // Attempt update first
            serverEntry = await vaultApiService.updateEntry(
              entry.id,
              entry.envelopeJson,
            );
          } on DioException catch (dioError) {
            // If entry not found on server (404), it was created offline -> POST create
            if (dioError.response?.statusCode == 404) {
              serverEntry = await vaultApiService.createEntry(entry.envelopeJson);
            } else {
              rethrow;
            }
          }

          final serverUpdatedIso = serverEntry.updatedAt.toUtc().toIso8601String();

          // Mark clean in local cache with server authoritative updated_at
          if (cacheRepo != null && cacheRepo.isOpen) {
            await cacheRepo.clearPendingSync(
              entry.id,
              serverUpdatedAt: serverUpdatedIso,
            );
          }
          if (localStorage != null) {
            await localStorage.clearDirty([entry.id]);
          }

          successCount++;
        }
      } catch (e) {
        failureCount++;
        errors.add('Failed to push entry ${entry.id}: $e');
        if (kDebugMode) {
          print('SyncPushQueue error for ${entry.id}: $e');
        }
      }
    }

    return PushQueueResult(
      totalPending: pendingEntries.length,
      successCount: successCount,
      failureCount: failureCount,
      errors: errors,
    );
  }
}
