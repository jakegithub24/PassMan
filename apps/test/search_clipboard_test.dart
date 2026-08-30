import 'package:apps/models/encrypted_vault_entry.dart';
import 'package:apps/models/vault_item.dart';
import 'package:apps/providers/providers.dart';
import 'package:apps/screens/add_edit_entry_screen.dart';
import 'package:apps/screens/vault_list_screen.dart';
import 'package:apps/services/crypto_service.dart';
import 'package:apps/services/local_vault_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  String? mockClipboardData;

  final item1 = VaultItem(
    id: 'item-1',
    title: 'GitHub Enterprise',
    username: 'dev_lead@github.com',
    password: 'ghp_superSecretToken12345',
    url: 'https://github.com',
    notes: 'SSH key: id_ed25519_work',
    category: 'logins',
    updatedAt: DateTime.utc(2026, 8, 30, 10, 0),
  );

  final item2 = VaultItem(
    id: 'item-2',
    title: 'AWS Cloud Console',
    username: 'root_admin@aws.amazon.com',
    password: 'AwsRootMasterPassword#999',
    url: 'https://console.aws.amazon.com',
    notes: 'MFA: YubiKey 5C NFC',
    category: 'logins',
    updatedAt: DateTime.utc(2026, 8, 30, 11, 0),
  );

  final item3 = VaultItem(
    id: 'item-3',
    title: 'Corporate Amex Card',
    username: 'Tech Lead Corp',
    password: '4321',
    category: 'cards',
    notes: 'Exp: 12/28, PIN: 9988',
    updatedAt: DateTime.utc(2026, 8, 30, 12, 0),
  );

  setUp(() async {
    mockClipboardData = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          mockClipboardData = (methodCall.arguments as Map?)?['text'] as String?;
          return null;
        } else if (methodCall.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': mockClipboardData};
        }
        return null;
      },
    );

    cryptoService = CryptoService(pbkdf2Iterations: 1000);
    sessionKey = await cryptoService.deriveMasterKey(
      masterPassword: 'MasterPassword123!',
      saltBase64: cryptoService.generateSalt(),
    );

    localVaultStorage = FakeLocalVaultStorageService();

    for (final item in [item1, item2, item3]) {
      final enc = await cryptoService.encryptVaultPayload(
        plaintext: '{"id":"${item.id}","title":"${item.title}","username":"${item.username}","password":"${item.password}","url":"${item.url ?? ''}","notes":"${item.notes ?? ''}","category":"${item.category}","updated_at":"${item.updatedAt.toIso8601String()}"}',
        keyBytes: sessionKey,
      );
      await localVaultStorage.saveEntry(EncryptedVaultEntry(
        id: item.id,
        userId: 'user-1',
        encryptedData: enc,
        updatedAt: item.updatedAt,
      ));
    }

    vaultNotifier = VaultNotifier(
      localVaultStorage: localVaultStorage,
      cryptoService: cryptoService,
      getSessionKey: () => sessionKey,
      getUserId: () => 'user-1',
    );

    await vaultNotifier.loadVault();
  });

  group('Search & Filtering Tests (Task 7.5)', () {
    testWidgets('search box filters items by title in real-time', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultStateProvider.overrideWith((ref) => vaultNotifier),
          ],
          child: const MaterialApp(
            home: VaultListScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('GitHub Enterprise'), findsOneWidget);
      expect(find.text('AWS Cloud Console'), findsOneWidget);
      expect(find.text('Corporate Amex Card'), findsOneWidget);

      // Search for "aws"
      final searchField = find.byType(TextField).first;
      await tester.enterText(searchField, 'aws');
      await tester.pumpAndSettle();

      expect(find.text('AWS Cloud Console'), findsOneWidget);
      expect(find.text('GitHub Enterprise'), findsNothing);
      expect(find.text('Corporate Amex Card'), findsNothing);
    });

    testWidgets('search box filters items by username and email substring', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultStateProvider.overrideWith((ref) => vaultNotifier),
          ],
          child: const MaterialApp(
            home: VaultListScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField).first;
      await tester.enterText(searchField, 'dev_lead@github');
      await tester.pumpAndSettle();

      expect(find.text('GitHub Enterprise'), findsOneWidget);
      expect(find.text('AWS Cloud Console'), findsNothing);
    });

    testWidgets('search box filters items by notes keyword', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultStateProvider.overrideWith((ref) => vaultNotifier),
          ],
          child: const MaterialApp(
            home: VaultListScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField).first;
      await tester.enterText(searchField, 'YubiKey');
      await tester.pumpAndSettle();

      expect(find.text('AWS Cloud Console'), findsOneWidget);
      expect(find.text('GitHub Enterprise'), findsNothing);
    });

    testWidgets('clear search button resets filtered list to all items', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultStateProvider.overrideWith((ref) => vaultNotifier),
          ],
          child: const MaterialApp(
            home: VaultListScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField).first;
      await tester.enterText(searchField, 'nonexistent_query_123');
      await tester.pumpAndSettle();

      expect(find.text('No matching passwords found'), findsOneWidget);
      expect(find.text('Clear Search'), findsOneWidget);

      // Tap Clear Search button
      await tester.tap(find.text('Clear Search'));
      await tester.pumpAndSettle();

      expect(find.text('GitHub Enterprise'), findsOneWidget);
      expect(find.text('AWS Cloud Console'), findsOneWidget);
      expect(find.text('Corporate Amex Card'), findsOneWidget);
    });
  });

  group('Copy-to-Clipboard Flow Tests (Task 7.5)', () {
    testWidgets('quick copy username button copies to clipboard and shows SnackBar', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultStateProvider.overrideWith((ref) => vaultNotifier),
          ],
          child: const MaterialApp(
            home: VaultListScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find username copy button (IconButton with Icons.person_rounded) on card
      final copyUsernameBtn = find.widgetWithIcon(IconButton, Icons.person_rounded).first;
      await tester.tap(copyUsernameBtn);
      await tester.pumpAndSettle();

      // Verify SnackBar shown
      expect(find.text('Username copied to clipboard!'), findsOneWidget);

      // Verify clipboard contents
      expect(mockClipboardData, equals('dev_lead@github.com'));
    });

    testWidgets('quick copy password button copies to clipboard and shows SnackBar', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultStateProvider.overrideWith((ref) => vaultNotifier),
          ],
          child: const MaterialApp(
            home: VaultListScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find password copy button on card
      final copyPassBtn = find.widgetWithIcon(IconButton, Icons.copy_rounded).first;
      await tester.tap(copyPassBtn);
      await tester.pumpAndSettle();

      expect(find.text('Password copied to clipboard!'), findsOneWidget);
      expect(mockClipboardData, equals('ghp_superSecretToken12345'));
    });

    testWidgets('card popup menu Copy Username copies to clipboard', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultStateProvider.overrideWith((ref) => vaultNotifier),
          ],
          child: const MaterialApp(
            home: VaultListScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open popup menu on first card
      final moreBtn = find.byIcon(Icons.more_vert_rounded).first;
      await tester.tap(moreBtn);
      await tester.pumpAndSettle();

      // Tap Copy Username in menu
      await tester.tap(find.text('Copy Username'));
      await tester.pumpAndSettle();

      expect(find.text('Username copied to clipboard!'), findsOneWidget);
      expect(mockClipboardData, equals('dev_lead@github.com'));
    });

    testWidgets('card popup menu Copy Password copies to clipboard', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultStateProvider.overrideWith((ref) => vaultNotifier),
          ],
          child: const MaterialApp(
            home: VaultListScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open popup menu on first card
      final moreBtn = find.byIcon(Icons.more_vert_rounded).first;
      await tester.tap(moreBtn);
      await tester.pumpAndSettle();

      // Tap Copy Password in menu
      await tester.tap(find.text('Copy Password'));
      await tester.pumpAndSettle();

      expect(find.text('Password copied to clipboard!'), findsOneWidget);
      expect(mockClipboardData, equals('ghp_superSecretToken12345'));
    });

    testWidgets('AddEditEntryScreen allows copying username to clipboard', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultStateProvider.overrideWith((ref) => vaultNotifier),
          ],
          child: MaterialApp(
            home: AddEditEntryScreen(initialItem: item1),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find copy icon on Username field
      final copyUsernameBtn = find.widgetWithIcon(IconButton, Icons.copy_rounded).first;
      await tester.tap(copyUsernameBtn);
      await tester.pumpAndSettle();

      expect(find.text('Username / Email copied to clipboard'), findsOneWidget);
      expect(mockClipboardData, equals('dev_lead@github.com'));
    });
  });
}
