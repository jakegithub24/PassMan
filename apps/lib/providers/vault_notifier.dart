import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/encrypted_vault_entry.dart';
import '../models/vault_item.dart';
import '../services/crypto_service.dart';
import '../services/local_vault_storage_service.dart';
import '../services/vault_api_service.dart';
import '../utils/uuid_util.dart';
import 'vault_state.dart';

/// StateNotifier responsible for vault operations (listing, adding, editing, deleting, searching, remote CRUD synchronization)
class VaultNotifier extends StateNotifier<VaultState> {
  final LocalVaultStorageService localVaultStorage;
  final CryptoService cryptoService;
  final VaultApiService? vaultApiService;
  final List<int>? Function() getSessionKey;
  final String? Function() getUserId;

  VaultNotifier({
    required this.localVaultStorage,
    required this.cryptoService,
    this.vaultApiService,
    required this.getSessionKey,
    required this.getUserId,
  }) : super(const VaultState());

  /// Loads and decrypts all cached entries from local storage, then syncs with backend if online
  Future<void> loadVault({bool syncRemote = true}) async {
    final sessionKey = getSessionKey();
    if (sessionKey == null || sessionKey.isEmpty) {
      state = state.copyWith(
        status: VaultStatus.locked,
        items: const [],
      );
      return;
    }

    state = state.copyWith(
      status: VaultStatus.loading,
      clearError: true,
    );

    try {
      // 1. Load local cached entries first
      await _loadFromLocalStorage(sessionKey);

      // 2. Perform delta synchronization with backend if available
      if (syncRemote && vaultApiService != null) {
        await _syncWithRemote(sessionKey);
      }

      state = state.copyWith(
        status: VaultStatus.ready,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
        status: VaultStatus.ready, // Keep local items ready even if network sync errors
        errorMessage: 'Network sync error: $e',
      );
    }
  }

  /// Helper to read and decrypt all entries from SQLite/local storage
  Future<void> _loadFromLocalStorage(List<int> sessionKey) async {
    final entries = await localVaultStorage.getAllEntries(includeDeleted: false);
    final List<VaultItem> decryptedItems = [];

    for (final entry in entries) {
      try {
        final decryptedJson = await cryptoService.decryptVaultPayload(
          jsonPayload: entry.encryptedData,
          keyBytes: sessionKey,
        );
        final decodedMap = jsonDecode(decryptedJson) as Map<String, dynamic>;
        final item = VaultItem.fromJson(decodedMap);
        decryptedItems.add(item);
      } catch (_) {
        // Ignore corrupted entry
      }
    }

    state = state.copyWith(
      status: VaultStatus.ready,
      items: decryptedItems,
    );
  }

  /// Synchronizes local storage with backend delta sync endpoint (GET /api/vault/sync)
  Future<void> _syncWithRemote(List<int> sessionKey) async {
    if (vaultApiService == null) return;

    try {
      final syncResult = await vaultApiService!.syncEntries();

      for (final remoteEntry in syncResult.entries) {
        if (remoteEntry.isDeleted) {
          await localVaultStorage.markDeleted(remoteEntry.id);
        } else {
          await localVaultStorage.saveEntry(remoteEntry, isDirty: false);
        }
      }

      // Re-read local storage after applying server deltas
      await _loadFromLocalStorage(sessionKey);
    } catch (_) {
      // Fail gracefully in offline mode
    }
  }

  /// Encrypts and adds a new item to local storage and syncs to backend CRUD endpoint (POST /api/vault/entries)
  Future<VaultItem?> addEntry({
    required String title,
    required String username,
    required String password,
    String? url,
    String? notes,
    String category = 'logins',
  }) async {
    final sessionKey = getSessionKey();
    final userId = getUserId();

    if (sessionKey == null || sessionKey.isEmpty) {
      state = state.copyWith(
        status: VaultStatus.locked,
        errorMessage: 'Vault is locked. Cannot add item.',
      );
      return null;
    }

    final newItem = VaultItem(
      id: UuidUtil.generateV4(),
      title: title.trim(),
      username: username.trim(),
      password: password,
      url: url?.trim(),
      notes: notes?.trim(),
      category: category,
      updatedAt: DateTime.now().toUtc(),
    );

    try {
      final jsonPayload = jsonEncode(newItem.toJson());
      final encryptedPayload = await cryptoService.encryptVaultPayload(
        plaintext: jsonPayload,
        keyBytes: sessionKey,
      );

      final localEntry = EncryptedVaultEntry(
        id: newItem.id,
        userId: userId ?? '',
        encryptedData: encryptedPayload,
        updatedAt: newItem.updatedAt,
      );

      // Save locally first
      await localVaultStorage.saveEntry(localEntry, isDirty: true);

      // Optimistic in-memory update
      state = state.copyWith(
        status: VaultStatus.ready,
        items: [newItem, ...state.items],
        clearError: true,
      );

      // Sync to backend endpoint (POST /api/vault/entries) if online
      if (vaultApiService != null) {
        try {
          final serverEntry = await vaultApiService!.createEntry(encryptedPayload);
          // Mark clean in local storage with authoritative server ID / timestamp
          await localVaultStorage.saveEntry(serverEntry, isDirty: false);
        } catch (_) {
          // Kept dirty in local storage for background sync queue
        }
      }

      return newItem;
    } catch (e) {
      state = state.copyWith(
        status: VaultStatus.error,
        errorMessage: 'Failed to save new entry: $e',
      );
      return null;
    }
  }

