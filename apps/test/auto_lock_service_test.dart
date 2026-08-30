import 'package:apps/services/auto_lock_service.dart';
import 'package:apps/services/secure_storage_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  late SecureStorageService secureStorage;
  int lockCalls = 0;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    secureStorage = SecureStorageService();
    lockCalls = 0;
  });

  group('AutoLockService Unit Tests (Task 10.2 / MVP.md §7)', () {
    test('User-selectable auto-lock timer preference (5–30 min)', () async {
      final autoLockService = AutoLockService(
        secureStorage: secureStorage,
        onLockVault: () => lockCalls++,
        getUserId: () => 'user-1',
      );

      // Default timeout is 5 minutes
      expect(autoLockService.timeoutMinutes, equals(5));

      // Update to 15 minutes
      await autoLockService.setTimeoutMinutes(15);
      expect(autoLockService.timeoutMinutes, equals(15));
      expect(await secureStorage.getAutoLockTimeoutMinutes(userId: 'user-1'), equals(15));

      // Update to 30 minutes
      await autoLockService.setTimeoutMinutes(30);
      expect(autoLockService.timeoutMinutes, equals(30));
      expect(await secureStorage.getAutoLockTimeoutMinutes(userId: 'user-1'), equals(30));

      autoLockService.dispose();
    });

    test('Immediate background lock (timeout = 0) locks vault on paused/inactive', () async {
      final autoLockService = AutoLockService(
        secureStorage: secureStorage,
        onLockVault: () => lockCalls++,
        getUserId: () => 'user-1',
        initialTimeoutMinutes: 0,
      );

      autoLockService.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(lockCalls, equals(1));

      autoLockService.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(lockCalls, equals(2));

      autoLockService.dispose();
    });

    test('Background duration exceeding timeout locks vault on resume', () async {
      final autoLockService = AutoLockService(
        secureStorage: secureStorage,
        onLockVault: () => lockCalls++,
        getUserId: () => 'user-1',
        initialTimeoutMinutes: 5,
        customInactivityDuration: const Duration(milliseconds: 50),
      );

      // App backgrounded
      autoLockService.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(lockCalls, equals(0));

      // Wait longer than custom duration (60ms > 50ms)
      await Future.delayed(const Duration(milliseconds: 60));

      // App resumed
      autoLockService.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(lockCalls, equals(1));

      autoLockService.dispose();
    });

    test('Background duration within timeout does not lock on resume', () async {
      final autoLockService = AutoLockService(
        secureStorage: secureStorage,
        onLockVault: () => lockCalls++,
        getUserId: () => 'user-1',
        initialTimeoutMinutes: 5,
        customInactivityDuration: const Duration(seconds: 10),
      );

      // App backgrounded
      autoLockService.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(lockCalls, equals(0));

      // App quickly resumed (within 100ms < 10s)
      await Future.delayed(const Duration(milliseconds: 50));
      autoLockService.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect(lockCalls, equals(0));

      autoLockService.dispose();
    });

    test('Foreground inactivity timer locks vault and resets on activity', () async {
      final autoLockService = AutoLockService(
        secureStorage: secureStorage,
        onLockVault: () => lockCalls++,
        getUserId: () => 'user-1',
        customInactivityDuration: const Duration(milliseconds: 100),
      );

      autoLockService.resetInactivityTimer();
      expect(autoLockService.isTimerActive, isTrue);

      // User interacts at 50ms -> resets timer
      await Future.delayed(const Duration(milliseconds: 50));
      autoLockService.resetInactivityTimer();
      expect(lockCalls, equals(0));

      // Wait for complete expiry (120ms > 100ms)
      await Future.delayed(const Duration(milliseconds: 120));
      expect(lockCalls, equals(1));

      autoLockService.dispose();
    });
  });
}
