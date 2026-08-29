import 'dart:convert';
import 'package:apps/services/crypto_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CryptoService cryptoService;

  setUp(() {
    cryptoService = CryptoService(pbkdf2Iterations: 1000); // 1000 iterations for fast test suite
  });

  group('CryptoService Tests (Task 6.1 Key Derivation & Security)', () {
    test('generateSalt produces valid Base64 encoded random salts of correct length', () {
      final salt16 = cryptoService.generateSalt(16);
      final salt32 = cryptoService.generateSalt(32);

      expect(salt16, isNotEmpty);
      expect(salt32, isNotEmpty);
      expect(salt16, isNot(equals(cryptoService.generateSalt(16))));

      final decoded16 = base64Decode(salt16);
      final decoded32 = base64Decode(salt32);
      expect(decoded16.length, equals(16));
      expect(decoded32.length, equals(32));
    });

    test('generateSaltBytes produces raw byte lists with proper entropy', () {
      final bytes1 = cryptoService.generateSaltBytes(16);
      final bytes2 = cryptoService.generateSaltBytes(16);

      expect(bytes1.length, equals(16));
      expect(bytes2.length, equals(16));
      expect(bytes1, isNot(equals(bytes2)));
    });

    test('deriveMasterKey generates deterministic 32-byte (256-bit) keys', () async {
      const password = 'MyMasterPassword123!@#';
      final salt = cryptoService.generateSalt(16);

      final key1 = await cryptoService.deriveMasterKey(
        masterPassword: password,
        saltBase64: salt,
      );
      final key2 = await cryptoService.deriveMasterKey(
        masterPassword: password,
        saltBase64: salt,
      );

      expect(key1.length, equals(32));
      expect(key1, equals(key2));

      final keyDifferentPassword = await cryptoService.deriveMasterKey(
        masterPassword: 'OtherPassword',
        saltBase64: salt,
      );
      expect(key1, isNot(equals(keyDifferentPassword)));

      final keyDifferentSalt = await cryptoService.deriveMasterKey(
        masterPassword: password,
        saltBase64: cryptoService.generateSalt(16),
      );
      expect(key1, isNot(equals(keyDifferentSalt)));
    });

    test('deriveMasterKeyBytes matches deriveMasterKey with Base64 decoded salt', () async {
      const password = 'SecurePassword789';
      final saltBase64 = cryptoService.generateSalt(16);
      final saltBytes = base64Decode(saltBase64);

      final keyFromBase64 = await cryptoService.deriveMasterKey(
        masterPassword: password,
        saltBase64: saltBase64,
      );

      final keyFromBytes = await cryptoService.deriveMasterKeyBytes(
        masterPassword: password,
        saltBytes: saltBytes,
      );

      expect(keyFromBase64, equals(keyFromBytes));
    });

    test('deriveSessionKeyBase64 returns valid Base64 string of derived key', () async {
      const password = 'MasterSessionPassword';
      final salt = cryptoService.generateSalt(16);

      final base64Key = await cryptoService.deriveSessionKeyBase64(
        masterPassword: password,
        saltBase64: salt,
      );

      final decoded = base64Decode(base64Key);
      expect(decoded.length, equals(32));

      final directKey = await cryptoService.deriveMasterKey(
        masterPassword: password,
        saltBase64: salt,
      );
      expect(decoded, equals(directKey));
    });

    test('constantTimeEquals correctly evaluates byte buffers', () {
      final a = [1, 2, 3, 4, 5];
      final b = [1, 2, 3, 4, 5];
      final c = [1, 2, 3, 4, 6];
      final d = [1, 2, 3, 4];

      expect(cryptoService.constantTimeEquals(a, b), isTrue);
      expect(cryptoService.constantTimeEquals(a, c), isFalse);
      expect(cryptoService.constantTimeEquals(a, d), isFalse);
    });

    test('wipeBuffer securely zeroes all elements in the buffer', () {
      final buffer = [10, 20, 30, 40, 50];
      cryptoService.wipeBuffer(buffer);

      expect(buffer, equals([0, 0, 0, 0, 0]));
    });
  });

  group('CryptoService AES-256-GCM Encryption Tests (Task 6.2)', () {
    test('encryptAesGcm generates valid {ciphertext, iv, tag} envelope with 12-byte IV and 16-byte tag', () async {
      const plaintext = 'SuperSecretVaultItemPayload';
      final key = await cryptoService.deriveMasterKey(
        masterPassword: 'MasterPassword123!',
        saltBase64: cryptoService.generateSalt(),
      );

      final encrypted = await cryptoService.encryptAesGcm(
        plaintext: plaintext,
        keyBytes: key,
      );

      expect(encrypted.containsKey('ciphertext'), isTrue);
      expect(encrypted.containsKey('iv'), isTrue);
      expect(encrypted.containsKey('tag'), isTrue);

      final ivBytes = base64Decode(encrypted['iv']!);
      final tagBytes = base64Decode(encrypted['tag']!);
      final cipherBytes = base64Decode(encrypted['ciphertext']!);

      expect(ivBytes.length, equals(12)); // 96-bit GCM IV
      expect(tagBytes.length, equals(16)); // 128-bit authentication tag
      expect(cipherBytes.isNotEmpty, isTrue);
    });

    test('encryptAesGcm produces unique IV and ciphertext for identical plaintexts (IND-CPA security)', () async {
      const plaintext = 'ConsistentPasswordValue';
      final key = await cryptoService.deriveMasterKey(
        masterPassword: 'MasterPassword123!',
        saltBase64: cryptoService.generateSalt(),
      );

      final enc1 = await cryptoService.encryptAesGcm(plaintext: plaintext, keyBytes: key);
      final enc2 = await cryptoService.encryptAesGcm(plaintext: plaintext, keyBytes: key);

      expect(enc1['iv'], isNot(equals(enc2['iv'])));
      expect(enc1['ciphertext'], isNot(equals(enc2['ciphertext'])));
    });

    test('encryptAesGcm with custom nonce uses specified nonce', () async {
      const plaintext = 'CustomNoncePayload';
      final key = await cryptoService.deriveMasterKey(
        masterPassword: 'MasterPassword123!',
        saltBase64: cryptoService.generateSalt(),
      );
      final customNonce = cryptoService.generateNonce(12);

      final encrypted = await cryptoService.encryptAesGcm(
        plaintext: plaintext,
        keyBytes: key,
        customNonce: customNonce,
      );

      expect(base64Decode(encrypted['iv']!), equals(customNonce));
    });

    test('encryptBytesAesGcm encrypts raw byte payloads', () async {
      final bytes = utf8.encode('RawByteSecret');
      final key = await cryptoService.deriveMasterKey(
        masterPassword: 'MasterPassword123!',
        saltBase64: cryptoService.generateSalt(),
      );

      final encrypted = await cryptoService.encryptBytesAesGcm(
        plaintextBytes: bytes,
        keyBytes: key,
      );

      expect(encrypted['ciphertext'], isNotEmpty);
      expect(base64Decode(encrypted['iv']!).length, equals(12));
    });

    test('encryptAesGcm throws ArgumentError if key length is not exactly 32 bytes', () async {
      final invalidKey = [1, 2, 3, 4, 5]; // 5 bytes instead of 32

      expect(
        () async => await cryptoService.encryptAesGcm(
          plaintext: 'test',
          keyBytes: invalidKey,
        ),
        throwsArgumentError,
      );
    });

    test('AES-256-GCM encryption and decryption round-trip', () async {
      const secretMessage = '{"title":"GitHub","username":"user@example.com","password":"SecretPassword123"}';
      final key = await cryptoService.deriveMasterKey(
        masterPassword: 'MasterPassword123!',
        saltBase64: cryptoService.generateSalt(),
      );

      final encrypted = await cryptoService.encryptAesGcm(
        plaintext: secretMessage,
        keyBytes: key,
      );

      final decrypted = await cryptoService.decryptAesGcm(
        ciphertextBase64: encrypted['ciphertext']!,
        ivBase64: encrypted['iv']!,
        tagBase64: encrypted['tag']!,
        keyBytes: key,
      );

      expect(decrypted, equals(secretMessage));
    });

    test('encryptVaultPayload and decryptVaultPayload JSON envelope round-trip', () async {
      const secretJson = '{"note":"Bank PIN 4321"}';
      final key = await cryptoService.deriveMasterKey(
        masterPassword: 'MasterPassword123!',
        saltBase64: cryptoService.generateSalt(),
      );

      final vaultJson = await cryptoService.encryptVaultPayload(
        plaintext: secretJson,
        keyBytes: key,
      );

      final decodedMap = jsonDecode(vaultJson) as Map<String, dynamic>;
      expect(decodedMap.containsKey('ciphertext'), isTrue);
      expect(decodedMap.containsKey('iv'), isTrue);
      expect(decodedMap.containsKey('tag'), isTrue);

      final restored = await cryptoService.decryptVaultPayload(
        jsonPayload: vaultJson,
        keyBytes: key,
      );

      expect(restored, equals(secretJson));
    });

    test('Decryption with wrong key fails', () async {
      const message = 'Classified Information';
      final key1 = await cryptoService.deriveMasterKey(
        masterPassword: 'PasswordOne',
        saltBase64: cryptoService.generateSalt(),
      );
      final key2 = await cryptoService.deriveMasterKey(
        masterPassword: 'PasswordTwo',
        saltBase64: cryptoService.generateSalt(),
      );

      final encrypted = await cryptoService.encryptAesGcm(
        plaintext: message,
        keyBytes: key1,
      );

      expect(
        () async => await cryptoService.decryptAesGcm(
          ciphertextBase64: encrypted['ciphertext']!,
          ivBase64: encrypted['iv']!,
          tagBase64: encrypted['tag']!,
          keyBytes: key2,
        ),
        throwsA(anything),
      );
    });
  });
}
