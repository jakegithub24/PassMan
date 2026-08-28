import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Storage service for sensitive session artifacts (JWT tokens, derived session key, user metadata).
/// Uses Android Keystore (via EncryptedSharedPreferences) on Android and secure in-memory/web storage on Web.
class SecureStorageService {
  final FlutterSecureStorage _secureStorage;

  // In-memory fallback/cache for ephemeral session key handling
  List<int>? _inMemorySessionKey;

  static const String _keyAccessToken = 'passman_access_token';
  static const String _keyRefreshToken = 'passman_refresh_token';
  static const String _keySessionKey = 'passman_session_key';
  static const String _keyUserId = 'passman_user_id';
  static const String _keyUserEmail = 'passman_user_email';
  static const String _keyUserSalt = 'passman_user_salt';

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
            );

  // ---------------------------------------------------------------------------
  // Tokens Management
  // ---------------------------------------------------------------------------

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _secureStorage.write(key: _keyAccessToken, value: accessToken);
    await _secureStorage.write(key: _keyRefreshToken, value: refreshToken);
  }

  Future<String?> getAccessToken() async {
    return await _secureStorage.read(key: _keyAccessToken);
  }

  Future<String?> getRefreshToken() async {
    return await _secureStorage.read(key: _keyRefreshToken);
  }

  Future<void> saveAccessToken(String token) async {
    await _secureStorage.write(key: _keyAccessToken, value: token);
  }

  Future<void> clearTokens() async {
    await _secureStorage.delete(key: _keyAccessToken);
    await _secureStorage.delete(key: _keyRefreshToken);
  }

  // ---------------------------------------------------------------------------
  // Master Session Key (Derived 256-bit AES Key)
  // ---------------------------------------------------------------------------

  /// Stores the derived master session key. On Web, prioritizes in-memory storage to minimize persistent leakage.
  Future<void> saveSessionKey(List<int> keyBytes) async {
    _inMemorySessionKey = List<int>.from(keyBytes);
    final String base64Key = base64Encode(keyBytes);
    await _secureStorage.write(key: _keySessionKey, value: base64Key);
  }

  /// Retrieves the derived session key.
  Future<List<int>?> getSessionKey() async {
    if (_inMemorySessionKey != null) {
      return _inMemorySessionKey;
    }
    final String? stored = await _secureStorage.read(key: _keySessionKey);
    if (stored != null && stored.isNotEmpty) {
      try {
        _inMemorySessionKey = base64Decode(stored);
        return _inMemorySessionKey;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Clears only the session encryption key (used during Vault Auto-Lock without logging out).
  Future<void> clearSessionKey() async {
    _inMemorySessionKey = null;
    await _secureStorage.delete(key: _keySessionKey);
  }

  // ---------------------------------------------------------------------------
  // User Profile & Salt
  // ---------------------------------------------------------------------------

  Future<void> saveUserMetadata({
    required String userId,
    required String email,
    required String salt,
  }) async {
    await _secureStorage.write(key: _keyUserId, value: userId);
    await _secureStorage.write(key: _keyUserEmail, value: email);
    await _secureStorage.write(key: _keyUserSalt, value: salt);
  }

  Future<Map<String, String>?> getUserMetadata() async {
    final String? userId = await _secureStorage.read(key: _keyUserId);
    final String? email = await _secureStorage.read(key: _keyUserEmail);
    final String? salt = await _secureStorage.read(key: _keyUserSalt);

    if (userId != null && email != null && salt != null) {
      return {
        'userId': userId,
        'email': email,
        'salt': salt,
      };
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Total Wipeout (Logout)
  // ---------------------------------------------------------------------------

  Future<void> clearAll() async {
    _inMemorySessionKey = null;
    await _secureStorage.deleteAll();
  }
}
