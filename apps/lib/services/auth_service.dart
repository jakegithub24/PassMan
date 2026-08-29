import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/auth_models.dart';

/// Network service for authentication endpoints matching backend/routers/auth.py
class AuthService {
  final Dio _dio;
  final String _baseUrl;

  AuthService({
    Dio? dio,
    String? baseUrl,
  })  : _baseUrl = baseUrl ?? _getDefaultBaseUrl(),
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl ?? _getDefaultBaseUrl(),
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 10),
                headers: {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
              ),
            );

  static String _getDefaultBaseUrl() {
    if (kIsWeb) {
      return 'http://localhost:8000';
    }
    // Android emulator alias for host loopback
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://localhost:8000';
  }

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
    if (error.response?.data != null && error.response!.data is Map) {
      final data = error.response!.data as Map;
      final detail = data['detail'];
      if (detail != null) {
        if (detail is String) {
          return Exception(detail);
        } else if (detail is List && detail.isNotEmpty) {
          final first = detail.first;
          if (first is Map && first['msg'] != null) {
            return Exception(first['msg'].toString());
          }
        }
      }
      final message = data['message'];
      if (message != null) {
        return Exception(message.toString());
      }
    }

    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return Exception('Connection timed out. Please check your network connection.');
    }
    if (error.type == DioExceptionType.connectionError) {
      return Exception('Unable to reach PassMan authentication server.');
    }

    return Exception(error.message ?? 'Authentication service error');
  }
}
