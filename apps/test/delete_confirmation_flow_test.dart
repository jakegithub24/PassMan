import 'package:apps/models/encrypted_vault_entry.dart';
import 'package:apps/models/vault_item.dart';
import 'package:apps/providers/providers.dart';
import 'package:apps/screens/add_edit_entry_screen.dart';
import 'package:apps/screens/vault_list_screen.dart';
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

  final sampleItem1 = VaultItem(
    id: 'item-1',
    title: 'Google Account',
    username: 'google@gmail.com',
    password: 'Password123!',
    url: 'https://google.com',
    category: 'logins',
    updatedAt: DateTime.utc(2026, 8, 30, 10, 0),
  );

  final sampleItem2 = VaultItem(
    id: 'item-2',
    title: 'Personal Visa Card',
    username: 'John Doe',
    password: '999',
    category: 'cards',
    updatedAt: DateTime.utc(2026, 8, 30, 11, 0),
  );

  setUp(() async {
    cryptoService = CryptoService(pbkdf2Iterations: 1000);
    sessionKey = await cryptoService.deriveMasterKey(
      masterPassword: 'MasterPassword123!',
      saltBase64: cryptoService.generateSalt(),
    );

    localVaultStorage = FakeLocalVaultStorageService();

    // Pre-populate storage with encrypted sample items
    for (final item in [sampleItem1, sampleItem2]) {
      final enc = await cryptoService.encryptVaultPayload(
        plaintext: '{"id":"${item.id}","title":"${item.title}","username":"${item.username}","password":"${item.password}","category":"${item.category}","updated_at":"${item.updatedAt.toIso8601String()}"}',
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

  group('Delete Confirmation Flow Tests (Task 7.4)', () {
    testWidgets('canceling delete confirmation in VaultListScreen leaves item intact', (tester) async {
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

      expect(find.text('Google Account'), findsOneWidget);

      // Open popup menu on Google Account card
      final moreBtn = find.byIcon(Icons.more_vert_rounded).first;
      await tester.tap(moreBtn);
      await tester.pumpAndSettle();

      // Tap Delete in menu
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Verify dialog is visible
      expect(find.text('Delete Entry?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog dismissed, item still present
      expect(find.text('Delete Entry?'), findsNothing);
      expect(find.text('Google Account'), findsOneWidget);
      expect(vaultNotifier.state.items.length, equals(2));
    });

    testWidgets('confirming delete in VaultListScreen deletes item, updates state, and shows SnackBar', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      VaultItem? deletedCallbackItem;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultStateProvider.overrideWith((ref) => vaultNotifier),
          ],
          child: MaterialApp(
            home: VaultListScreen(
              onDeleteItem: (item) => deletedCallbackItem = item,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open popup menu on Google Account
      final moreBtn = find.byIcon(Icons.more_vert_rounded).first;
      await tester.tap(moreBtn);
      await tester.pumpAndSettle();

      // Tap Delete in menu
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Entry?'), findsOneWidget);

      // Tap Delete in AlertDialog
      final confirmDeleteBtn = find.widgetWithText(ElevatedButton, 'Delete');
      await tester.tap(confirmDeleteBtn);
      await tester.pumpAndSettle();

      // Verify item removed from UI and state
      expect(find.text('Google Account'), findsNothing);
      expect(vaultNotifier.state.items.length, equals(1));
      expect(deletedCallbackItem?.id, equals('item-1'));

      // Verify SnackBar shown
      expect(find.text('Deleted "Google Account"'), findsOneWidget);

      // Verify soft-deleted in storage
      final stored = await localVaultStorage.getEntry('item-1');
      expect(stored?.isDeleted, isTrue);
    });

    testWidgets('AddEditEntryScreen in edit mode allows deleting item via confirmation dialog', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      VaultItem? deletedItem;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultStateProvider.overrideWith((ref) => vaultNotifier),
          ],
          child: MaterialApp(
            home: AddEditEntryScreen(
              initialItem: sampleItem2,
              onDeleted: (item) => deletedItem = item,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Delete Entry button is visible in edit mode
      final deleteBtn = find.widgetWithText(OutlinedButton, 'Delete Entry');
      expect(deleteBtn, findsOneWidget);

      // Scroll and tap Delete Entry button
      await tester.ensureVisible(deleteBtn);
      await tester.pumpAndSettle();
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      expect(find.text('Delete Entry?'), findsOneWidget);
      expect(find.text('Are you sure you want to delete "Personal Visa Card"? This item will be removed from your encrypted vault.'), findsOneWidget);

      // Tap Delete in confirmation dialog
      final confirmBtn = find.widgetWithText(ElevatedButton, 'Delete');
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      expect(deletedItem?.id, equals('item-2'));
      expect(vaultNotifier.state.items.where((i) => i.id == 'item-2').isEmpty, isTrue);

      // Verify soft-deleted in storage
      final stored = await localVaultStorage.getEntry('item-2');
      expect(stored?.isDeleted, isTrue);
    });

    testWidgets('AddEditEntryScreen in add mode does not display delete button', (tester) async {
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
            home: AddEditEntryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(OutlinedButton, 'Delete Entry'), findsNothing);
    });
  });
}
