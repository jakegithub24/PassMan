import 'dart:convert';
import 'package:apps/models/vault_item.dart';
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
  });

  group('CryptoService AES-256-GCM Decryption Tests (Task 6.3)', () {
    test('decryptAesGcm and decryptMapAesGcm successfully restore original plaintext', () async {
      const originalText = 'Highly confidential password & private key 9876';
      final key = await cryptoService.deriveMasterKey(
        masterPassword: 'MySecretMasterKey!',
        saltBase64: cryptoService.generateSalt(),
      );

      final encryptedMap = await cryptoService.encryptAesGcm(
        plaintext: originalText,
        keyBytes: key,
      );

      final decryptedString = await cryptoService.decryptAesGcm(
        ciphertextBase64: encryptedMap['ciphertext']!,
        ivBase64: encryptedMap['iv']!,
        tagBase64: encryptedMap['tag']!,
        keyBytes: key,
      );
      expect(decryptedString, equals(originalText));

      final decryptedFromMap = await cryptoService.decryptMapAesGcm(
        payload: encryptedMap,
        keyBytes: key,
      );
      expect(decryptedFromMap, equals(originalText));
    });

    test('decryptBytesAesGcm restores raw byte payload', () async {
      final rawData = [0, 255, 128, 64, 32, 16, 8, 4, 2, 1];
      final key = await cryptoService.deriveMasterKey(
        masterPassword: 'KeyForRawBytes!',
        saltBase64: cryptoService.generateSalt(),
      );

      final encrypted = await cryptoService.encryptBytesAesGcm(
        plaintextBytes: rawData,
        keyBytes: key,
      );

      final decryptedBytes = await cryptoService.decryptBytesAesGcm(
        ciphertextBase64: encrypted['ciphertext']!,
        ivBase64: encrypted['iv']!,
        tagBase64: encrypted['tag']!,
        keyBytes: key,
      );

      expect(decryptedBytes, equals(rawData));
    });

    test('decryptAesGcm throws ArgumentError if key is not 32 bytes', () async {
      expect(
        () async => await cryptoService.decryptAesGcm(
          ciphertextBase64: 'AAAA',
          ivBase64: 'AAAA',
          tagBase64: 'AAAA',
          keyBytes: [1, 2, 3],
        ),
        throwsArgumentError,
      );
    });

    test('decryptAesGcm throws on tampered ciphertext (tamper detection)', () async {
      final key = await cryptoService.deriveMasterKey(
        masterPassword: 'MasterPassword123!',
        saltBase64: cryptoService.generateSalt(),
      );

      final encrypted = await cryptoService.encryptAesGcm(
        plaintext: 'Valid Plaintext',
        keyBytes: key,
      );

      // Tamper with ciphertext bytes
      final cipherBytes = base64Decode(encrypted['ciphertext']!);
      cipherBytes[0] ^= 0xFF;
      final tamperedCiphertext = base64Encode(cipherBytes);

      expect(
        () async => await cryptoService.decryptAesGcm(
          ciphertextBase64: tamperedCiphertext,
          ivBase64: encrypted['iv']!,
          tagBase64: encrypted['tag']!,
          keyBytes: key,
        ),
        throwsA(anything),
      );
    });

    test('decryptAesGcm throws on tampered authentication tag (authentication failure)', () async {
      final key = await cryptoService.deriveMasterKey(
        masterPassword: 'MasterPassword123!',
        saltBase64: cryptoService.generateSalt(),
      );

      final encrypted = await cryptoService.encryptAesGcm(
        plaintext: 'Valid Plaintext',
        keyBytes: key,
      );

      // Tamper with tag bytes
      final tagBytes = base64Decode(encrypted['tag']!);
      tagBytes[0] ^= 0xFF;
      final tamperedTag = base64Encode(tagBytes);

      expect(
        () async => await cryptoService.decryptAesGcm(
          ciphertextBase64: encrypted['ciphertext']!,
          ivBase64: encrypted['iv']!,
          tagBase64: tamperedTag,
          keyBytes: key,
        ),
        throwsA(anything),
      );
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

  group('Task 6.4: Full Round-Trip Unit Tests (Plaintext -> Encrypt -> Decrypt -> Match)', () {
    test('round-trip test: basic plaintext ASCII matches', () async {
      const plaintext = 'StandardPlaintextCredential123!';
      final key = await cryptoService.deriveMasterKey(
        masterPassword: 'MasterPassword!',
        saltBase64: cryptoService.generateSalt(),
      );

      final encrypted = await cryptoService.encryptAesGcm(plaintext: plaintext, keyBytes: key);
      final decrypted = await cryptoService.decryptAesGcm(
        ciphertextBase64: encrypted['ciphertext']!,
        ivBase64: encrypted['iv']!,
        tagBase64: encrypted['tag']!,
        keyBytes: key,
      );

      expect(decrypted, equals(plaintext));
    });

    test('round-trip test: multi-language UTF-8 unicode & emojis match', () async {
      const plaintext = 'PassMan 🔐 密码 密碼 パスワード كلمة المرور пароль 🚀✨';
      final key = await cryptoService.deriveMasterKey(
        masterPassword: 'UniversalPassword@2026',
        saltBase64: cryptoService.generateSalt(),
      );

      final encrypted = await cryptoService.encryptAesGcm(plaintext: plaintext, keyBytes: key);
      final decrypted = await cryptoService.decryptAesGcm(
        ciphertextBase64: encrypted['ciphertext']!,
        ivBase64: encrypted['iv']!,
        tagBase64: encrypted['tag']!,
        keyBytes: key,
      );

      expect(decrypted, equals(plaintext));
    });

    test('round-trip test: empty string matches', () async {
      const plaintext = '';
      final key = await cryptoService.deriveMasterKey(
        masterPassword: 'PasswordForEmpty',
        saltBase64: cryptoService.generateSalt(),
      );

      final encrypted = await cryptoService.encryptAesGcm(plaintext: plaintext, keyBytes: key);
      final decrypted = await cryptoService.decryptAesGcm(
        ciphertextBase64: encrypted['ciphertext']!,
        ivBase64: encrypted['iv']!,
        tagBase64: encrypted['tag']!,
        keyBytes: key,
      );

      expect(decrypted, equals(plaintext));
    });

    test('round-trip test: large multiline JSON payload matches', () async {
      final largeBuffer = StringBuffer();
      for (int i = 0; i < 500; i++) {
        largeBuffer.writeln('Entry $i: username=user$i@domain.com password=P@ssw0rd$i! notes=SecureNotes$i');
      }
      final plaintext = largeBuffer.toString();

      final key = await cryptoService.deriveMasterKey(
        masterPassword: 'LargePayloadMasterPassword',
        saltBase64: cryptoService.generateSalt(),
      );

      final encrypted = await cryptoService.encryptAesGcm(plaintext: plaintext, keyBytes: key);
      final decrypted = await cryptoService.decryptAesGcm(
        ciphertextBase64: encrypted['ciphertext']!,
        ivBase64: encrypted['iv']!,
        tagBase64: encrypted['tag']!,
        keyBytes: key,
      );

      expect(decrypted, equals(plaintext));
    });

    test('round-trip test: VaultItem model JSON envelope encrypt/decrypt matches', () async {
      final item = VaultItem(
        id: 'uuid-entry-1234',
        title: 'Production AWS Root Account',
        username: 'admin@company.internal',
        password: 'SuperSecretComplexPassword#2026',
        url: 'https://aws.amazon.com/console',
        notes: 'Backup 2FA seed phrase: test seed words ...',
        updatedAt: DateTime.utc(2026, 8, 29, 12, 0, 0),
      );

      final itemJson = jsonEncode(item.toJson());

      final key = await cryptoService.deriveMasterKey(
        masterPassword: 'VaultMasterPassword!99',
        saltBase64: cryptoService.generateSalt(),
      );

      // 1. Encrypt to JSON envelope
      final vaultEnvelopeJson = await cryptoService.encryptVaultPayload(
        plaintext: itemJson,
        keyBytes: key,
      );

      // 2. Decrypt envelope back to item JSON
      final restoredItemJson = await cryptoService.decryptVaultPayload(
        jsonPayload: vaultEnvelopeJson,
        keyBytes: key,
      );

      expect(restoredItemJson, equals(itemJson));

      // 3. Deserialize back to VaultItem and verify equality
      final restoredItem = VaultItem.fromJson(jsonDecode(restoredItemJson) as Map<String, dynamic>);
      expect(restoredItem.id, equals(item.id));
      expect(restoredItem.title, equals(item.title));
      expect(restoredItem.username, equals(item.username));
      expect(restoredItem.password, equals(item.password));
      expect(restoredItem.url, equals(item.url));
      expect(restoredItem.notes, equals(item.notes));
    });
  });
}
