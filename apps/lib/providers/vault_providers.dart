import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/vault_item.dart';
import '../services/local_vault_storage_service.dart';
import 'auth_providers.dart';
import 'vault_notifier.dart';
import 'vault_state.dart';

// -----------------------------------------------------------------------------
// Service Providers
// -----------------------------------------------------------------------------

/// Provider for LocalVaultStorageService handling local SQLite/Hive persistence
final Provider<LocalVaultStorageService> localVaultStorageServiceProvider =
    Provider<LocalVaultStorageService>((ref) {
  return LocalVaultStorageService();
});

// -----------------------------------------------------------------------------
// Vault State Notifier Provider
// -----------------------------------------------------------------------------

/// Main VaultState notifier provider
final StateNotifierProvider<VaultNotifier, VaultState> vaultStateProvider =
    StateNotifierProvider<VaultNotifier, VaultState>((ref) {
  final localVaultStorage = ref.watch(localVaultStorageServiceProvider);
  final cryptoService = ref.watch(cryptoServiceProvider);

  return VaultNotifier(
    localVaultStorage: localVaultStorage,
    cryptoService: cryptoService,
    getSessionKey: () => ref.read(sessionKeyProvider),
    getUserId: () => ref.read(currentUserProvider)?.id,
  );
});

// -----------------------------------------------------------------------------
// Granular Selectors & Convenience Providers
// -----------------------------------------------------------------------------

/// Provides active filtered decrypted vault items matching current search and category
final Provider<List<VaultItem>> vaultItemsProvider = Provider<List<VaultItem>>((ref) {
  return ref.watch(vaultStateProvider).filteredItems;
});

/// Provides total non-deleted vault items count
final Provider<int> vaultItemsCountProvider = Provider<int>((ref) {
  return ref.watch(vaultStateProvider).items.where((i) => !i.isDeleted).length;
});

/// Provides current vault lifecycle status
final Provider<VaultStatus> vaultStatusProvider = Provider<VaultStatus>((ref) {
  return ref.watch(vaultStateProvider).status;
});

/// Provides current live search query
final Provider<String> vaultSearchQueryProvider = Provider<String>((ref) {
  return ref.watch(vaultStateProvider).searchQuery;
});

/// Provides current selected category filter
final Provider<String> vaultCategoryProvider = Provider<String>((ref) {
  return ref.watch(vaultStateProvider).selectedCategory;
});
