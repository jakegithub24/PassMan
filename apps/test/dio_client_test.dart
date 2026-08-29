import 'package:apps/network/api_config.dart';
import 'package:apps/network/dio_client.dart';
import 'package:apps/network/jwt_auth_interceptor.dart';
import 'package:apps/services/secure_storage_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  late SecureStorageService secureStorage;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    secureStorage = SecureStorageService();
  });

  group('ApiConfig Constants & Configuration', () {
    test('verifies standard timeouts and public routes', () {
      expect(ApiConfig.defaultConnectTimeout, const Duration(seconds: 15));
      expect(ApiConfig.defaultReceiveTimeout, const Duration(seconds: 15));
      expect(ApiConfig.defaultSendTimeout, const Duration(seconds: 15));

      expect(ApiConfig.publicEndpoints.contains('/api/auth/register'), isTrue);
      expect(ApiConfig.publicEndpoints.contains('/api/auth/login'), isTrue);
      expect(ApiConfig.publicEndpoints.contains('/api/auth/refresh'), isTrue);
      expect(ApiConfig.defaultBaseUrl, isNotEmpty);
    });
  });

  group('JwtAuthInterceptor Unit & Pipeline Tests', () {
    test('attaches Bearer token to protected endpoint requests when token exists', () async {
      await secureStorage.saveTokens(
        accessToken: 'valid_jwt_access_token_123',
        refreshToken: 'valid_refresh_token_456',
      );

      final interceptor = JwtAuthInterceptor(secureStorage: secureStorage);
      final options = RequestOptions(path: '/api/vault/sync');

      var nextCalled = false;
      await interceptor.onRequest(
        options,
        _MockInterceptorHandler(
          onNext: (opt) {
            nextCalled = true;
            expect(opt.headers['Authorization'], 'Bearer valid_jwt_access_token_123');
          },
        ),
      );

      expect(nextCalled, isTrue);
    });

    test('skips attaching Bearer token for public endpoints', () async {
      await secureStorage.saveTokens(
        accessToken: 'valid_jwt_access_token_123',
        refreshToken: 'valid_refresh_token_456',
      );

      final interceptor = JwtAuthInterceptor(secureStorage: secureStorage);
      final options = RequestOptions(path: '/api/auth/login');

      var nextCalled = false;
      await interceptor.onRequest(
        options,
        _MockInterceptorHandler(
          onNext: (opt) {
            nextCalled = true;
            expect(opt.headers.containsKey('Authorization'), isFalse);
          },
        ),
      );

      expect(nextCalled, isTrue);
    });

    test('preserves existing Authorization header if already explicitly provided', () async {
      await secureStorage.saveTokens(
        accessToken: 'storage_token_123',
        refreshToken: 'storage_refresh_456',
      );

      final interceptor = JwtAuthInterceptor(secureStorage: secureStorage);
      final options = RequestOptions(
        path: '/api/vault/entries',
        headers: {'Authorization': 'Bearer custom_explicit_token_789'},
      );

      var nextCalled = false;
      await interceptor.onRequest(
        options,
        _MockInterceptorHandler(
          onNext: (opt) {
            nextCalled = true;
            expect(opt.headers['Authorization'], 'Bearer custom_explicit_token_789');
          },
        ),
      );

      expect(nextCalled, isTrue);
    });

    test('proceeds gracefully without Authorization header when storage is empty', () async {
      final interceptor = JwtAuthInterceptor(secureStorage: secureStorage);
      final options = RequestOptions(path: '/api/vault/entries');

      var nextCalled = false;
      await interceptor.onRequest(
        options,
        _MockInterceptorHandler(
          onNext: (opt) {
            nextCalled = true;
            expect(opt.headers.containsKey('Authorization'), isFalse);
          },
        ),
      );

      expect(nextCalled, isTrue);
    });
  });

  group('DioClientFactory Integration Tests', () {
    test('createDio sets default base options and registers JwtAuthInterceptor', () {
      final dio = DioClientFactory.createDio(
        secureStorage: secureStorage,
        baseUrl: 'http://test-server:8000',
      );

      expect(dio.options.baseUrl, 'http://test-server:8000');
      expect(dio.options.connectTimeout, const Duration(seconds: 15));
      expect(dio.options.receiveTimeout, const Duration(seconds: 15));
      expect(dio.options.sendTimeout, const Duration(seconds: 15));
      expect(dio.options.headers['Content-Type'], 'application/json');
      expect(dio.options.headers['Accept'], 'application/json');

      expect(
        dio.interceptors.any((i) => i is JwtAuthInterceptor),
        isTrue,
      );
    });

    test('createDio attaches additional custom interceptors if provided', () {
      final customInterceptor = InterceptorsWrapper();
      final dio = DioClientFactory.createDio(
        secureStorage: secureStorage,
        additionalInterceptors: [customInterceptor],
      );

      expect(dio.interceptors.contains(customInterceptor), isTrue);
    });
  });
}

class _MockInterceptorHandler extends RequestInterceptorHandler {
  final Function(RequestOptions) onNext;

  _MockInterceptorHandler({required this.onNext});

  @override
  void next(RequestOptions requestOptions) {
    onNext(requestOptions);
  }
}
