import 'package:apps/models/encrypted_vault_entry.dart';
import 'package:apps/models/vault_item.dart';
import 'package:apps/providers/providers.dart';
import 'package:apps/screens/add_edit_entry_screen.dart';
import 'package:apps/services/crypto_service.dart';
import 'package:apps/services/local_vault_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeLocalVaultStorageService extends LocalVaultStorageService {
  final Map<String, EncryptedVaultEntry> _storage = {};

  @override
  Future<void> saveEntry(EncryptedVaultEntry entry, {bool isDirty = false}) async {
    _storage[entry.id] = entry;
  }

  @override
  Future<EncryptedVaultEntry?> getEntry(String id) async {
    return _storage[id];
  }

  @override
  Future<List<EncryptedVaultEntry>> getAllEntries({bool includeDeleted = false}) async {
    return _storage.values.where((e) => includeDeleted || e.deletedAt == null).toList();
  }

  @override
  Future<void> markDeleted(String id) async {
    final existing = _storage[id];
    if (existing != null) {
      _storage[id] = existing.copyWith(deletedAt: DateTime.now().toUtc());
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CryptoService cryptoService;
  late FakeLocalVaultStorageService localVaultStorage;
  late List<int> sessionKey;
  late VaultNotifier vaultNotifier;

  setUp(() async {
    cryptoService = CryptoService(pbkdf2Iterations: 1000);
    sessionKey = await cryptoService.deriveMasterKey(
      masterPassword: 'MasterPassword123!',
      saltBase64: cryptoService.generateSalt(),
    );

    localVaultStorage = FakeLocalVaultStorageService();

    vaultNotifier = VaultNotifier(
      localVaultStorage: localVaultStorage,
      cryptoService: cryptoService,
      getSessionKey: () => sessionKey,
      getUserId: () => 'user-1',
    );
  });

  Widget createWidgetUnderTest({
    VaultItem? initialItem,
    ValueChanged<VaultItem>? onSaved,
  }) {
    return ProviderScope(
      overrides: [
        vaultStateProvider.overrideWith((ref) => vaultNotifier),
      ],
      child: MaterialApp(
        home: AddEditEntryScreen(
          initialItem: initialItem,
          onSaved: onSaved,
        ),
      ),
    );
  }

  group('AddEditEntryScreen UI & Encryption Tests (Task 7.3)', () {
    testWidgets('renders add mode with empty fields and category chips', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('New Item'), findsOneWidget);
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('form validation triggers on empty title and password', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Tap Save in AppBar with empty fields
      final saveBtn = find.text('Save');
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(find.text('Title is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);
    });

    testWidgets('renders edit mode with pre-populated fields', (tester) async {
      final existingItem = VaultItem(
        id: 'entry-99',
        title: 'Spotify Premium',
        username: 'music@spotify.com',
        password: 'spotify_secret_pass',
        url: 'https://spotify.com',
        notes: 'Family plan slot 3',
        category: 'logins',
        updatedAt: DateTime.utc(2026, 8, 30, 10, 0),
      );

      await tester.pumpWidget(createWidgetUnderTest(initialItem: existingItem));
      await tester.pumpAndSettle();

      expect(find.text('Edit Item'), findsOneWidget);
      expect(find.text('Spotify Premium'), findsOneWidget);
      expect(find.text('music@spotify.com'), findsOneWidget);
      expect(find.text('spotify_secret_pass'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('password generator generates secure password and updates field', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Tap Generate button
      final generateBtn = find.text('Generate');
      await tester.tap(generateBtn);
      await tester.pumpAndSettle();

      expect(find.text('Password Generator'), findsOneWidget);
      expect(find.text('Use This Password'), findsOneWidget);

      // Tap Use This Password
      await tester.tap(find.text('Use This Password'));
      await tester.pumpAndSettle();

      // Verify password field is now populated
      final passwordField = tester.widget<TextFormField>(find.byType(TextFormField).at(2));
      expect(passwordField.controller!.text.isNotEmpty, isTrue);
      expect(passwordField.controller!.text.length, equals(18));
    });

    testWidgets('valid form submission in add mode encrypts and calls onSaved', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      VaultItem? savedResult;

      await tester.pumpWidget(createWidgetUnderTest(
        onSaved: (item) => savedResult = item,
      ));
      await tester.pumpAndSettle();

      // Enter Title
      await tester.enterText(find.byType(TextFormField).at(0), 'Amazon AWS Console');
      // Enter Username
      await tester.enterText(find.byType(TextFormField).at(1), 'aws_root@company.com');
      // Enter Password
      await tester.enterText(find.byType(TextFormField).at(2), 'SuperSecretAwsPass#2026');
      // Enter URL
      await tester.enterText(find.byType(TextFormField).at(3), 'https://console.aws.amazon.com');
      // Enter Notes
      await tester.enterText(find.byType(TextFormField).at(4), 'MFA hardware token');

      await tester.pumpAndSettle();

      // Tap Save in AppBar
      final saveBtn = find.text('Save');
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(savedResult, isNotNull);
      expect(savedResult!.title, equals('Amazon AWS Console'));
      expect(savedResult!.username, equals('aws_root@company.com'));
      expect(savedResult!.password, equals('SuperSecretAwsPass#2026'));

      // Verify ciphertext was written to in-memory fake storage
      final cached = await localVaultStorage.getEntry(savedResult!.id);
      expect(cached, isNotNull);

      // Decrypt to verify zero-knowledge encryption
      final decryptedJson = await cryptoService.decryptVaultPayload(
        jsonPayload: cached!.encryptedData,
        keyBytes: sessionKey,
      );
      expect(decryptedJson.contains('SuperSecretAwsPass#2026'), isTrue);
    });

    testWidgets('valid edit submission re-encrypts and updates entry', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final existingItem = VaultItem(
        id: 'entry-test-edit',
        title: 'Old Title',
        username: 'old@example.com',
        password: 'old_password_123',
        category: 'logins',
        updatedAt: DateTime.utc(2026, 8, 30, 10, 0),
      );

      // Pre-save to local storage
      final enc = await cryptoService.encryptVaultPayload(
        plaintext: '{"id":"entry-test-edit"}',
        keyBytes: sessionKey,
      );
      await localVaultStorage.saveEntry(EncryptedVaultEntry(
        id: existingItem.id,
        userId: 'u1',
        encryptedData: enc,
        updatedAt: existingItem.updatedAt,
      ));

      VaultItem? savedResult;

      await tester.pumpWidget(createWidgetUnderTest(
        initialItem: existingItem,
        onSaved: (item) => savedResult = item,
      ));
      await tester.pumpAndSettle();

      // Change Title and Password
      await tester.enterText(find.byType(TextFormField).at(0), 'Updated Work GitHub');
      await tester.enterText(find.byType(TextFormField).at(2), 'NewSuperStrongPassword#2026');
      await tester.pumpAndSettle();

      // Tap Save
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(savedResult, isNotNull);
      expect(savedResult!.title, equals('Updated Work GitHub'));
      expect(savedResult!.password, equals('NewSuperStrongPassword#2026'));

      // Verify storage has updated encrypted data
      final cached = await localVaultStorage.getEntry(existingItem.id);
      final decryptedJson = await cryptoService.decryptVaultPayload(
        jsonPayload: cached!.encryptedData,
        keyBytes: sessionKey,
      );
      expect(decryptedJson.contains('NewSuperStrongPassword#2026'), isTrue);
    });
  });
}
