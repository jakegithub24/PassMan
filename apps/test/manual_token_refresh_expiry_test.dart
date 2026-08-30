import 'dart:convert';
import 'package:apps/models/auth_models.dart';
import 'package:apps/models/encrypted_vault_entry.dart';
import 'package:apps/network/dio_client.dart';
import 'package:apps/services/secure_storage_service.dart';
import 'package:apps/services/vault_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class ExpiringTokenMockServer {
  String validAccessToken = 'valid_access_token_v1';
  String validRefreshToken = 'valid_refresh_token_v1';
  int refreshCount = 0;
  final Map<String, EncryptedVaultEntry> serverVault = {};

  void expireAccessToken() {
    validAccessToken = 'valid_access_token_v2_rotated_${++refreshCount}';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  late SecureStorageService secureStorage;
  late ExpiringTokenMockServer mockServer;
  late Dio dio;
  late VaultApiService vaultApiService;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    secureStorage = SecureStorageService();
    mockServer = ExpiringTokenMockServer();

    await secureStorage.saveTokens(
      accessToken: mockServer.validAccessToken,
      refreshToken: mockServer.validRefreshToken,
    );

    // Create configured Dio with JWT auth + 401 refresh interceptors
    dio = DioClientFactory.createDio(
      secureStorage: secureStorage,
      baseUrl: 'http://mock-server.passman.internal',
      customRefreshCall: (refreshToken) async {
        if (refreshToken == mockServer.validRefreshToken) {
          mockServer.expireAccessToken();
          mockServer.validRefreshToken = 'valid_refresh_token_v2_${mockServer.refreshCount}';
          return TokenPairModel(
            accessToken: mockServer.validAccessToken,
            refreshToken: mockServer.validRefreshToken,
            tokenType: 'bearer',
            expiresIn: 600,
          );
        }
        throw DioException(
          requestOptions: RequestOptions(path: '/api/auth/refresh'),
          response: Response(
            requestOptions: RequestOptions(path: '/api/auth/refresh'),
            statusCode: 401,
          ),
        );
      },
    );

    // Mock HTTP Adapter simulating protected endpoints and 401 on expired access token
    dio.httpClientAdapter = _MockExpiringHttpAdapter(mockServer);

    vaultApiService = VaultApiService(
      dio: dio,
      baseUrl: 'http://mock-server.passman.internal',
    );
  });

  group('Task 11.5: Access Token Expiry Mid-Session → Transparent Refresh', () {
    test('Protected API call succeeds transparently when access token expires mid-session', () async {
      // 1. Initial successful call with valid token (refreshCount is 0)
      final createRes = await vaultApiService.createEntry(
        jsonEncode({'ciphertext': 'initial_data', 'iv': 'iv1', 'tag': 'tag1'}),
      );
      expect(createRes.id, isNotEmpty);
      expect(mockServer.refreshCount, equals(0));

      // 2. Mid-session: Access token expires on server
      mockServer.expireAccessToken(); // Server now expects valid_access_token_v2_rotated_1 (refreshCount = 1)

      // 3. Client attempts sync with old token stored in secure storage
      // Request initially fails with 401 -> Interceptor catches 401 -> calls customRefreshCall
      // -> saves rotated tokens in SecureStorage -> retries original request with new token
      final syncRes = await vaultApiService.syncEntries();

      // 4. Request succeeded transparently without throwing exception
      expect(syncRes.entries.length, equals(1));
      expect(mockServer.refreshCount, equals(2)); // Rotated again on transparent refresh

      // 5. Verify rotated tokens are stored in secure storage
      expect(await secureStorage.getAccessToken(), equals(mockServer.validAccessToken));
      expect(await secureStorage.getRefreshToken(), equals(mockServer.validRefreshToken));

      // 6. Subsequent requests use the fresh rotated access token directly without refresh
      final createRes2 = await vaultApiService.createEntry(
        jsonEncode({'ciphertext': 'subsequent_data', 'iv': 'iv2', 'tag': 'tag2'}),
      );
      expect(createRes2.id, isNotEmpty);
      expect(mockServer.serverVault.length, equals(2));
      expect(mockServer.refreshCount, equals(2)); // No additional refresh needed
    });
  });
}

class _MockExpiringHttpAdapter implements HttpClientAdapter {
  final ExpiringTokenMockServer server;

  _MockExpiringHttpAdapter(this.server);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final authHeader = options.headers['Authorization'] as String? ?? '';
    final token = authHeader.replaceFirst('Bearer ', '').trim();

    // Check token validity
    if (token != server.validAccessToken) {
      return ResponseBody.fromString(
        jsonEncode({'detail': 'Access token expired or invalid'}),
        401,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    // Handle /api/vault/entries
    if (options.path.contains('/api/vault/entries')) {
      final id = 'entry-${server.serverVault.length + 1}';
      final entry = EncryptedVaultEntry(
        id: id,
        userId: 'user-123',
        encryptedData: jsonEncode(options.data),
        updatedAt: DateTime.now().toUtc(),
      );
      server.serverVault[id] = entry;
      return ResponseBody.fromString(
        jsonEncode(entry.toJson()),
        201,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    // Handle /api/vault/sync
    if (options.path.contains('/api/vault/sync')) {
      return ResponseBody.fromString(
        jsonEncode({
          'entries': server.serverVault.values.map((e) => e.toJson()).toList(),
          'server_time': DateTime.now().toUtc().toIso8601String(),
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    return ResponseBody.fromString('{}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}
