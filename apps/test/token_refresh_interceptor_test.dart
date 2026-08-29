import 'package:apps/models/auth_models.dart';
import 'package:apps/network/token_refresh_interceptor.dart';
import 'package:apps/services/secure_storage_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  late SecureStorageService secureStorage;
  late Dio dio;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    secureStorage = SecureStorageService();
    dio = Dio();
  });

  group('TokenRefreshInterceptor (Task 5.4 401 Refresh & Retry Tests)', () {
    test('401 on protected endpoint calls refresh, rotates tokens, and retries request successfully', () async {
      await secureStorage.saveTokens(
        accessToken: 'expired_access_token_111',
        refreshToken: 'valid_refresh_token_222',
      );

      var refreshCalled = false;
      var tokenRefreshedCallbackCalled = false;
      String? rotatedAccess;
      String? rotatedRefresh;

      final interceptor = TokenRefreshInterceptor(
        secureStorage: secureStorage,
        dio: dio,
        customRefreshCall: (refreshToken) async {
          refreshCalled = true;
          expect(refreshToken, 'valid_refresh_token_222');
          return TokenPairModel(
            accessToken: 'fresh_access_token_333',
            refreshToken: 'fresh_refresh_token_444',
            tokenType: 'bearer',
            expiresIn: 600,
          );
        },
        onTokenRefreshed: (acc, ref) async {
          tokenRefreshedCallbackCalled = true;
          rotatedAccess = acc;
          rotatedRefresh = ref;
        },
      );

      // Simulate a 401 error on /api/vault/sync
      final requestOptions = RequestOptions(
        path: '/api/vault/sync',
        headers: {'Authorization': 'Bearer expired_access_token_111'},
      );

      final dioError = DioException(
        requestOptions: requestOptions,
        response: Response(
          requestOptions: requestOptions,
          statusCode: 401,
        ),
        type: DioExceptionType.badResponse,
      );

      // Mock dio.fetch to return a 200 response when retried
      dio.httpClientAdapter = _MockHttpClientAdapter(
        (options) => ResponseBody.fromString(
          '{"status": "ok", "entries": []}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      );

      var resolved = false;
      Response? resolvedResponse;

      await interceptor.onError(
        dioError,
        _MockErrorInterceptorHandler(
          onResolve: (res) {
            resolved = true;
            resolvedResponse = res;
          },
        ),
      );

      // Verify refresh call succeeded
      expect(refreshCalled, isTrue);
      expect(tokenRefreshedCallbackCalled, isTrue);
      expect(rotatedAccess, 'fresh_access_token_333');
      expect(rotatedRefresh, 'fresh_refresh_token_444');

      // Verify tokens updated in secure storage
      expect(await secureStorage.getAccessToken(), 'fresh_access_token_333');
      expect(await secureStorage.getRefreshToken(), 'fresh_refresh_token_444');

      // Verify request was updated with fresh header and resolved
      expect(requestOptions.headers['Authorization'], 'Bearer fresh_access_token_333');
      expect(requestOptions.extra['has_retried_401'], isTrue);
      expect(resolved, isTrue);
      expect(resolvedResponse?.statusCode, 200);
    });

    test('401 with already retried flag triggers force logout and rejects error', () async {
      await secureStorage.saveTokens(
        accessToken: 'fresh_access_token_333',
        refreshToken: 'valid_refresh_token_222',
      );

      var forceLogoutCalled = false;
      final interceptor = TokenRefreshInterceptor(
        secureStorage: secureStorage,
        dio: dio,
        onForceLogout: () async {
          forceLogoutCalled = true;
        },
      );

      // Request marked with has_retried_401 = true
      final requestOptions = RequestOptions(
        path: '/api/vault/sync',
        extra: {'has_retried_401': true},
      );

      final dioError = DioException(
        requestOptions: requestOptions,
        response: Response(
          requestOptions: requestOptions,
          statusCode: 401,
        ),
        type: DioExceptionType.badResponse,
      );

      var nextCalled = false;
      await interceptor.onError(
        dioError,
        _MockErrorInterceptorHandler(
          onNext: (err) {
            nextCalled = true;
          },
        ),
      );

      expect(nextCalled, isTrue);
      expect(forceLogoutCalled, isTrue);
      expect(await secureStorage.getAccessToken(), isNull);
      expect(await secureStorage.getRefreshToken(), isNull);
    });

    test('401 when refresh fails triggers force logout and clears storage', () async {
      await secureStorage.saveTokens(
        accessToken: 'expired_access_token_111',
        refreshToken: 'revoked_refresh_token_999',
      );

      var forceLogoutCalled = false;
      final interceptor = TokenRefreshInterceptor(
        secureStorage: secureStorage,
        dio: dio,
        customRefreshCall: (_) async {
          throw Exception('Refresh token has expired or was revoked');
        },
        onForceLogout: () async {
          forceLogoutCalled = true;
        },
      );

      final requestOptions = RequestOptions(path: '/api/vault/entries');
      final dioError = DioException(
        requestOptions: requestOptions,
        response: Response(
          requestOptions: requestOptions,
          statusCode: 401,
        ),
        type: DioExceptionType.badResponse,
      );

      var nextCalled = false;
      await interceptor.onError(
        dioError,
        _MockErrorInterceptorHandler(
          onNext: (err) {
            nextCalled = true;
          },
        ),
      );

      expect(nextCalled, isTrue);
      expect(forceLogoutCalled, isTrue);
      expect(await secureStorage.getAccessToken(), isNull);
    });

    test('401 when refresh token is missing in storage triggers force logout', () async {
      // No tokens in storage
      var forceLogoutCalled = false;
      final interceptor = TokenRefreshInterceptor(
        secureStorage: secureStorage,
        dio: dio,
        onForceLogout: () async {
          forceLogoutCalled = true;
        },
      );

      final requestOptions = RequestOptions(path: '/api/vault/entries');
      final dioError = DioException(
        requestOptions: requestOptions,
        response: Response(
          requestOptions: requestOptions,
          statusCode: 401,
        ),
        type: DioExceptionType.badResponse,
      );

      var nextCalled = false;
      await interceptor.onError(
        dioError,
        _MockErrorInterceptorHandler(
          onNext: (err) {
            nextCalled = true;
          },
        ),
      );

      expect(nextCalled, isTrue);
      expect(forceLogoutCalled, isTrue);
    });

    test('401 on login or refresh endpoint passes through without refresh loop', () async {
      final interceptor = TokenRefreshInterceptor(
        secureStorage: secureStorage,
        dio: dio,
      );

      final requestOptions = RequestOptions(path: '/api/auth/login');
      final dioError = DioException(
        requestOptions: requestOptions,
        response: Response(
          requestOptions: requestOptions,
          statusCode: 401,
        ),
        type: DioExceptionType.badResponse,
      );

      var nextCalled = false;
      await interceptor.onError(
        dioError,
        _MockErrorInterceptorHandler(
          onNext: (err) {
            nextCalled = true;
          },
        ),
      );

      expect(nextCalled, isTrue);
      expect(requestOptions.extra['has_retried_401'], isNull);
    });

    test('non-401 errors pass through untouched', () async {
      final interceptor = TokenRefreshInterceptor(
        secureStorage: secureStorage,
        dio: dio,
      );

      final requestOptions = RequestOptions(path: '/api/vault/sync');
      final dioError = DioException(
        requestOptions: requestOptions,
        response: Response(
          requestOptions: requestOptions,
          statusCode: 500,
        ),
        type: DioExceptionType.badResponse,
      );

      var nextCalled = false;
      await interceptor.onError(
        dioError,
        _MockErrorInterceptorHandler(
          onNext: (err) {
            nextCalled = true;
          },
        ),
      );

      expect(nextCalled, isTrue);
      expect(requestOptions.extra['has_retried_401'], isNull);
    });
  });
}

class _MockErrorInterceptorHandler extends ErrorInterceptorHandler {
  final Function(Response)? onResolve;
  final Function(DioException)? onNext;

  _MockErrorInterceptorHandler({this.onResolve, this.onNext});

  @override
  void resolve(Response response) {
    onResolve?.call(response);
  }

  @override
  void next(DioException err) {
    onNext?.call(err);
  }
}

class _MockHttpClientAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions options) handler;

  _MockHttpClientAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}
