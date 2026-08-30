import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sync_state.dart';
import '../providers/vault_notifier.dart';

/// Sync Engine and Trigger Manager implementing MVP.md §6 / Task 9.1:
/// Listens to 3 explicit triggers (no polling loop):
///   1. App launch
///   2. App resume from background
///   3. Manual pull-to-refresh / "Sync Now" button
class SyncEngine extends StateNotifier<SyncState> with WidgetsBindingObserver {
  final VaultNotifier vaultNotifier;
  bool _isObserverRegistered = false;

  SyncEngine({
    required this.vaultNotifier,
  }) : super(const SyncState()) {
    _registerLifecycleObserver();
  }

  void _registerLifecycleObserver() {
    if (!_isObserverRegistered) {
      WidgetsBinding.instance.addObserver(this);
      _isObserverRegistered = true;
    }
  }

  @override
  void dispose() {
    if (_isObserverRegistered) {
      WidgetsBinding.instance.removeObserver(this);
      _isObserverRegistered = false;
    }
    super.dispose();
  }

  /// Hook 2: App Resume from background
  @override
  void didChangeAppLifecycleState(AppLifecycleState appLifecycleState) {
    if (appLifecycleState == AppLifecycleState.resumed) {
      triggerAppResume();
    }
  }

  /// Hook 1: App Launch Sync Trigger
  Future<void> triggerAppLaunch() async {
    await _executeSync(SyncTrigger.appLaunch);
  }

  /// Hook 2: App Resume Sync Trigger
  Future<void> triggerAppResume() async {
    await _executeSync(SyncTrigger.appResume);
  }

  /// Hook 3: Manual Pull-to-Refresh / "Sync Now" Trigger
  Future<void> triggerManualRefresh() async {
    await _executeSync(SyncTrigger.manualRefresh);
  }

  /// Core sync execution orchestrator with concurrency guard
  Future<void> _executeSync(SyncTrigger trigger) async {
    // Prevent overlapping sync executions
    if (state.isSyncing) return;

    state = state.copyWith(
      status: SyncStatus.syncing,
      lastTrigger: trigger,
      clearError: true,
    );

    try {
      // Execute delta sync via VaultNotifier
      await vaultNotifier.syncWithServer();

      final now = DateTime.now().toUtc();
      state = state.copyWith(
        status: SyncStatus.success,
        lastSyncedAt: now,
        serverTime: now,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
        status: SyncStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// Manually reset status to idle
  void resetIdle() {
    state = state.copyWith(status: SyncStatus.idle);
  }
}
