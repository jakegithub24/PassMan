import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/auth_models.dart';
import '../services/secure_storage_service.dart';
import 'api_config.dart';

/// Interceptor that handles HTTP 401 Unauthorized errors by automatically calling
/// /api/auth/refresh, updating tokens, retrying the failed request once, or forcing logout
class TokenRefreshInterceptor extends QueuedInterceptor {
  final SecureStorageService secureStorage;
  final Dio dio;
  final String? refreshUrl;
  final Future<TokenPairModel> Function(String refreshToken)? customRefreshCall;
  final Future<void> Function()? onForceLogout;
  final Future<void> Function(String accessToken, String refreshToken)? onTokenRefreshed;

  TokenRefreshInterceptor({
    required this.secureStorage,
    required this.dio,
    this.refreshUrl,
    this.customRefreshCall,
    this.onForceLogout,
    this.onTokenRefreshed,
  });

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    final requestOptions = err.requestOptions;

    // Intercept only 401 Unauthorized responses
    if (response?.statusCode == 401) {
      final String path = requestOptions.path;

      // 1. Skip refresh handling if the 401 occurred on auth endpoints themselves
      if (path.endsWith('/api/auth/refresh') ||
          path.endsWith('/api/auth/login') ||
          path.endsWith('/api/auth/register')) {
        return handler.next(err);
      }

      // 2. Check if request has already been retried once
      final bool alreadyRetried = requestOptions.extra['has_retried_401'] == true;
      if (alreadyRetried) {
        await _handleForceLogout();
        return handler.next(err);
      }

      // 3. Mark request as retried
      requestOptions.extra['has_retried_401'] = true;

      // 4. Retrieve refresh token from secure storage
      final String? refreshToken = await secureStorage.getRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        await _handleForceLogout();
        return handler.next(err);
      }

      try {
        // 5. Call refresh token endpoint to rotate access token
        final TokenPairModel tokenPair;
        if (customRefreshCall != null) {
          tokenPair = await customRefreshCall!(refreshToken);
        } else {
          final refreshDio = Dio(
            BaseOptions(
              baseUrl: requestOptions.baseUrl.isNotEmpty
                  ? requestOptions.baseUrl
                  : ApiConfig.defaultBaseUrl,
              connectTimeout: ApiConfig.defaultConnectTimeout,
              receiveTimeout: ApiConfig.defaultReceiveTimeout,
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
            ),
          );

          final platform = kIsWeb ? 'web' : 'android';
          final refreshResponse = await refreshDio.post(
            refreshUrl ?? '/api/auth/refresh',
            data: {
              'refresh_token': refreshToken,
              'client_type': platform,
            },
          );

          if (refreshResponse.statusCode == 200 && refreshResponse.data != null) {
            tokenPair = TokenPairModel.fromJson(refreshResponse.data as Map<String, dynamic>);
          } else {
            throw Exception('Token refresh rejected with status ${refreshResponse.statusCode}');
          }
        }

        // 6. Save rotated token pair securely
        await secureStorage.saveTokens(
          accessToken: tokenPair.accessToken,
          refreshToken: tokenPair.refreshToken,
        );

        // 7. Notify callback (e.g. Riverpod AuthNotifier state update)
        if (onTokenRefreshed != null) {
          await onTokenRefreshed!(tokenPair.accessToken, tokenPair.refreshToken);
        }

        // 8. Update original request headers with new access token
        requestOptions.headers['Authorization'] = 'Bearer ${tokenPair.accessToken}';

        // 9. Retry original request
        final retryResponse = await dio.fetch(requestOptions);
        return handler.resolve(retryResponse);
      } catch (refreshErr) {
        // Refresh failed (expired/revoked refresh token) -> Trigger force logout
        await _handleForceLogout();
        return handler.next(err);
      }
    }

    return handler.next(err);
  }

  Future<void> _handleForceLogout() async {
    try {
      await secureStorage.clearAll();
      if (onForceLogout != null) {
        await onForceLogout!();
      }
    } catch (_) {}
  }
}
