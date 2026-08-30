import 'package:apps/models/sync_state.dart';
import 'package:apps/providers/vault_notifier.dart';
import 'package:apps/services/crypto_service.dart';
import 'package:apps/services/local_vault_storage_service.dart';
import 'package:apps/services/sync_engine.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class MockSyncVaultNotifier extends VaultNotifier {
  int syncCallCount = 0;
  bool shouldThrow = false;

  MockSyncVaultNotifier()
      : super(
          localVaultStorage: LocalVaultStorageService(),
          cryptoService: CryptoService(pbkdf2Iterations: 1000),
          getSessionKey: () => [1, 2, 3],
          getUserId: () => 'u1',
        );

  @override
  Future<void> syncWithServer() async {
    syncCallCount++;
    if (shouldThrow) {
      throw Exception('Network unreachable');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSyncVaultNotifier mockVaultNotifier;
  late SyncEngine syncEngine;

  setUp(() {
    mockVaultNotifier = MockSyncVaultNotifier();
    syncEngine = SyncEngine(vaultNotifier: mockVaultNotifier);
  });

  tearDown(() {
    syncEngine.dispose();
  });

  group('SyncEngine Trigger Hooks (Task 9.1 / MVP.md §6)', () {
    test('Hook 1: triggerAppLaunch triggers delta sync with appLaunch tag', () async {
      expect(syncEngine.state.status, equals(SyncStatus.idle));

      await syncEngine.triggerAppLaunch();

      expect(mockVaultNotifier.syncCallCount, equals(1));
      expect(syncEngine.state.status, equals(SyncStatus.success));
      expect(syncEngine.state.lastTrigger, equals(SyncTrigger.appLaunch));
      expect(syncEngine.state.lastSyncedAt, isNotNull);
    });

    test('Hook 2: didChangeAppLifecycleState with resumed triggers appResume sync', () async {
      syncEngine.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(mockVaultNotifier.syncCallCount, equals(1));
      expect(syncEngine.state.status, equals(SyncStatus.success));
      expect(syncEngine.state.lastTrigger, equals(SyncTrigger.appResume));
    });

    test('Hook 2: didChangeAppLifecycleState with paused/inactive does not trigger sync', () async {
      syncEngine.didChangeAppLifecycleState(AppLifecycleState.paused);
      syncEngine.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(mockVaultNotifier.syncCallCount, equals(0));
      expect(syncEngine.state.status, equals(SyncStatus.idle));
    });

    test('Hook 3: triggerManualRefresh triggers delta sync with manualRefresh tag', () async {
      await syncEngine.triggerManualRefresh();

      expect(mockVaultNotifier.syncCallCount, equals(1));
      expect(syncEngine.state.status, equals(SyncStatus.success));
      expect(syncEngine.state.lastTrigger, equals(SyncTrigger.manualRefresh));
    });

    test('Concurrency guard ignores overlapping triggers while syncing', () async {
      // Simulate in-progress sync
      syncEngine.triggerAppLaunch();
      expect(syncEngine.state.isSyncing, isTrue);

      // Concurrent second trigger while syncing
      await syncEngine.triggerManualRefresh();

      // Only 1 sync execution should have occurred
      expect(mockVaultNotifier.syncCallCount, equals(1));
    });

    test('Error handling captures sync failures gracefully without crashing', () async {
      mockVaultNotifier.shouldThrow = true;

      await syncEngine.triggerManualRefresh();

      expect(syncEngine.state.status, equals(SyncStatus.error));
      expect(syncEngine.state.errorMessage, contains('Network unreachable'));
      expect(syncEngine.state.hasError, isTrue);
    });
  });
}
