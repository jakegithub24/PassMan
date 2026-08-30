import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'secure_storage_service.dart';

/// Biometric and Device-Level Authentication Service (MVP.md §5, §7 / Task 10.1)
class BiometricService {
  final LocalAuthentication _localAuth;
  final SecureStorageService secureStorage;

  BiometricService({
    LocalAuthentication? localAuth,
    required this.secureStorage,
  }) : _localAuth = localAuth ?? LocalAuthentication();

  /// Checks whether hardware supports biometric/device passcode authentication
  Future<bool> canAuthenticate() async {
    try {
      final isSupported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      return isSupported || canCheck;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print('BiometricService canAuthenticate error: $e');
      }
      return false;
    }
  }

  /// Lists available biometric sensor types (e.g. fingerprint, face)
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print('BiometricService getAvailableBiometrics error: $e');
      }
      return [];
    }
  }

  /// Prompts device-level biometric / PIN prompt
  Future<bool> authenticate({
    String localizedReason = 'Authenticate to unlock your PassMan vault',
    bool biometricOnly = false,
    bool persistAcrossBackgrounding = true,
  }) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: localizedReason,
        biometricOnly: biometricOnly,
        persistAcrossBackgrounding: persistAcrossBackgrounding,
      );
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print('BiometricService authenticate error: $e');
      }
      return false;
    }
  }

  /// Checks if the user has enabled biometric unlock
  Future<bool> isBiometricUnlockEnabled({String? userId}) async {
    return await secureStorage.isBiometricEnabled(userId: userId);
  }

  /// Enables biometric unlock and saves session key in secure storage
  Future<void> enableBiometricUnlock(List<int> sessionKey, {String? userId}) async {
    await secureStorage.saveBiometricSessionKey(sessionKey, userId: userId);
    await secureStorage.saveBiometricEnabled(true, userId: userId);
  }

  /// Disables biometric unlock and clears saved session key
  Future<void> disableBiometricUnlock({String? userId}) async {
    await secureStorage.clearBiometricSessionKey(userId: userId);
    await secureStorage.saveBiometricEnabled(false, userId: userId);
  }

  /// Unlocks vault via biometrics and returns recovered session key if authenticated
  Future<List<int>?> unlockWithBiometrics({String? userId}) async {
    final enabled = await isBiometricUnlockEnabled(userId: userId);
    if (!enabled) return null;

    final authenticated = await authenticate();
    if (!authenticated) return null;

    return await secureStorage.getBiometricSessionKey(userId: userId);
  }
}
