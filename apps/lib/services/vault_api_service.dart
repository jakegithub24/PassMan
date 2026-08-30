import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/encrypted_vault_entry.dart';

/// Result envelope returned by delta sync endpoint
class VaultSyncResult {
  final List<EncryptedVaultEntry> entries;
  final DateTime serverTime;

  const VaultSyncResult({
    required this.entries,
    required this.serverTime,
  });

  factory VaultSyncResult.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'] as List<dynamic>? ?? [];
    final entries = rawEntries
        .map((e) => EncryptedVaultEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    final serverTime = json['server_time'] != null
        ? DateTime.parse(json['server_time'] as String)
        : DateTime.now().toUtc();

    return VaultSyncResult(
      entries: entries,
      serverTime: serverTime,
    );
  }
}

/// Network service for CRUD & Delta-Sync vault endpoints matching backend/routers/vault.py
class VaultApiService {
  final Dio _dio;
  final String _baseUrl;

  VaultApiService({
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
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://localhost:8000';
  }

  // ---------------------------------------------------------------------------
  // 3.1 Create Vault Entry (POST /api/vault/entries)
  // ---------------------------------------------------------------------------

  /// Creates a new encrypted vault entry on the backend
  Future<EncryptedVaultEntry> createEntry(String encryptedData) async {
    try {
      final response = await _dio.post(
        '$_baseUrl/api/vault/entries',
        data: {
          'encrypted_data': encryptedData,
        },
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        return EncryptedVaultEntry.fromJson(response.data as Map<String, dynamic>);
      } else {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          message: 'Failed to create vault entry: ${response.statusCode}',
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // 3.3 Update Vault Entry (PUT /api/vault/entries/{id})
  // ---------------------------------------------------------------------------

  /// Updates an existing encrypted vault entry ciphertext
  Future<EncryptedVaultEntry> updateEntry(String entryId, String encryptedData) async {
    try {
      final response = await _dio.put(
        '$_baseUrl/api/vault/entries/$entryId',
        data: {
          'encrypted_data': encryptedData,
        },
      );

      if (response.statusCode == 200) {
        return EncryptedVaultEntry.fromJson(response.data as Map<String, dynamic>);
      } else {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          message: 'Failed to update vault entry: ${response.statusCode}',
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // 3.4 Soft Delete Vault Entry (DELETE /api/vault/entries/{id})
  // ---------------------------------------------------------------------------

  /// Soft deletes a vault entry on the backend
  Future<bool> deleteEntry(String entryId) async {
    try {
      final response = await _dio.delete('$_baseUrl/api/vault/entries/$entryId');
      return response.statusCode == 200;
    } catch (e) {
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // 3.2 Delta Sync / List Entries (GET /api/vault/sync)
  // ---------------------------------------------------------------------------

  /// Fetches vault records modified after the specified [since] timestamp
  Future<VaultSyncResult> syncEntries({
    DateTime? since,
    int limit = 500,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'limit': limit,
      };
      if (since != null) {
        queryParams['since'] = since.toUtc().toIso8601String();
      }

      final response = await _dio.get(
        '$_baseUrl/api/vault/sync',
        queryParameters: queryParams,
      );

      if (response.statusCode == 200) {
        return VaultSyncResult.fromJson(response.data as Map<String, dynamic>);
      } else {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          message: 'Failed to synchronize vault entries: ${response.statusCode}',
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Sync Status (GET /api/vault/sync/status)
  // ---------------------------------------------------------------------------

  /// Retrieves server operational status and authoritative UTC time
  Future<Map<String, dynamic>> fetchSyncStatus() async {
    try {
      final response = await _dio.get('$_baseUrl/api/vault/sync/status');
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(response.data as Map);
      } else {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          message: 'Failed to fetch sync status: ${response.statusCode}',
        );
      }
    } catch (e) {
      rethrow;
    }
  }
}
