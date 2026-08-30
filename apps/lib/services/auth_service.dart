import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/auth_models.dart';
import '../network/api_config.dart';
import '../network/api_error_parser.dart';

/// Network service for authentication endpoints matching backend/routers/auth.py
class AuthService {
  final Dio _dio;
  final String _baseUrl;

  AuthService({
    Dio? dio,
    String? baseUrl,
  })  : _baseUrl = baseUrl ?? ApiConfig.defaultBaseUrl,
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl ?? ApiConfig.defaultBaseUrl,
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 10),
                headers: {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
              ),
            );

  // ---------------------------------------------------------------------------
  // Register / Signup
  // ---------------------------------------------------------------------------

  /// Registers a new user account with master password and client derivation salt
  Future<UserModel> register({
    required String email,
    required String password,
    required String salt,
  }) async {
    try {
      final response = await _dio.post(
        '$_baseUrl/api/auth/register',
        data: {
          'email': email.trim().toLowerCase(),
          'password': password,
          'salt': salt,
        },
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        return UserModel.fromJson(response.data as Map<String, dynamic>);
      } else {
        throw Exception('Registration failed with status code ${response.statusCode}');
      }
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // Login / Authenticate
  // ---------------------------------------------------------------------------

  /// Authenticates user and retrieves access/refresh token pair
  Future<TokenPairModel> login({
    required String email,
    required String password,
    String? clientType,
  }) async {
    try {
      final String platform = clientType ?? (kIsWeb ? 'web' : 'android');
      final response = await _dio.post(
        '$_baseUrl/api/auth/login',
        data: {
          'email': email.trim().toLowerCase(),
          'password': password,
          'client_type': platform,
        },
      );

      if (response.statusCode == 200) {
        return TokenPairModel.fromJson(response.data as Map<String, dynamic>);
      } else {
        throw Exception('Login failed with status code ${response.statusCode}');
      }
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // Refresh Token Rotation
  // ---------------------------------------------------------------------------

  /// Exchanges active refresh token for a fresh access token
  Future<TokenPairModel> refreshToken({
    required String refreshToken,
    String? clientType,
  }) async {
    try {
      final String platform = clientType ?? (kIsWeb ? 'web' : 'android');
      final response = await _dio.post(
        '$_baseUrl/api/auth/refresh',
        data: {
          'refresh_token': refreshToken,
          'client_type': platform,
        },
      );

      if (response.statusCode == 200) {
        return TokenPairModel.fromJson(response.data as Map<String, dynamic>);
      } else {
        throw Exception('Token refresh failed with status code ${response.statusCode}');
      }
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // Logout / Revoke Session
  // ---------------------------------------------------------------------------

  /// Revokes active refresh token session on the backend
  Future<void> logout({
    required String refreshToken,
  }) async {
    try {
      await _dio.post(
        '$_baseUrl/api/auth/logout',
        data: {
          'refresh_token': refreshToken,
        },
      );
    } on DioException catch (e) {
      // Best-effort logout (don't throw if already expired/revoked)
      if (kDebugMode) {
        print('Logout network notice: ${e.message}');
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Profile / Me
  // ---------------------------------------------------------------------------

  /// Fetches authenticated user profile
  Future<UserModel> getMe({
    required String accessToken,
  }) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/api/auth/me',
        options: Options(
          headers: {
            'Authorization': 'Bearer $accessToken',
          },
        ),
      );

      if (response.statusCode == 200) {
        return UserModel.fromJson(response.data as Map<String, dynamic>);
      } else {
        throw Exception('Failed to fetch user profile with status code ${response.statusCode}');
      }
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // Error Parsing Helper
  // ---------------------------------------------------------------------------

  Exception _handleDioError(DioException error) {
    return Exception(ApiErrorParser.parseDioException(
      error,
      fallbackMessage: 'Authentication service error',
    ));
  }
}
