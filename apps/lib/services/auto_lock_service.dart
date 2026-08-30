import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'secure_storage_service.dart';

/// Service managing user-selectable auto-lock timeout (5-30m) and background lock (Task 10.2 / MVP.md §7)
class AutoLockService with WidgetsBindingObserver {
  final SecureStorageService secureStorage;
  final VoidCallback onLockVault;
  final String? Function() getUserId;

  int _timeoutMinutes = 5;
  DateTime? _backgroundedAt;
  Timer? _inactivityTimer;
  bool _isListening = false;
  Duration? customInactivityDuration; // Used for fast unit testing

  AutoLockService({
    required this.secureStorage,
    required this.onLockVault,
    required this.getUserId,
    int initialTimeoutMinutes = 5,
    this.customInactivityDuration,
  }) : _timeoutMinutes = initialTimeoutMinutes;

  int get timeoutMinutes => _timeoutMinutes;
  DateTime? get backgroundedAt => _backgroundedAt;
  bool get isTimerActive => _inactivityTimer?.isActive ?? false;

  /// Initializes lifecycle listener and loads user preference
  Future<void> init() async {
    final userId = getUserId();
    _timeoutMinutes = await secureStorage.getAutoLockTimeoutMinutes(userId: userId);

    if (!_isListening) {
      WidgetsBinding.instance.addObserver(this);
      _isListening = true;
    }

    resetInactivityTimer();
  }

  /// Sets and persists new auto-lock duration in minutes
  Future<void> setTimeoutMinutes(int minutes) async {
    _timeoutMinutes = minutes;
    final userId = getUserId();
    await secureStorage.saveAutoLockTimeoutMinutes(minutes, userId: userId);
    resetInactivityTimer();
  }

  /// Override duration for unit testing
  @visibleForTesting
  void setCustomInactivityDuration(Duration duration) {
    customInactivityDuration = duration;
    resetInactivityTimer();
  }

  /// Resets foreground inactivity countdown
  void resetInactivityTimer() {
    _inactivityTimer?.cancel();

    if (_timeoutMinutes <= 0 && customInactivityDuration == null) {
      return;
    }

    final duration = customInactivityDuration ?? Duration(minutes: _timeoutMinutes);
    _inactivityTimer = Timer(duration, () {
      if (kDebugMode) {
        print('AutoLockService: Inactivity timer expired after $duration. Locking vault.');
      }
      onLockVault();
    });
  }

  /// AppLifecycle observer: locks vault on background timeout or immediate configuration
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _backgroundedAt = DateTime.now();
        _inactivityTimer?.cancel();

        // If timeout is 0 (Immediate background lock) -> lock immediately
        if (_timeoutMinutes == 0) {
          if (kDebugMode) {
            print('AutoLockService: Immediate background lock triggered.');
          }
          onLockVault();
        }
        break;

      case AppLifecycleState.resumed:
        if (_backgroundedAt != null) {
          final elapsed = DateTime.now().difference(_backgroundedAt!);
          final targetDuration = customInactivityDuration ?? Duration(minutes: _timeoutMinutes);

          if (elapsed >= targetDuration) {
            if (kDebugMode) {
              print('AutoLockService: Background duration ($elapsed) exceeded timeout ($targetDuration). Locking vault.');
            }
            onLockVault();
          } else {
            // Still within timeout window: resume foreground inactivity timer
            resetInactivityTimer();
          }
          _backgroundedAt = null;
        } else {
          resetInactivityTimer();
        }
        break;

      case AppLifecycleState.detached:
        _inactivityTimer?.cancel();
        break;
    }
  }

  /// Cleans up observers and timers
  void dispose() {
    _inactivityTimer?.cancel();
    if (_isListening) {
      WidgetsBinding.instance.removeObserver(this);
      _isListening = false;
    }
  }
}
