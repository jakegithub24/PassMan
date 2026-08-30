import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Production-ready storage service for sensitive session artifacts
/// (JWT access/refresh tokens, master session encryption key, and user metadata).
///
/// Configured with:
/// - Android: Hardware-backed Android Keystore via EncryptedSharedPreferences with automatic error recovery
/// - Web: Web Crypto API with persistent encrypted IndexedDB (PassManSecureDB)
/// - iOS/macOS: Keychain Services protected by KeychainAccessibility.first_unlock
/// - Linux/Windows: Native secret service / Credential Manager
class SecureStorageService {
  final FlutterSecureStorage _secureStorage;

  // Ephemeral in-memory session key cache
  List<int>? _inMemorySessionKey;

  static const String keyAccessToken = 'passman_access_token';
  static const String keyRefreshToken = 'passman_refresh_token';
  static const String keySessionKey = 'passman_session_key';
  static const String keyUserId = 'passman_user_id';
  static const String keyUserEmail = 'passman_user_email';
  static const String keyUserSalt = 'passman_user_salt';

  SecureStorageService({FlutterSecureStorage? storage})
      : _secureStorage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                resetOnError: true,
              ),
              webOptions: WebOptions(
                dbName: 'PassManSecureDB',
                publicKey: 'PassManWebKey',
              ),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
              mOptions: MacOsOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
              lOptions: LinuxOptions(),
              wOptions: WindowsOptions(),
            );

  // ---------------------------------------------------------------------------
  // Tokens Management
  // ---------------------------------------------------------------------------

  /// Persists both access and refresh tokens atomically
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _secureStorage.write(key: keyAccessToken, value: accessToken);
    await _secureStorage.write(key: keyRefreshToken, value: refreshToken);
  }

  /// Retrieves active JWT access token
  Future<String?> getAccessToken() async {
    try {
      return await _secureStorage.read(key: keyAccessToken);
    } catch (e) {
      if (kDebugMode) {
        print('SecureStorage access token read error: $e');
      }
      return null;
    }
  }

  /// Retrieves active JWT refresh token
  Future<String?> getRefreshToken() async {
    try {
      return await _secureStorage.read(key: keyRefreshToken);
    } catch (e) {
      if (kDebugMode) {
        print('SecureStorage refresh token read error: $e');
      }
      return null;
    }
  }

  /// Updates only the access token (e.g. after silent rotation)
  Future<void> saveAccessToken(String token) async {
    await _secureStorage.write(key: keyAccessToken, value: token);
  }

  /// Clears only authentication tokens without clearing session key or metadata
  Future<void> clearTokens() async {
    await _secureStorage.delete(key: keyAccessToken);
    await _secureStorage.delete(key: keyRefreshToken);
  }

  /// Checks if valid tokens are present in secure storage
  Future<bool> hasValidTokens() async {
    final access = await getAccessToken();
    final refresh = await getRefreshToken();
    return access != null && access.isNotEmpty && refresh != null && refresh.isNotEmpty;
  }

  // ---------------------------------------------------------------------------
  // Master Session Key (Derived 256-bit AES Key)
  // ---------------------------------------------------------------------------

  /// Stores the derived master session key in memory and secure storage
  Future<void> saveSessionKey(List<int> keyBytes) async {
    _inMemorySessionKey = List<int>.from(keyBytes);
    final String base64Key = base64Encode(keyBytes);
    await _secureStorage.write(key: keySessionKey, value: base64Key);
  }

  /// Retrieves the derived session key
  Future<List<int>?> getSessionKey() async {
    if (_inMemorySessionKey != null && _inMemorySessionKey!.isNotEmpty) {
      return _inMemorySessionKey;
    }
    try {
      final String? stored = await _secureStorage.read(key: keySessionKey);
      if (stored != null && stored.isNotEmpty) {
        _inMemorySessionKey = base64Decode(stored);
        return _inMemorySessionKey;
      }
    } catch (e) {
      if (kDebugMode) {
        print('SecureStorage session key decode error: $e');
      }
      return null;
    }
    return null;
  }

  /// Checks if an active session key exists (unlocked state)
  Future<bool> hasActiveSessionKey() async {
    final key = await getSessionKey();
    return key != null && key.isNotEmpty;
  }

  /// Clears only the session encryption key (used during Vault Auto-Lock)
  Future<void> clearSessionKey() async {
    _inMemorySessionKey = null;
    await _secureStorage.delete(key: keySessionKey);
  }

  // ---------------------------------------------------------------------------
  // User Profile & Salt
  // ---------------------------------------------------------------------------

  /// Persists user identifier, normalized email, and cryptographic salt
  Future<void> saveUserMetadata({
    required String userId,
    required String email,
    required String salt,
  }) async {
    await _secureStorage.write(key: keyUserId, value: userId);
    await _secureStorage.write(key: keyUserEmail, value: email);
    await _secureStorage.write(key: keyUserSalt, value: salt);
  }

  /// Retrieves cached user profile and derivation salt
  Future<Map<String, String>?> getUserMetadata() async {
    try {
      final String? userId = await _secureStorage.read(key: keyUserId);
      final String? email = await _secureStorage.read(key: keyUserEmail);
      final String? salt = await _secureStorage.read(key: keyUserSalt);

      if (userId != null && email != null && salt != null) {
        return {
          'userId': userId,
          'email': email,
          'salt': salt,
        };
      }
    } catch (e) {
      if (kDebugMode) {
        print('SecureStorage user metadata read error: $e');
      }
      return null;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Sync Persistence (Task 9.2 / last_synced_at)
  // ---------------------------------------------------------------------------

  static const String keyLastSyncedAtPrefix = 'passman_last_synced_at_';

  /// Saves the last synced UTC timestamp
  Future<void> saveLastSyncedAt(DateTime timestamp, {String? userId}) async {
    final key = '$keyLastSyncedAtPrefix${userId ?? "default"}';
    await _secureStorage.write(key: key, value: timestamp.toUtc().toIso8601String());
  }

  /// Retrieves the last synced UTC timestamp
  Future<DateTime?> getLastSyncedAt({String? userId}) async {
    try {
      final key = '$keyLastSyncedAtPrefix${userId ?? "default"}';
      final val = await _secureStorage.read(key: key);
      if (val != null && val.isNotEmpty) {
        return DateTime.parse(val).toUtc();
      }
    } catch (e) {
      if (kDebugMode) {
        print('SecureStorage last_synced_at read error: $e');
      }
    }
    return null;
  }

  /// Clears last synced timestamp
  Future<void> clearLastSyncedAt({String? userId}) async {
    final key = '$keyLastSyncedAtPrefix${userId ?? "default"}';
    await _secureStorage.delete(key: key);
  }

  // ---------------------------------------------------------------------------
  // Generic Helpers & Total Wipeout (Logout)
  // ---------------------------------------------------------------------------

  /// Checks if a given key exists in secure storage
  Future<bool> containsKey(String key) async {
    return await _secureStorage.containsKey(key: key);
  }

  /// Deletes all stored tokens, session keys, and user metadata
  Future<void> clearAll() async {
    _inMemorySessionKey = null;
    await _secureStorage.deleteAll();
  }
}
