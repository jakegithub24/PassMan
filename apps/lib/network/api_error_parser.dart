import 'package:dio/dio.dart';

/// Centralized parser for converting backend (FastAPI / Pydantic / Dio) error payloads
/// into user-friendly, consistent, actionable error messages (Task 12.3 / MVP.md §5 & §6)
class ApiErrorParser {
  /// Extracts the most descriptive human-readable error message from any error
  static String parse(dynamic error, {String fallbackMessage = 'An unexpected error occurred'}) {
    if (error == null) return fallbackMessage;

    if (error is DioException) {
      return parseDioException(error, fallbackMessage: fallbackMessage);
    }

    if (error is Exception) {
      final str = error.toString();
      if (str.startsWith('Exception: ')) {
        return str.substring('Exception: '.length).trim();
      }
      return str;
    }

    if (error is String) {
      return error;
    }

    if (error is Map) {
      return parseErrorMap(error) ?? fallbackMessage;
    }

    return error.toString();
  }

  /// Parses a [DioException] inspecting response status codes, payload structures, and network error types
  static String parseDioException(DioException error, {String fallbackMessage = 'An unexpected error occurred'}) {
    // 1. Inspect response body if present
    final response = error.response;
    if (response != null) {
      if (response.data != null) {
        final data = response.data;
        if (data is Map) {
          final parsed = parseErrorMap(data);
          if (parsed != null && parsed.isNotEmpty) {
            return parsed;
          }
        } else if (data is String && data.trim().isNotEmpty) {
          // Plain text response from server or reverse proxy
          return data.trim();
        }
      }

      // 2. HTTP Status code specific human-readable messages
      switch (response.statusCode) {
        case 400:
          return 'Invalid request parameters. Please verify your input.';
        case 401:
          return 'Authentication required or session has expired.';
        case 403:
          return 'You do not have permission to access this resource.';
        case 404:
          return 'The requested resource was not found.';
        case 409:
          return 'A conflicting record already exists (e.g. email already registered).';
        case 422:
          return 'Submitted data failed validation. Please check required fields.';
        case 429:
          return 'Too many requests. Please wait a moment before trying again.';
        case 500:
          return 'Internal server error. Please try again shortly.';
        case 502:
        case 503:
        case 504:
          return 'PassMan server is currently unavailable or unreachable.';
      }
    }

    // 3. Network connection / timeout errors
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timed out. Please check your network connection.';
      case DioExceptionType.connectionError:
        return 'Unable to reach PassMan server. Check your network or try again later.';
      case DioExceptionType.cancel:
        return 'Request was cancelled.';
      case DioExceptionType.badCertificate:
        return 'Security certificate verification failed.';
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
      default:
        break;
    }

    return error.message?.trim().isNotEmpty == true ? error.message!.trim() : fallbackMessage;
  }

  /// Parses standard FastAPI / Pydantic JSON error payloads:
  /// - `{"detail": "Error string"}`
  /// - `{"detail": [{"loc": ["body", "email"], "msg": "value is not a valid email address", "type": "value_error"}]}`
  /// - `{"message": "..."}` or `{"error": "..."}`
  static String? parseErrorMap(Map map) {
    // 1. FastAPI standard "detail" field
    final detail = map['detail'];
    if (detail != null) {
      if (detail is String && detail.trim().isNotEmpty) {
        return detail.trim();
      }

      // FastAPI / Pydantic validation error list
      if (detail is List && detail.isNotEmpty) {
        final messages = <String>[];
        for (final item in detail) {
          if (item is Map) {
            final msg = item['msg']?.toString();
            final loc = item['loc'] is List ? (item['loc'] as List).join('.') : null;
            if (msg != null && msg.isNotEmpty) {
              if (loc != null && loc.isNotEmpty && !loc.contains('body')) {
                messages.add('$loc: $msg');
              } else {
                messages.add(msg);
              }
            }
          } else if (item is String && item.isNotEmpty) {
            messages.add(item);
          }
        }
        if (messages.isNotEmpty) {
          return messages.join(', ');
        }
      }
    }

    // 2. Alternative "message" / "error" / "description" fields
    for (final key in ['message', 'error', 'description', 'error_description']) {
      final val = map[key];
      if (val != null && val.toString().trim().isNotEmpty) {
        return val.toString().trim();
      }
    }

    return null;
  }
}
