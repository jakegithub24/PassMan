import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// Cryptographic service providing client-side zero-knowledge encryption (AES-256-GCM),
/// PBKDF2-HMAC-SHA256 key derivation, and cryptographically secure salt generation.
class CryptoService {
  static const int defaultPbkdf2Iterations = 100000;
  static const int keyLengthBits = 256;
  static const int keyLengthBytes = 32;
  static const int gcmNonceLengthBytes = 12; // 96-bit standard IV per NIST SP 800-38D
  static const int gcmTagLengthBytes = 16; // 128-bit authentication tag

  final int iterations;
  final AesGcm _aesGcm = AesGcm.with256bits();
  final Pbkdf2 _pbkdf2;

  CryptoService({int? pbkdf2Iterations})
      : iterations = pbkdf2Iterations ?? defaultPbkdf2Iterations,
        _pbkdf2 = Pbkdf2(
          macAlgorithm: Hmac.sha256(),
          iterations: pbkdf2Iterations ?? defaultPbkdf2Iterations,
          bits: keyLengthBits,
        );

  /// Generates a cryptographically secure random salt encoded in Base64.
  String generateSalt([int length = 16]) {
    final Uint8List saltBytes = generateSaltBytes(length);
    return base64Encode(saltBytes);
  }

  /// Generates raw random salt bytes of the specified length.
  Uint8List generateSaltBytes([int length = 16]) {
    final Random random = Random.secure();
    final Uint8List saltBytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      saltBytes[i] = random.nextInt(256);
    }
    return saltBytes;
  }

  /// Generates a random 12-byte (96-bit) Initialization Vector (Nonce) for AES-GCM.
  Uint8List generateNonce([int length = gcmNonceLengthBytes]) {
    final Random random = Random.secure();
    final Uint8List nonce = Uint8List(length);
    for (int i = 0; i < length; i++) {
      nonce[i] = random.nextInt(256);
    }
    return nonce;
  }

  /// Derives a deterministic 256-bit symmetric encryption key from a master password
  /// and Base64-encoded salt using PBKDF2-HMAC-SHA256.
  Future<List<int>> deriveMasterKey({
    required String masterPassword,
    required String saltBase64,
  }) async {
    final List<int> saltBytes = base64Decode(saltBase64);
    return await deriveMasterKeyBytes(
      masterPassword: masterPassword,
      saltBytes: saltBytes,
    );
  }

  /// Derives a deterministic 256-bit symmetric encryption key from a master password
  /// and raw salt bytes using PBKDF2-HMAC-SHA256.
  Future<List<int>> deriveMasterKeyBytes({
    required String masterPassword,
    required List<int> saltBytes,
  }) async {
    final SecretKey secretKey = await _pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(masterPassword)),
      nonce: saltBytes,
    );
    return await secretKey.extractBytes();
  }

  /// Derives the master session key and encodes it directly as a Base64 string.
  Future<String> deriveSessionKeyBase64({
    required String masterPassword,
    required String saltBase64,
  }) async {
    final keyBytes = await deriveMasterKey(
      masterPassword: masterPassword,
      saltBase64: saltBase64,
    );
    return base64Encode(keyBytes);
  }

  /// Compares two byte lists in constant time to prevent side-channel timing attacks.
  bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  /// Wipes a sensitive in-memory byte buffer by overwriting all elements with zeroes.
  void wipeBuffer(List<int> buffer) {
    for (int i = 0; i < buffer.length; i++) {
      buffer[i] = 0;
    }
  }

  /// Encrypts plaintext string using AES-256-GCM.
  /// Validates 256-bit key length and returns a Map containing Base64-encoded {ciphertext, iv, tag}.
  Future<Map<String, String>> encryptAesGcm({
    required String plaintext,
    required List<int> keyBytes,
    List<int>? customNonce,
  }) async {
    if (keyBytes.length != keyLengthBytes) {
      throw ArgumentError('AES-256 requires exactly 32 key bytes (got ${keyBytes.length})');
    }

    final SecretKey secretKey = SecretKey(keyBytes);
    final SecretBox secretBox = await _aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: secretKey,
      nonce: customNonce,
    );

    return {
      'ciphertext': base64Encode(secretBox.cipherText),
      'iv': base64Encode(secretBox.nonce),
      'tag': base64Encode(secretBox.mac.bytes),
    };
  }

  /// Encrypts raw plaintext byte buffer using AES-256-GCM.
  Future<Map<String, String>> encryptBytesAesGcm({
    required List<int> plaintextBytes,
    required List<int> keyBytes,
    List<int>? customNonce,
  }) async {
    if (keyBytes.length != keyLengthBytes) {
      throw ArgumentError('AES-256 requires exactly 32 key bytes (got ${keyBytes.length})');
    }

    final SecretKey secretKey = SecretKey(keyBytes);
    final SecretBox secretBox = await _aesGcm.encrypt(
      plaintextBytes,
      secretKey: secretKey,
      nonce: customNonce,
    );

    return {
      'ciphertext': base64Encode(secretBox.cipherText),
      'iv': base64Encode(secretBox.nonce),
      'tag': base64Encode(secretBox.mac.bytes),
    };
  }

  /// Decrypts AES-256-GCM ciphertext using Base64 {ciphertext, iv, tag} and key bytes.
  Future<String> decryptAesGcm({
    required String ciphertextBase64,
    required String ivBase64,
    required String tagBase64,
    required List<int> keyBytes,
  }) async {
    final clearTextBytes = await decryptBytesAesGcm(
      ciphertextBase64: ciphertextBase64,
      ivBase64: ivBase64,
      tagBase64: tagBase64,
      keyBytes: keyBytes,
    );
    return utf8.decode(clearTextBytes);
  }

  /// Decrypts AES-256-GCM ciphertext map {ciphertext, iv, tag} directly.
  Future<String> decryptMapAesGcm({
    required Map<String, String> payload,
    required List<int> keyBytes,
  }) async {
    final ciphertext = payload['ciphertext'];
    final iv = payload['iv'];
    final tag = payload['tag'];

    if (ciphertext == null || iv == null || tag == null) {
      throw const FormatException('Missing required ciphertext, iv, or tag in payload');
    }

    return await decryptAesGcm(
      ciphertextBase64: ciphertext,
      ivBase64: iv,
      tagBase64: tag,
      keyBytes: keyBytes,
    );
  }

  /// Decrypts AES-256-GCM payload directly to raw plaintext bytes.
  Future<List<int>> decryptBytesAesGcm({
    required String ciphertextBase64,
    required String ivBase64,
    required String tagBase64,
    required List<int> keyBytes,
  }) async {
    if (keyBytes.length != keyLengthBytes) {
      throw ArgumentError('AES-256 requires exactly 32 key bytes (got ${keyBytes.length})');
    }

    final SecretKey secretKey = SecretKey(keyBytes);
    final SecretBox secretBox = SecretBox(
      base64Decode(ciphertextBase64),
      nonce: base64Decode(ivBase64),
      mac: Mac(base64Decode(tagBase64)),
    );

    return await _aesGcm.decrypt(
      secretBox,
      secretKey: secretKey,
    );
  }

  /// Serializes AES-256-GCM encryption result to a JSON string envelope for backend persistence.
  Future<String> encryptVaultPayload({
    required String plaintext,
    required List<int> keyBytes,
  }) async {
    final Map<String, String> envelope = await encryptAesGcm(
      plaintext: plaintext,
      keyBytes: keyBytes,
    );
    return jsonEncode(envelope);
  }

  /// Deserializes a JSON string envelope {ciphertext, iv, tag} and decrypts to plaintext string.
  Future<String> decryptVaultPayload({
    required String jsonPayload,
    required List<int> keyBytes,
  }) async {
    final dynamic decoded = jsonDecode(jsonPayload);
    if (decoded is! Map) {
      throw const FormatException('Invalid JSON payload format for vault entry');
    }

    final String? ciphertext = decoded['ciphertext'] as String?;
    final String? iv = decoded['iv'] as String?;
    final String? tag = decoded['tag'] as String?;

    if (ciphertext == null || iv == null || tag == null) {
      throw const FormatException('Missing required ciphertext, iv, or tag in envelope');
    }

    return await decryptAesGcm(
      ciphertextBase64: ciphertext,
      ivBase64: iv,
      tagBase64: tag,
      keyBytes: keyBytes,
    );
  }
}
