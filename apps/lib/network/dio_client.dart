import 'package:dio/dio.dart';
import '../models/auth_models.dart';
import '../services/secure_storage_service.dart';
import 'api_config.dart';
import 'jwt_auth_interceptor.dart';
import 'token_refresh_interceptor.dart';

/// Factory and helper class for configuring and creating Dio HTTP clients
class DioClientFactory {
  /// Creates a configured Dio client with base timeouts, default headers, JWT interceptor, and 401 refresh handler
  static Dio createDio({
    required SecureStorageService secureStorage,
    String? baseUrl,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Duration? sendTimeout,
    Future<void> Function()? onForceLogout,
    Future<void> Function(String accessToken, String refreshToken)? onTokenRefreshed,
    Future<TokenPairModel> Function(String refreshToken)? customRefreshCall,
    List<Interceptor>? additionalInterceptors,
  }) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? ApiConfig.defaultBaseUrl,
        connectTimeout: connectTimeout ?? ApiConfig.defaultConnectTimeout,
        receiveTimeout: receiveTimeout ?? ApiConfig.defaultReceiveTimeout,
        sendTimeout: sendTimeout ?? ApiConfig.defaultSendTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // 1. Attach JWT authorization interceptor
    dio.interceptors.add(
      JwtAuthInterceptor(secureStorage: secureStorage),
    );

    // 2. Attach 401 token refresh and single-retry interceptor
    dio.interceptors.add(
      TokenRefreshInterceptor(
        secureStorage: secureStorage,
        dio: dio,
        onForceLogout: onForceLogout,
        onTokenRefreshed: onTokenRefreshed,
        customRefreshCall: customRefreshCall,
      ),
    );

    // 3. Attach any additional custom interceptors
    if (additionalInterceptors != null && additionalInterceptors.isNotEmpty) {
      dio.interceptors.addAll(additionalInterceptors);
    }

    return dio;
  }
}
