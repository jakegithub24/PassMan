import 'package:apps/network/api_error_parser.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApiErrorParser Consistency Tests (Task 12.3 / MVP.md §5 & §6)', () {
    test('Parses standard FastAPI detail string (e.g. 400/401/403/404)', () {
      final dioException = DioException(
        requestOptions: RequestOptions(path: '/api/auth/login'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/auth/login'),
          statusCode: 401,
          data: {'detail': 'Invalid email or master password'},
        ),
        type: DioExceptionType.badResponse,
      );

      final message = ApiErrorParser.parseDioException(dioException);
      expect(message, equals('Invalid email or master password'));
    });

    test('Parses Pydantic 422 validation error detail array', () {
      final dioException = DioException(
        requestOptions: RequestOptions(path: '/api/auth/register'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/auth/register'),
          statusCode: 422,
          data: {
            'detail': [
              {
                'loc': ['body', 'email'],
                'msg': 'value is not a valid email address',
                'type': 'value_error',
              }
            ]
          },
        ),
        type: DioExceptionType.badResponse,
      );

      final message = ApiErrorParser.parseDioException(dioException);
      expect(message, equals('value is not a valid email address'));
    });

    test('Parses 429 rate limit error', () {
      final dioException = DioException(
        requestOptions: RequestOptions(path: '/api/auth/login'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/auth/login'),
          statusCode: 429,
          data: {'detail': 'Rate limit exceeded. Try again in 60 seconds.'},
        ),
        type: DioExceptionType.badResponse,
      );

      final message = ApiErrorParser.parseDioException(dioException);
      expect(message, equals('Rate limit exceeded. Try again in 60 seconds.'));
    });

    test('Falls back to HTTP status code description when response body is empty', () {
      final error404 = DioException(
        requestOptions: RequestOptions(path: '/api/vault/entries/nonexistent'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/vault/entries/nonexistent'),
          statusCode: 404,
          data: null,
        ),
        type: DioExceptionType.badResponse,
      );
      expect(
        ApiErrorParser.parseDioException(error404),
        equals('The requested resource was not found.'),
      );

      final error429 = DioException(
        requestOptions: RequestOptions(path: '/api/auth/login'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/auth/login'),
          statusCode: 429,
          data: null,
        ),
        type: DioExceptionType.badResponse,
      );
      expect(
        ApiErrorParser.parseDioException(error429),
        equals('Too many requests. Please wait a moment before trying again.'),
      );
    });

    test('Parses network timeout and connection failure exception types', () {
      final timeout = DioException(
        requestOptions: RequestOptions(path: '/api/vault/sync'),
        type: DioExceptionType.connectionTimeout,
      );
      expect(
        ApiErrorParser.parseDioException(timeout),
        equals('Connection timed out. Please check your network connection.'),
      );

      final connError = DioException(
        requestOptions: RequestOptions(path: '/api/vault/sync'),
        type: DioExceptionType.connectionError,
      );
      expect(
        ApiErrorParser.parseDioException(connError),
        equals('Unable to reach PassMan server. Check your network or try again later.'),
      );
    });

    test('Parses generic Exception and fallback strings', () {
      expect(
        ApiErrorParser.parse(Exception('Custom error message')),
        equals('Custom error message'),
      );
      expect(
        ApiErrorParser.parse('Direct string error'),
        equals('Direct string error'),
      );
      expect(
        ApiErrorParser.parse(null, fallbackMessage: 'Default'),
        equals('Default'),
      );
    });
  });
}
