import 'package:dio/dio.dart';
import '../services/secure_storage_service.dart';
import 'api_config.dart';

/// Interceptor that attaches the Bearer JWT access token to outgoing API requests
class JwtAuthInterceptor extends QueuedInterceptor {
  final SecureStorageService secureStorage;
  final Set<String> publicEndpoints;

  JwtAuthInterceptor({
    required this.secureStorage,
    Set<String>? publicEndpoints,
  }) : publicEndpoints = publicEndpoints ?? ApiConfig.publicEndpoints;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // 1. Skip attaching token if Authorization header is already explicitly provided
    if (options.headers.containsKey('Authorization') &&
        options.headers['Authorization'] != null &&
        options.headers['Authorization'].toString().isNotEmpty) {
      return handler.next(options);
    }

    // 2. Skip attaching token for known public/unauthenticated endpoints
    final String requestPath = options.path;
    final bool isPublic = publicEndpoints.any(
      (publicPath) => requestPath.endsWith(publicPath) || requestPath == publicPath,
    );

    if (isPublic) {
      return handler.next(options);
    }

    // 3. Fetch token from secure storage and attach Bearer header
    try {
      final String? accessToken = await secureStorage.getAccessToken();
      if (accessToken != null && accessToken.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $accessToken';
      }
    } catch (_) {
      // Continue request without token if secure storage read fails
    }

    return handler.next(options);
  }
}
