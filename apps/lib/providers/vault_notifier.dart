import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/encrypted_vault_entry.dart';
import '../models/vault_item.dart';
import '../services/crypto_service.dart';
import '../services/local_vault_storage_service.dart';
import '../utils/uuid_util.dart';
import 'vault_state.dart';

/// StateNotifier responsible for vault operations (listing, adding, editing, deleting, searching)
class VaultNotifier extends StateNotifier<VaultState> {
  final LocalVaultStorageService localVaultStorage;
  final CryptoService cryptoService;
  final List<int>? Function() getSessionKey;
  final String? Function() getUserId;

  VaultNotifier({
    required this.localVaultStorage,
    required this.cryptoService,
    required this.getSessionKey,
    required this.getUserId,
  }) : super(const VaultState());

  /// Loads and decrypts all cached entries from local storage using active session key
  Future<void> loadVault() async {
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
          // Ignore corrupt entry
        }
      }

      state = state.copyWith(
        status: VaultStatus.ready,
        items: decryptedItems,
      );
    } catch (e) {
      state = state.copyWith(
        status: VaultStatus.error,
        errorMessage: 'Failed to load vault items: $e',
      );
    }
  }

  /// Encrypts and adds a new item to local storage and updates in-memory state
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

      final entry = EncryptedVaultEntry(
        id: newItem.id,
        userId: userId ?? '',
        encryptedData: encryptedPayload,
        updatedAt: newItem.updatedAt,
      );

      await localVaultStorage.saveEntry(entry, isDirty: true);

      // Optimistic in-memory update
      state = state.copyWith(
        status: VaultStatus.ready,
        items: [newItem, ...state.items],
        clearError: true,
      );

      return newItem;
    } catch (e) {
      state = state.copyWith(
        status: VaultStatus.error,
        errorMessage: 'Failed to save new entry: $e',
      );
      return null;
    }
  }

  /// Re-encrypts and updates an existing entry
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

      final entry = EncryptedVaultEntry(
        id: itemWithNewTimestamp.id,
        userId: userId ?? '',
        encryptedData: encryptedPayload,
        updatedAt: itemWithNewTimestamp.updatedAt,
      );

      await localVaultStorage.saveEntry(entry, isDirty: true);

      // Update in-memory item
      final updatedList = state.items.map((item) {
        return item.id == itemWithNewTimestamp.id ? itemWithNewTimestamp : item;
      }).toList();

      state = state.copyWith(
        status: VaultStatus.ready,
        items: updatedList,
        clearError: true,
      );

      return true;
    } catch (e) {
      state = state.copyWith(
        status: VaultStatus.error,
        errorMessage: 'Failed to update entry: $e',
      );
      return false;
    }
  }

  /// Soft deletes an entry in local storage and removes it from active state
  Future<bool> deleteEntry(String id) async {
    try {
      await localVaultStorage.markDeleted(id);

      final updatedList = state.items.where((item) => item.id != id).toList();

      state = state.copyWith(
        status: VaultStatus.ready,
        items: updatedList,
        clearError: true,
      );

      return true;
    } catch (e) {
      state = state.copyWith(
        status: VaultStatus.error,
        errorMessage: 'Failed to delete entry: $e',
      );
      return false;
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