  /// Re-encrypts and updates an existing entry locally and on backend (PUT /api/vault/entries/{id})
  Future<bool> updateEntry(VaultItem updatedItem) async {
    final sessionKey = getSessionKey();
    final userId = getUserId();

    if (sessionKey == null || sessionKey.isEmpty) {
      state = state.copyWith(
        status: VaultStatus.locked,
        errorMessage: 'Vault is locked. Cannot update item.',
      );
      return false;
    }

    final itemWithNewTimestamp = updatedItem.copyWith(
      updatedAt: DateTime.now().toUtc(),
    );

    try {
      final jsonPayload = jsonEncode(itemWithNewTimestamp.toJson());
      final encryptedPayload = await cryptoService.encryptVaultPayload(
        plaintext: jsonPayload,
        keyBytes: sessionKey,
      );

      final localEntry = EncryptedVaultEntry(
        id: itemWithNewTimestamp.id,
        userId: userId ?? '',
        encryptedData: encryptedPayload,
        updatedAt: itemWithNewTimestamp.updatedAt,
      );

      await localVaultStorage.saveEntry(localEntry, isDirty: true);

      // Update in-memory item
      final updatedList = state.items.map((item) {
        return item.id == itemWithNewTimestamp.id ? itemWithNewTimestamp : item;
      }).toList();

      state = state.copyWith(
        status: VaultStatus.ready,
        items: updatedList,
        clearError: true,
      );

      // Sync to backend endpoint (PUT /api/vault/entries/{id}) if online
      if (vaultApiService != null) {
        try {
          final serverEntry = await vaultApiService!.updateEntry(
            itemWithNewTimestamp.id,
            encryptedPayload,
          );
          await localVaultStorage.saveEntry(serverEntry, isDirty: false);
        } catch (_) {
          // Kept dirty in local storage for background sync queue
        }
      }

      return true;
    } catch (e) {
      state = state.copyWith(
        status: VaultStatus.error,
        errorMessage: 'Failed to update entry: $e',
      );
      return false;
    }
  }

  /// Soft deletes an entry locally and on backend (DELETE /api/vault/entries/{id})
  Future<bool> deleteEntry(String id) async {
    try {
      await localVaultStorage.markDeleted(id);

      final updatedList = state.items.where((item) => item.id != id).toList();

      state = state.copyWith(
        status: VaultStatus.ready,
        items: updatedList,
        clearError: true,
      );

      // Sync to backend endpoint (DELETE /api/vault/entries/{id}) if online
      if (vaultApiService != null) {
        try {
          await vaultApiService!.deleteEntry(id);
        } catch (_) {
          // Kept marked as dirty/tombstone locally
        }
      }

      return true;
    } catch (e) {
      state = state.copyWith(
        status: VaultStatus.error,
        errorMessage: 'Failed to delete entry: $e',
      );
      return false;
    }
  }

  /// Triggers a manual sync with backend
  Future<void> syncWithServer() async {
    final sessionKey = getSessionKey();
    if (sessionKey != null && sessionKey.isNotEmpty) {
      await _syncWithRemote(sessionKey);
    }
  }

  /// Updates live search query filter
  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  /// Updates category filter (e.g. 'all', 'logins', 'cards', 'notes')
  void setCategory(String category) {
    state = state.copyWith(selectedCategory: category);
  }

  /// Clears search query
  void clearSearch() {
    state = state.copyWith(searchQuery: '');
  }

  /// Wipes in-memory decrypted items on vault lock or logout
  void clear() {
    state = const VaultState(status: VaultStatus.locked);
  }

  /// Clears any transient error message
  void clearError() {
    state = state.copyWith(clearError: true);
  }
}
