enum SyncStatus {
  idle,
  syncing,
  success,
  error,
  offline,
}

enum SyncTrigger {
  appLaunch,
  appResume,
  manualRefresh,
}

class SyncState {
  final SyncStatus status;
  final SyncTrigger? lastTrigger;
  final DateTime? lastSyncedAt;
  final DateTime? serverTime;
  final int pendingUploadsCount;
  final String? errorMessage;

  const SyncState({
    this.status = SyncStatus.idle,
    this.lastTrigger,
    this.lastSyncedAt,
    this.serverTime,
    this.pendingUploadsCount = 0,
    this.errorMessage,
  });

  bool get isSyncing => status == SyncStatus.syncing;
  bool get hasError => status == SyncStatus.error;
  bool get isOffline => status == SyncStatus.offline;

  SyncState copyWith({
    SyncStatus? status,
    SyncTrigger? lastTrigger,
    DateTime? lastSyncedAt,
    DateTime? serverTime,
    int? pendingUploadsCount,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SyncState(
      status: status ?? this.status,
      lastTrigger: lastTrigger ?? this.lastTrigger,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      serverTime: serverTime ?? this.serverTime,
      pendingUploadsCount: pendingUploadsCount ?? this.pendingUploadsCount,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
