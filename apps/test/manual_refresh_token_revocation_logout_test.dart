import 'dart:convert';
import 'package:apps/models/auth_models.dart';
import 'package:apps/network/dio_client.dart';
import 'package:apps/network/token_refresh_interceptor.dart';
import 'package:apps/providers/auth_notifier.dart';
import 'package:apps/providers/auth_providers.dart';
import 'package:apps/providers/auth_state.dart';
import 'package:apps/screens/app_lock_gate.dart';
import 'package:apps/screens/login_signup_screen.dart';
import 'package:apps/services/auth_service.dart';
import 'package:apps/services/crypto_service.dart';
import 'package:apps/services/secure_storage_service.dart';
import 'package:apps/services/vault_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class RevokedTokenMockServer {
  bool isRefreshTokenRevoked = true;
  String currentAccessToken = 'stale_access_token_111';
  String currentRefreshToken = 'revoked_refresh_token_999';
}

class FakeTestRevocationAuthService extends Fake implements AuthService {
  @override
  Future<void> logout({String? refreshToken}) async {}
}

class _MockErrorInterceptorHandler extends Fake implements ErrorInterceptorHandler {
  final void Function(DioException err)? onNext;

  _MockErrorInterceptorHandler({this.onNext});

  @override
  void next(DioException err) {
    onNext?.call(err);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  late SecureStorageService secureStorage;
  late CryptoService cryptoService;
  late RevokedTokenMockServer mockServer;
  late Dio dio;
  late VaultApiService vaultApiService;
  late UserModel testUser;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    secureStorage = SecureStorageService();
    cryptoService = CryptoService(pbkdf2Iterations: 1000);
    mockServer = RevokedTokenMockServer();

    testUser = UserModel(
      id: 'revocation-user-123',
      email: 'revocation.test@passman.app',
      salt: cryptoService.generateSalt(16),
      createdAt: DateTime.utc(2026, 8, 30),
      updatedAt: DateTime.utc(2026, 8, 30),
    );

    await secureStorage.saveTokens(
      accessToken: mockServer.currentAccessToken,
      refreshToken: mockServer.currentRefreshToken,
    );
    await secureStorage.saveUserMetadata(
      userId: testUser.id,
      email: testUser.email,
      salt: testUser.salt,
    );
  });

  group('Task 11.6: Refresh Token Expiry/Revocation → Forced Logout', () {
    test('Revoked refresh token on 401 triggers force logout and wipes credentials', () async {
      late AuthNotifier authNotifier;

      dio = DioClientFactory.createDio(
        secureStorage: secureStorage,
        baseUrl: 'http://mock-server.passman.internal',
        onForceLogout: () async {
          await authNotifier.forceLogout();
        },
        customRefreshCall: (refreshToken) async {
          if (mockServer.isRefreshTokenRevoked) {
            throw DioException(
              requestOptions: RequestOptions(path: '/api/auth/refresh'),
              response: Response(
                requestOptions: RequestOptions(path: '/api/auth/refresh'),
                statusCode: 401,
                data: {'detail': 'Refresh token has expired or been revoked'},
              ),
              type: DioExceptionType.badResponse,
            );
          }
          return TokenPairModel(
            accessToken: 'new_token',
            refreshToken: 'new_refresh',
            tokenType: 'bearer',
            expiresIn: 600,
          );
        },
      );

      dio.httpClientAdapter = _MockRevokedHttpAdapter(mockServer);

      vaultApiService = VaultApiService(
        dio: dio,
        baseUrl: 'http://mock-server.passman.internal',
      );

      final sessionKey = await cryptoService.deriveMasterKey(
        masterPassword: 'MasterPassword123!',
        saltBase64: testUser.salt,
      );

      authNotifier = AuthNotifier(
        secureStorage: secureStorage,
        cryptoService: cryptoService,
        authService: FakeTestRevocationAuthService(),
        initialState: AuthState.authenticated(
          user: testUser,
          accessToken: mockServer.currentAccessToken,
          refreshToken: mockServer.currentRefreshToken,
          sessionKey: sessionKey,
        ),
      );

      expect(authNotifier.state.status, equals(AuthStatus.authenticated));

      // Attempt protected API request while refresh token is revoked on backend
      try {
        await vaultApiService.syncEntries();
      } catch (_) {
        // Expected DioException due to failed refresh
      }

      // Verify forced logout occurred
      expect(authNotifier.state.status, equals(AuthStatus.unauthenticated));
      expect(authNotifier.state.sessionKey, isNull);
      expect(authNotifier.state.user, isNull);

      // Verify secure storage cleared
      expect(await secureStorage.getAccessToken(), isNull);
      expect(await secureStorage.getRefreshToken(), isNull);
      expect(await secureStorage.getSessionKey(), isNull);
    });

    testWidgets('AppLockGate immediately renders LoginSignupScreen when unauthenticated', (tester) async {
      final authNotifier = AuthNotifier(
        secureStorage: secureStorage,
        cryptoService: cryptoService,
        authService: FakeTestRevocationAuthService(),
        initialState: const AuthState.unauthenticated(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith((ref) => authNotifier),
          ],
          child: const MaterialApp(
            home: AppLockGate(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(LoginSignupScreen), findsOneWidget);
    });

    test('Missing refresh token on 401 directly triggers forced logout without looping', () async {
      // Clear refresh token from storage
      await secureStorage.clearAll();
      await secureStorage.saveAccessToken('stale_access_token');

      var forceLogoutCalled = false;

      final interceptor = TokenRefreshInterceptor(
        secureStorage: secureStorage,
        dio: dio,
        onForceLogout: () async {
          forceLogoutCalled = true;
        },
      );

      final requestOptions = RequestOptions(path: '/api/vault/sync');
      final error = DioException(
        requestOptions: requestOptions,
        response: Response(
          requestOptions: requestOptions,
          statusCode: 401,
        ),
        type: DioExceptionType.badResponse,
      );

      var nextCalled = false;
      await interceptor.onError(
        error,
        _MockErrorInterceptorHandler(
          onNext: (err) {
            nextCalled = true;
          },
        ),
      );

      expect(forceLogoutCalled, isTrue);
      expect(nextCalled, isTrue);
    });
  });
}

class _MockRevokedHttpAdapter implements HttpClientAdapter {
  final RevokedTokenMockServer server;

  _MockRevokedHttpAdapter(this.server);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    // Return 401 Unauthorized for all requests to simulate expired access token
    return ResponseBody.fromString(
      jsonEncode({'detail': 'Access token is invalid or expired'}),
      401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
