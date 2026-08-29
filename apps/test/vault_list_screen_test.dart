import 'package:apps/models/vault_item.dart';
import 'package:apps/providers/providers.dart';
import 'package:apps/screens/vault_list_screen.dart';
import 'package:apps/services/crypto_service.dart';
import 'package:apps/services/local_vault_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late CryptoService cryptoService;
  late LocalVaultStorageService localVaultStorage;
  late Database ffiDb;

  final sampleItems = [
    VaultItem(
      id: 'entry-1',
      title: 'GitHub Professional',
      username: 'dev@github.com',
      password: 'github_password_123',
      url: 'https://github.com',
      notes: 'Work repository access',
      category: 'logins',
      updatedAt: DateTime.utc(2026, 8, 30, 10, 0),
    ),
    VaultItem(
      id: 'entry-2',
      title: 'Chase Sapphire Reserve',
      username: 'Visa 9876',
      password: 'cvv 123',
      category: 'cards',
      updatedAt: DateTime.utc(2026, 8, 30, 11, 0),
    ),
    VaultItem(
      id: 'entry-3',
      title: 'Server Recovery Seed',
      username: 'admin',
      password: 'seed phrase ...',
      category: 'notes',
      updatedAt: DateTime.utc(2026, 8, 30, 12, 0),
    ),
  ];

  setUp(() async {
    cryptoService = CryptoService(pbkdf2Iterations: 1000);
    ffiDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await ffiDb.execute('''
      CREATE TABLE ${LocalVaultStorageService.tableName} (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        encrypted_data TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        is_dirty INTEGER NOT NULL DEFAULT 0
      )
    ''');
    localVaultStorage = LocalVaultStorageService(sqliteDb: ffiDb);
  });

  tearDown(() async {
    await ffiDb.close();
  });

  Widget createWidgetUnderTest({
    List<VaultItem>? items,
    VaultStatus status = VaultStatus.ready,
    Size size = const Size(1200, 800),
    VoidCallback? onAddNew,
    ValueChanged<VaultItem>? onEditItem,
  }) {
    return ProviderScope(
      overrides: [
        localVaultStorageServiceProvider.overrideWithValue(localVaultStorage),
        cryptoServiceProvider.overrideWithValue(cryptoService),
        vaultStateProvider.overrideWith(
          (ref) => _MockVaultNotifier(
            VaultState(status: status, items: items ?? []),
            localVaultStorage,
            cryptoService,
          ),
        ),
      ],
      child: MaterialApp(
        home: SizedBox(
          width: size.width,
          height: size.height,
          child: VaultListScreen(
            onAddNew: onAddNew,
            onEditItem: onEditItem,
          ),
        ),
      ),
    );
  }

  group('VaultListScreen UI & Interaction Tests (Task 7.2)', () {
    testWidgets('renders empty state when vault has no items', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest(items: []));
      await tester.pumpAndSettle();

      expect(find.text('Your vault is currently empty'), findsOneWidget);
      expect(find.text('Add Password'), findsOneWidget);
    });

    testWidgets('renders desktop sidebar and item cards in grid layout', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createWidgetUnderTest(
        items: sampleItems,
        size: const Size(1280, 900),
      ));
      await tester.pumpAndSettle();

      // Check desktop sidebar
      expect(find.text('PassMan'), findsOneWidget);
      expect(find.text('CATEGORIES'), findsOneWidget);
      expect(find.text('All Items'), findsOneWidget);

      // Check rendered vault cards
      expect(find.text('GitHub Professional'), findsOneWidget);
      expect(find.text('Chase Sapphire Reserve'), findsOneWidget);
      expect(find.text('Server Recovery Seed'), findsOneWidget);
    });

    testWidgets('renders mobile layout with app bar and category filter chips', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createWidgetUnderTest(
        items: sampleItems,
        size: const Size(390, 844),
      ));
      await tester.pumpAndSettle();

      expect(find.text('My Passwords'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Logins'), findsOneWidget);
      expect(find.text('Cards'), findsOneWidget);
      expect(find.text('GitHub Professional'), findsOneWidget);
    });

    testWidgets('search box updates query and filters items', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createWidgetUnderTest(
        items: sampleItems,
        size: const Size(1280, 900),
      ));
      await tester.pumpAndSettle();

      // Type in search box
      final searchInput = find.byType(TextField).first;
      await tester.enterText(searchInput, 'Chase');
      await tester.pumpAndSettle();

      expect(find.text('Chase Sapphire Reserve'), findsOneWidget);
      expect(find.text('GitHub Professional'), findsNothing);
    });

    testWidgets('renders locked state when vault is locked', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest(
        items: sampleItems,
        status: VaultStatus.locked,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Vault is Locked'), findsOneWidget);
      expect(find.text('Your master password is required to decrypt your vault items.'), findsOneWidget);
    });

    testWidgets('tapping new item button triggers callback', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool addNewCalled = false;

      await tester.pumpWidget(createWidgetUnderTest(
        items: sampleItems,
        size: const Size(390, 844),
        onAddNew: () => addNewCalled = true,
      ));
      await tester.pumpAndSettle();

      final fab = find.byType(FloatingActionButton);
      expect(fab, findsOneWidget);

      await tester.tap(fab);
      await tester.pumpAndSettle();

      expect(addNewCalled, isTrue);
    });
  });
}

class _MockVaultNotifier extends VaultNotifier {
  _MockVaultNotifier(
    VaultState initialState,
    LocalVaultStorageService localVault,
    CryptoService crypto,
  ) : super(
          localVaultStorage: localVault,
          cryptoService: crypto,
          getSessionKey: () => [1, 2, 3],
          getUserId: () => 'u1',
        ) {
    state = initialState;
  }

  @override
  Future<void> loadVault() async {}
}
