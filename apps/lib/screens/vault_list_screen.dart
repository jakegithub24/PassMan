import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/vault_item.dart';
import '../providers/auth_providers.dart';
import '../providers/vault_providers.dart';
import '../providers/vault_state.dart';
import '../theme/app_theme.dart';
import 'add_edit_entry_screen.dart';

/// Comprehensive, responsive, fluent Vault List screen for Android, Web, and Desktop
class VaultListScreen extends ConsumerStatefulWidget {
  final VoidCallback? onAddNew;
  final ValueChanged<VaultItem>? onEditItem;
  final ValueChanged<VaultItem>? onDeleteItem;

  const VaultListScreen({
    super.key,
    this.onAddNew,
    this.onEditItem,
    this.onDeleteItem,
  });

  @override
  ConsumerState<VaultListScreen> createState() => _VaultListScreenState();
}

class _VaultListScreenState extends ConsumerState<VaultListScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Load vault items on first mount
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(vaultStateProvider.notifier).loadVault();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text('$label copied to clipboard!'),
          ],
        ),
        backgroundColor: AppColors.navyDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vaultState = ref.watch(vaultStateProvider);
    final user = ref.watch(currentUserProvider);
    final items = vaultState.filteredItems;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 900;
        final bool isTablet = constraints.maxWidth >= 600 && constraints.maxWidth < 900;

        return Scaffold(
          backgroundColor: AppColors.frameBg,
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFEEF3F1),
                  Color(0xFFDBE9F6),
                  Color(0xFFE4EEFA),
                ],
              ),
            ),
            child: SafeArea(
              child: isDesktop
                  ? _buildDesktopLayout(context, vaultState, items, user)
                  : _buildMobileTabletLayout(context, vaultState, items, isTablet),
            ),
          ),
          floatingActionButton: !isDesktop
              ? FloatingActionButton.extended(
                  onPressed: widget.onAddNew ?? () => _showAddEntryStub(context),
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text(
                    'New Item',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                )
              : null,
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Desktop Layout (Sidebar + Content View)
  // ---------------------------------------------------------------------------

  Widget _buildDesktopLayout(
    BuildContext context,
    VaultState vaultState,
    List<VaultItem> items,
    dynamic user,
  ) {
    return Row(
      children: [
        // Sidebar Navigation Rail
        SizedBox(
          width: 260,
          child: _buildSidebar(context, vaultState, user),
        ),

        // Main Vault Area
        Expanded(
          child: Column(
            children: [
              _buildDesktopHeader(context, vaultState),
              Expanded(
                child: _buildVaultContent(context, vaultState, items),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSidebar(BuildContext context, VaultState vaultState, dynamic user) {
    final categories = [
      {'id': 'all', 'label': 'All Items', 'icon': Icons.folder_copy_rounded},
      {'id': 'logins', 'label': 'Logins', 'icon': Icons.lock_outline_rounded},
      {'id': 'cards', 'label': 'Cards', 'icon': Icons.credit_card_rounded},
      {'id': 'notes', 'label': 'Secure Notes', 'icon': Icons.note_alt_outlined},
    ];

    return Container(
      margin: const EdgeInsets.all(12),
      child: AppGlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        borderRadius: 20,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App Brand
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.shield_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'PassMan',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.ink,
                      letterSpacing: -0.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0x1F12A37F),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.pillGreen.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_open_rounded, size: 10, color: AppColors.pillGreen),
                      SizedBox(width: 3),
                      Text(
                        'Secure',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppColors.pillGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Primary Add Action
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: widget.onAddNew ?? () => _showAddEntryStub(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Item', style: TextStyle(fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Category Navigation Items
            const Text(
              'CATEGORIES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.inkSoft,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 10),

            Expanded(
              child: ListView.builder(
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final cat = categories[index];
                  final isSelected = vaultState.selectedCategory == cat['id'];
                  final count = cat['id'] == 'all'
                      ? vaultState.items.where((i) => !i.isDeleted).length
                      : vaultState.items
                          .where((i) => !i.isDeleted && i.category == cat['id'])
                          .length;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: InkWell(
                      onTap: () {
                        ref.read(vaultStateProvider.notifier).setCategory(cat['id'] as String);
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.navy.withValues(alpha: 0.1) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: isSelected
                              ? Border.all(color: AppColors.navy.withValues(alpha: 0.25))
                              : null,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              cat['icon'] as IconData,
                              size: 18,
                              color: isSelected ? AppColors.navy : AppColors.inkSoft,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                cat['label'] as String,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                  color: isSelected ? AppColors.navy : AppColors.ink,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.navy.withValues(alpha: 0.15)
                                    : Colors.black.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$count',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected ? AppColors.navy : AppColors.inkSoft,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const Divider(color: AppColors.hairline),
            const SizedBox(height: 12),

            // Profile & Lock Actions
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.navy.withValues(alpha: 0.15),
                  child: Text(
                    user != null && user.email.isNotEmpty
                        ? user.email[0].toUpperCase()
                        : 'U',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navy,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        user?.email ?? 'User Vault',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Text(
                        'AES-256 Encrypted',
                        style: TextStyle(fontSize: 10, color: AppColors.inkSoft),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Lock Vault',
                  icon: const Icon(Icons.lock_rounded, size: 18, color: AppColors.inkSoft),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(6),
                  onPressed: () {
                    ref.read(authNotifierProvider.notifier).lockVault();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopHeader(BuildContext context, VaultState vaultState) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 16, 16, 12),
      child: AppGlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        borderRadius: 20,
        child: Row(
          children: [
            // Search Box
            Expanded(
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.inputBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.inputBorder),
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  onChanged: (val) {
                    ref.read(vaultStateProvider.notifier).setSearchQuery(val);
                  },
                  decoration: InputDecoration(
                    hintText: 'Search passwords, usernames, and notes...',
                    hintStyle: const TextStyle(fontSize: 14, color: AppColors.inkLight),
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.inkSoft, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              ref.read(vaultStateProvider.notifier).clearSearch();
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),

            // Quick Refresh Button
            IconButton(
              tooltip: 'Refresh Vault',
              icon: const Icon(Icons.refresh_rounded, color: AppColors.inkSoft),
              onPressed: () {
                ref.read(vaultStateProvider.notifier).loadVault();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Mobile & Tablet Layout
  // ---------------------------------------------------------------------------

  Widget _buildMobileTabletLayout(
    BuildContext context,
    VaultState vaultState,
    List<VaultItem> items,
    bool isTablet,
  ) {
    final categories = [
      {'id': 'all', 'label': 'All'},
      {'id': 'logins', 'label': 'Logins'},
      {'id': 'cards', 'label': 'Cards'},
      {'id': 'notes', 'label': 'Notes'},
    ];

    return Column(
      children: [
        // App Bar Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.shield_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'My Passwords',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.ink,
                    letterSpacing: -0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Lock Vault',
                icon: const Icon(Icons.lock_outline_rounded, color: AppColors.navy, size: 20),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(8),
                onPressed: () {
                  ref.read(authNotifierProvider.notifier).lockVault();
                },
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.sync_rounded, color: AppColors.inkSoft, size: 20),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(8),
                onPressed: () {
                  ref.read(vaultStateProvider.notifier).loadVault();
                },
              ),
            ],
          ),
        ),

        // Search Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Container(
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.inputBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.inputBorder),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                ref.read(vaultStateProvider.notifier).setSearchQuery(val);
              },
              decoration: InputDecoration(
                hintText: 'Search entries...',
                hintStyle: const TextStyle(fontSize: 14, color: AppColors.inkLight),
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.inkSoft, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(vaultStateProvider.notifier).clearSearch();
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),

        // Category Filter Chips
        SizedBox(
          height: 44,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final cat = categories[index];
              final isSelected = vaultState.selectedCategory == cat['id'];

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(cat['label']!),
                  selected: isSelected,
                  onSelected: (selected) {
                    ref.read(vaultStateProvider.notifier).setCategory(cat['id']!);
                  },
                  backgroundColor: AppColors.glassWhite,
                  selectedColor: AppColors.navy,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : AppColors.ink,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isSelected ? AppColors.navy : AppColors.glassBorderStrong,
                    ),
                  ),
                  showCheckmark: false,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),

        // Main List Content
        Expanded(
          child: _buildVaultContent(context, vaultState, items),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Shared Vault Content Area (Grid / List / Empty / Loading / Locked)
  // ---------------------------------------------------------------------------

  Widget _buildVaultContent(
    BuildContext context,
    VaultState vaultState,
    List<VaultItem> items,
  ) {
    if (vaultState.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.navy),
      );
    }

    if (vaultState.isLocked) {
      return _buildLockedState(context);
    }

    if (items.isEmpty) {
      return _buildEmptyState(context, vaultState.searchQuery.isNotEmpty);
    }

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(vaultStateProvider.notifier).loadVault();
      },
      color: AppColors.navy,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMultiColumn = constraints.maxWidth >= 720;
          final crossAxisCount = constraints.maxWidth >= 1200 ? 3 : (isMultiColumn ? 2 : 1);

          if (isMultiColumn) {
            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                mainAxisExtent: 145,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                return _buildVaultCard(context, items[index]);
              },
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            itemCount: items.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildVaultCard(context, items[index]),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildVaultCard(BuildContext context, VaultItem item) {
    final categoryColor = _getCategoryColor(item.category);
    final categoryIcon = _getCategoryIcon(item.category);

    return AppGlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 18,
      child: InkWell(
        onTap: () {
          if (widget.onEditItem != null) {
            widget.onEditItem!(item);
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                // Category Icon Avatar
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: categoryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: categoryColor.withValues(alpha: 0.3)),
                  ),
                  child: Icon(categoryIcon, color: categoryColor, size: 20),
                ),
                const SizedBox(width: 12),

                // Title & Subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.ink,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.username.isNotEmpty ? item.username : (item.url ?? 'No username'),
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.inkSoft,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // Menu Popup
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppColors.inkSoft),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: (action) {
                    if (action == 'copy_user') {
                      _copyToClipboard(context, item.username, 'Username');
                    } else if (action == 'copy_pass') {
                      _copyToClipboard(context, item.password, 'Password');
                    } else if (action == 'edit' && widget.onEditItem != null) {
                      widget.onEditItem!(item);
                    } else if (action == 'delete') {
                      _confirmDelete(context, item);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'copy_user',
                      child: Row(
                        children: [
                          Icon(Icons.person_outline_rounded, size: 18),
                          SizedBox(width: 10),
                          Text('Copy Username'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'copy_pass',
                      child: Row(
                        children: [
                          Icon(Icons.key_rounded, size: 18),
                          SizedBox(width: 10),
                          Text('Copy Password'),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 10),
                          Text('Edit Entry'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded, color: AppColors.red, size: 18),
                          SizedBox(width: 10),
                          Text('Delete', style: TextStyle(color: AppColors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Bottom row: password dots and quick copy buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.circle, size: 6, color: AppColors.inkLight),
                    SizedBox(width: 3),
                    Icon(Icons.circle, size: 6, color: AppColors.inkLight),
                    SizedBox(width: 3),
                    Icon(Icons.circle, size: 6, color: AppColors.inkLight),
                    SizedBox(width: 3),
                    Icon(Icons.circle, size: 6, color: AppColors.inkLight),
                    SizedBox(width: 3),
                    Icon(Icons.circle, size: 6, color: AppColors.inkLight),
                    SizedBox(width: 3),
                    Icon(Icons.circle, size: 6, color: AppColors.inkLight),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Copy Username',
                      icon: const Icon(Icons.person_rounded, size: 18, color: AppColors.navy),
                      onPressed: () => _copyToClipboard(context, item.username, 'Username'),
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    IconButton(
                      tooltip: 'Copy Password',
                      icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.navy),
                      onPressed: () => _copyToClipboard(context, item.password, 'Password'),
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isSearching) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.navy.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isSearching ? Icons.search_off_rounded : Icons.lock_outline_rounded,
                size: 64,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isSearching ? 'No matching passwords found' : 'Your vault is currently empty',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isSearching
                  ? 'Try searching with another title, username, or website.'
                  : 'Add your first password or card to keep it encrypted and safe.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppColors.inkSoft),
            ),
            const SizedBox(height: 24),
            if (isSearching)
              OutlinedButton(
                onPressed: () {
                  _searchController.clear();
                  ref.read(vaultStateProvider.notifier).clearSearch();
                },
                child: const Text('Clear Search'),
              )
            else
              ElevatedButton.icon(
                onPressed: widget.onAddNew ?? () => _showAddEntryStub(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add Password'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLockedState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_rounded, size: 64, color: AppColors.navyDark),
            ),
            const SizedBox(height: 20),
            const Text(
              'Vault is Locked',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your master password is required to decrypt your vault items.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.inkSoft),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, VaultItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Entry?'),
        content: Text('Are you sure you want to delete "${item.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(vaultStateProvider.notifier).deleteEntry(item.id);
              if (widget.onDeleteItem != null) {
                widget.onDeleteItem!(item);
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showAddEntryStub(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AddEditEntryScreen(),
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'cards':
        return AppColors.pillGreen;
      case 'notes':
        return const Color(0xFFD97706);
      case 'logins':
      default:
        return AppColors.navy;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'cards':
        return Icons.credit_card_rounded;
      case 'notes':
        return Icons.note_alt_outlined;
      case 'logins':
      default:
        return Icons.lock_outline_rounded;
    }
  }
}
