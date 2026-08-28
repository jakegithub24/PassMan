import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:apps/services/crypto_service.dart';

void main() {
  late CryptoService cryptoService;

  setUp(() {
    cryptoService = CryptoService(pbkdf2Iterations: 1000); // Faster iteration count for unit test suite
  });

  group('CryptoService Tests', () {
    test('generateSalt produces valid base64 16-byte strings', () {
      final salt1 = cryptoService.generateSalt(16);
      final salt2 = cryptoService.generateSalt(16);

      expect(salt1, isNotEmpty);
      expect(salt2, isNotEmpty);
      expect(salt1, isNot(equals(salt2)));

      final decoded = base64Decode(salt1);
      expect(decoded.length, equals(16));
    });

    test('deriveMasterKey generates deterministic 32-byte (256-bit) keys', () async {
      const password = 'MyMasterPassword123!@#';
      final salt = cryptoService.generateSalt();

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

      expect(encrypted['ciphertext'], isNotEmpty);
      expect(encrypted['iv'], isNotEmpty);
      expect(encrypted['tag'], isNotEmpty);

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
