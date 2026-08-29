import 'package:flutter/foundation.dart';
import '../models/vault_item.dart';

/// Lifecycle statuses for the local decrypted vault state
enum VaultStatus {
  initial,
  loading,
  ready,
  syncing,
  locked,
  error,
}

/// Immutable state model for the user's decrypted password vault
class VaultState {
  final VaultStatus status;
  final List<VaultItem> items;
  final String searchQuery;
  final String selectedCategory;
  final String? errorMessage;
  final bool isSyncing;

  const VaultState({
    this.status = VaultStatus.initial,
    this.items = const [],
    this.searchQuery = '',
    this.selectedCategory = 'all',
    this.errorMessage,
    this.isSyncing = false,
  });

  bool get isLoading => status == VaultStatus.loading;
  bool get isLocked => status == VaultStatus.locked;
  bool get isReady => status == VaultStatus.ready;
  bool get hasError => errorMessage != null;

  /// Returns active non-deleted items matching active search query and category filter
  List<VaultItem> get filteredItems {
    return items.where((item) {
      if (item.isDeleted) return false;

      // 1. Category filter
      if (selectedCategory != 'all' &&
          item.category.toLowerCase() != selectedCategory.toLowerCase()) {
        return false;
      }

      // 2. Search query filter
      if (searchQuery.trim().isNotEmpty) {
        final query = searchQuery.trim().toLowerCase();
        final matchesTitle = item.title.toLowerCase().contains(query);
        final matchesUsername = item.username.toLowerCase().contains(query);
        final matchesUrl = item.url?.toLowerCase().contains(query) ?? false;
        final matchesNotes = item.notes?.toLowerCase().contains(query) ?? false;

        if (!matchesTitle && !matchesUsername && !matchesUrl && !matchesNotes) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  VaultState copyWith({
    VaultStatus? status,
    List<VaultItem>? items,
    String? searchQuery,
    String? selectedCategory,
    String? errorMessage,
    bool? isSyncing,
    bool clearError = false,
  }) {
    return VaultState(
      status: status ?? this.status,
      items: items ?? this.items,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isSyncing: isSyncing ?? this.isSyncing,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VaultState &&
        other.status == status &&
        listEquals(other.items, items) &&
        other.searchQuery == searchQuery &&
        other.selectedCategory == selectedCategory &&
        other.errorMessage == errorMessage &&
        other.isSyncing == isSyncing;
  }

  @override
  int get hashCode => Object.hash(
        status,
        Object.hashAll(items),
        searchQuery,
        selectedCategory,
        errorMessage,
        isSyncing,
      );
}
