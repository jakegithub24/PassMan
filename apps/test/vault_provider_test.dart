import 'dart:convert';
import 'package:apps/models/encrypted_vault_entry.dart';
import 'package:apps/models/vault_item.dart';
import 'package:apps/providers/providers.dart';
import 'package:apps/services/crypto_service.dart';
import 'package:apps/services/local_vault_storage_service.dart';
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
  late List<int> sessionKey;

  setUp(() async {
    cryptoService = CryptoService(pbkdf2Iterations: 1000);
    sessionKey = await cryptoService.deriveMasterKey(
      masterPassword: 'MasterPassword123!',
      saltBase64: cryptoService.generateSalt(),
    );

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

  group('VaultState Model Unit Tests (Task 7.1)', () {
    final item1 = VaultItem(
      id: '1',
      title: 'GitHub Work',
      username: 'user@company.com',
      password: 'password1',
      url: 'https://github.com',
      notes: 'SSH key: id_rsa',
      category: 'logins',
      updatedAt: DateTime.utc(2026, 8, 29, 10, 0),
    );

    final item2 = VaultItem(
      id: '2',
      title: 'Personal Gmail',
      username: 'personal@gmail.com',
      password: 'password2',
      url: 'https://mail.google.com',
      category: 'logins',
      updatedAt: DateTime.utc(2026, 8, 29, 11, 0),
    );

    final item3 = VaultItem(
      id: '3',
      title: 'Credit Card',
      username: 'Visa 4321',
      password: 'cvv 999',
      category: 'cards',
      updatedAt: DateTime.utc(2026, 8, 29, 12, 0),
    );

    final itemDeleted = VaultItem(
      id: '4',
      title: 'Old Deleted Service',
      username: 'deleted',
      password: 'deleted',
      category: 'logins',
      updatedAt: DateTime.utc(2026, 8, 29, 13, 0),
      deletedAt: DateTime.utc(2026, 8, 29, 14, 0),
    );

    test('filteredItems filters by category and excludes deleted items', () {
      final stateAll = VaultState(
        status: VaultStatus.ready,
        items: [item1, item2, item3, itemDeleted],
        selectedCategory: 'all',
      );

      expect(stateAll.filteredItems.length, equals(3));
      expect(stateAll.filteredItems.any((i) => i.id == '4'), isFalse);

      final stateCards = stateAll.copyWith(selectedCategory: 'cards');
      expect(stateCards.filteredItems.length, equals(1));
      expect(stateCards.filteredItems.first.title, equals('Credit Card'));
    });

    test('filteredItems matches search queries across title, username, url, and notes', () {
      final state = VaultState(
        status: VaultStatus.ready,
        items: [item1, item2, item3],
      );

      final searchTitle = state.copyWith(searchQuery: 'github');
      expect(searchTitle.filteredItems.length, equals(1));
      expect(searchTitle.filteredItems.first.id, equals('1'));

      final searchEmail = state.copyWith(searchQuery: 'personal@');
      expect(searchEmail.filteredItems.length, equals(1));
      expect(searchEmail.filteredItems.first.id, equals('2'));

      final searchNotes = state.copyWith(searchQuery: 'ssh key');
      expect(searchNotes.filteredItems.length, equals(1));
      expect(searchNotes.filteredItems.first.id, equals('1'));

      final searchNotFound = state.copyWith(searchQuery: 'nonexistent');
      expect(searchNotFound.filteredItems.isEmpty, isTrue);
    });

    test('copyWith, equality, and hashCode work as expected', () {
      const s1 = VaultState(status: VaultStatus.ready, searchQuery: 'abc');
      final s2 = s1.copyWith(searchQuery: 'xyz');
      final s3 = const VaultState(status: VaultStatus.ready, searchQuery: 'abc');

      expect(s2.searchQuery, equals('xyz'));
      expect(s1, equals(s3));
      expect(s1.hashCode, equals(s3.hashCode));
    });
  });

  group('VaultNotifier CRUD Operations & Cryptography Tests (Task 7.1)', () {
    test('loadVault with missing session key sets locked status', () async {
      final notifier = VaultNotifier(
        localVaultStorage: localVaultStorage,
        cryptoService: cryptoService,
        getSessionKey: () => null,
        getUserId: () => 'user-1',
      );

      await notifier.loadVault();

      expect(notifier.state.status, equals(VaultStatus.locked));
      expect(notifier.state.items.isEmpty, isTrue);
    });

    test('addEntry encrypts payload with session key and persists to SQLite', () async {
      final notifier = VaultNotifier(
        localVaultStorage: localVaultStorage,
        cryptoService: cryptoService,
        getSessionKey: () => sessionKey,
        getUserId: () => 'user-123',
      );

      final added = await notifier.addEntry(
        title: 'Twitter / X',
        username: 'user@x.com',
        password: 'SuperSecretPassword!',
        url: 'https://x.com',
        notes: '2FA Backup Key: 1234',
        category: 'logins',
      );

      expect(added, isNotNull);
      expect(added!.title, equals('Twitter / X'));
      expect(notifier.state.items.length, equals(1));
      expect(notifier.state.items.first.id, equals(added.id));

      // Verify entry exists in SQLite in encrypted form
      final cached = await localVaultStorage.getEntry(added.id);
      expect(cached, isNotNull);
      expect(cached!.userId, equals('user-123'));

      // Decrypt directly to verify ciphertext integrity
      final decryptedJson = await cryptoService.decryptVaultPayload(
        jsonPayload: cached.encryptedData,
        keyBytes: sessionKey,
      );
      final restored = VaultItem.fromJson(jsonDecode(decryptedJson) as Map<String, dynamic>);
      expect(restored.password, equals('SuperSecretPassword!'));
    });

    test('loadVault decrypts and populates existing entries', () async {
      // Seed SQLite with 2 encrypted entries
      final item1 = VaultItem(
        id: 'item-1',
        title: 'Entry 1',
        username: 'user1',
        password: 'pass1',
        updatedAt: DateTime.utc(2026, 8, 29, 10, 0),
      );
      final item2 = VaultItem(
        id: 'item-2',
        title: 'Entry 2',
        username: 'user2',
        password: 'pass2',
        updatedAt: DateTime.utc(2026, 8, 29, 11, 0),
      );

      final enc1 = await cryptoService.encryptVaultPayload(
        plaintext: jsonEncode(item1.toJson()),
        keyBytes: sessionKey,
      );
      final enc2 = await cryptoService.encryptVaultPayload(
        plaintext: jsonEncode(item2.toJson()),
        keyBytes: sessionKey,
      );

      await localVaultStorage.saveEntry(
        EncryptedVaultEntry(id: item1.id, userId: 'u1', encryptedData: enc1, updatedAt: item1.updatedAt),
      );
      await localVaultStorage.saveEntry(
        EncryptedVaultEntry(id: item2.id, userId: 'u1', encryptedData: enc2, updatedAt: item2.updatedAt),
      );

      final notifier = VaultNotifier(
        localVaultStorage: localVaultStorage,
        cryptoService: cryptoService,
        getSessionKey: () => sessionKey,
        getUserId: () => 'u1',
      );

      await notifier.loadVault();

      expect(notifier.state.status, equals(VaultStatus.ready));
      expect(notifier.state.items.length, equals(2));
      expect(notifier.state.items.any((i) => i.id == 'item-1'), isTrue);
      expect(notifier.state.items.any((i) => i.id == 'item-2'), isTrue);
    });

    test('updateEntry modifies item, updates timestamp, and re-encrypts', () async {
      final notifier = VaultNotifier(
        localVaultStorage: localVaultStorage,
        cryptoService: cryptoService,
        getSessionKey: () => sessionKey,
        getUserId: () => 'u1',
      );

      final added = await notifier.addEntry(
        title: 'Netflix',
        username: 'watcher@gmail.com',
        password: 'old_password',
      );

      expect(added, isNotNull);

      final updatedItem = added!.copyWith(
        password: 'brand_new_secure_password',
        notes: 'Family plan',
      );

      final success = await notifier.updateEntry(updatedItem);
      expect(success, isTrue);

      expect(notifier.state.items.first.password, equals('brand_new_secure_password'));
      expect(notifier.state.items.first.notes, equals('Family plan'));

      // Verify SQLite reflects updated re-encrypted content
      final cached = await localVaultStorage.getEntry(added.id);
      final decrypted = await cryptoService.decryptVaultPayload(
        jsonPayload: cached!.encryptedData,
        keyBytes: sessionKey,
      );
      final decryptedItem = VaultItem.fromJson(jsonDecode(decrypted) as Map<String, dynamic>);
      expect(decryptedItem.password, equals('brand_new_secure_password'));
    });

    test('deleteEntry soft deletes item and removes from in-memory state', () async {
      final notifier = VaultNotifier(
        localVaultStorage: localVaultStorage,
        cryptoService: cryptoService,
        getSessionKey: () => sessionKey,
        getUserId: () => 'u1',
      );

      final added = await notifier.addEntry(
        title: 'Disposable Account',
        username: 'temp@temp.com',
        password: '123',
      );

      expect(notifier.state.items.length, equals(1));

      final deleted = await notifier.deleteEntry(added!.id);
      expect(deleted, isTrue);
      expect(notifier.state.items.isEmpty, isTrue);

      // Verify soft delete in SQLite
      final cached = await localVaultStorage.getEntry(added.id);
      expect(cached!.isDeleted, isTrue);
    });

    test('setSearchQuery, setCategory, and clearSearch work properly', () {
      final notifier = VaultNotifier(
        localVaultStorage: localVaultStorage,
        cryptoService: cryptoService,
        getSessionKey: () => sessionKey,
        getUserId: () => 'u1',
      );

      notifier.setSearchQuery('google');
      expect(notifier.state.searchQuery, equals('google'));

      notifier.setCategory('cards');
      expect(notifier.state.selectedCategory, equals('cards'));

      notifier.clearSearch();
      expect(notifier.state.searchQuery, isEmpty);
    });

    test('clear wipes in-memory items and resets to locked', () async {
      final notifier = VaultNotifier(
        localVaultStorage: localVaultStorage,
        cryptoService: cryptoService,
        getSessionKey: () => sessionKey,
        getUserId: () => 'u1',
      );

      await notifier.addEntry(title: 'Item 1', username: 'u', password: 'p');
      expect(notifier.state.items.isNotEmpty, isTrue);

      notifier.clear();
      expect(notifier.state.items.isEmpty, isTrue);
      expect(notifier.state.status, equals(VaultStatus.locked));
    });
  });

  group('Riverpod ProviderContainer Vault Providers Integration', () {
    test('vaultStateProvider and derived selectors provide expected values', () async {
      final container = ProviderContainer(
        overrides: [
          localVaultStorageServiceProvider.overrideWithValue(localVaultStorage),
          cryptoServiceProvider.overrideWithValue(cryptoService),
          sessionKeyProvider.overrideWithValue(sessionKey),
        ],
      );

      final notifier = container.read(vaultStateProvider.notifier);

      expect(container.read(vaultStatusProvider), equals(VaultStatus.initial));
      expect(container.read(vaultItemsCountProvider), equals(0));

      await notifier.addEntry(
        title: 'Amazon',
        username: 'shopper@gmail.com',
        password: 'prime_password',
        category: 'logins',
      );

      expect(container.read(vaultItemsCountProvider), equals(1));
      expect(container.read(vaultItemsProvider).first.title, equals('Amazon'));

      notifier.setSearchQuery('Amazon');
      expect(container.read(vaultSearchQueryProvider), equals('Amazon'));

      notifier.setCategory('logins');
      expect(container.read(vaultCategoryProvider), equals('logins'));
    });
  });
}
