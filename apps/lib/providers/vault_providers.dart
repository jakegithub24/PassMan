import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sync_state.dart';
import '../models/vault_item.dart';
import '../repositories/vault_cache_repository.dart';
import '../services/local_vault_storage_service.dart';
import '../services/sync_engine.dart';
import '../services/vault_api_service.dart';
import 'auth_providers.dart';
import 'vault_notifier.dart';
import 'vault_state.dart';

// -----------------------------------------------------------------------------
// Service & Repository Providers
// -----------------------------------------------------------------------------

/// Provider for LocalVaultStorageService handling local SQLite/Hive persistence
final Provider<LocalVaultStorageService> localVaultStorageServiceProvider =
    Provider<LocalVaultStorageService>((ref) {
  return LocalVaultStorageService();
});

/// Provider for platform-agnostic IVaultCacheRepository (Task 8.4)
final Provider<IVaultCacheRepository> vaultCacheRepositoryProvider =
    Provider<IVaultCacheRepository>((ref) {
  return VaultCacheRepository.create();
});

/// Provider for VaultApiService handling backend CRUD endpoints
final Provider<VaultApiService> vaultApiServiceProvider =
    Provider<VaultApiService>((ref) {
  final dio = ref.watch(dioClientProvider);
  return VaultApiService(dio: dio);
});

// -----------------------------------------------------------------------------
// Vault State Notifier Provider
// -----------------------------------------------------------------------------

/// Main VaultState notifier provider
final StateNotifierProvider<VaultNotifier, VaultState> vaultStateProvider =
    StateNotifierProvider<VaultNotifier, VaultState>((ref) {
  final localVaultStorage = ref.watch(localVaultStorageServiceProvider);
  final cacheRepository = ref.watch(vaultCacheRepositoryProvider);
  final secureStorage = ref.watch(secureStorageServiceProvider);
  final cryptoService = ref.watch(cryptoServiceProvider);
  final vaultApiService = ref.watch(vaultApiServiceProvider);

  return VaultNotifier(
    localVaultStorage: localVaultStorage,
    cacheRepository: cacheRepository,
    secureStorage: secureStorage,
    cryptoService: cryptoService,
    vaultApiService: vaultApiService,
    getSessionKey: () => ref.read(sessionKeyProvider),
    getUserId: () => ref.read(currentUserProvider)?.id,
  );
});

/// Provider for SyncEngine (Task 9.1)
final StateNotifierProvider<SyncEngine, SyncState> syncEngineProvider =
    StateNotifierProvider<SyncEngine, SyncState>((ref) {
  final vaultNotifier = ref.watch(vaultStateProvider.notifier);
  return SyncEngine(vaultNotifier: vaultNotifier);
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
