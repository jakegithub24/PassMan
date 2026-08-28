enum SyncStatus {
  idle,
  syncing,
  success,
  error,
  offline,
}

class SyncState {
  final SyncStatus status;
  final DateTime? lastSyncedAt;
  final DateTime? serverTime;
  final int pendingUploadsCount;
  final String? errorMessage;

  const SyncState({
    this.status = SyncStatus.idle,
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
    DateTime? lastSyncedAt,
    DateTime? serverTime,
    int? pendingUploadsCount,
    String? errorMessage,
  }) {
    return SyncState(
      status: status ?? this.status,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      serverTime: serverTime ?? this.serverTime,
      pendingUploadsCount: pendingUploadsCount ?? this.pendingUploadsCount,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
