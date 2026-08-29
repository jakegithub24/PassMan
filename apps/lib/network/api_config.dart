import 'package:flutter/foundation.dart';

/// Network configuration settings for PassMan API clients
class ApiConfig {
  static const Duration defaultConnectTimeout = Duration(seconds: 15);
  static const Duration defaultReceiveTimeout = Duration(seconds: 15);
  static const Duration defaultSendTimeout = Duration(seconds: 15);

  /// Default public paths that do not require an Authorization Bearer header
  static const Set<String> publicEndpoints = {
    '/api/auth/register',
    '/api/auth/login',
    '/api/auth/refresh',
    '/api/health',
    '/health',
  };

  /// Resolves the backend base URL dynamically based on client target platform
  static String get defaultBaseUrl {
    if (kIsWeb) {
      return 'http://localhost:8000';
    }
    // Android emulator host alias for loopback interface
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    // Desktop (Linux, macOS, Windows) and iOS simulator
    return 'http://localhost:8000';
  }
}
