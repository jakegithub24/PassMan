import 'package:flutter/foundation.dart';
import '../models/auth_models.dart';

/// Enum representing the possible authentication and vault lock states
enum AuthStatus {
  initial,
  unauthenticated,
  authenticating,
  authenticated,
  locked,
  error,
}

/// Immutable state class for Riverpod AuthState management
@immutable
class AuthState {
  final AuthStatus status;
  final UserModel? user;
  final String? accessToken;
  final String? refreshToken;
  final List<int>? sessionKey;
  final String? errorMessage;

  const AuthState({
    required this.status,
    this.user,
    this.accessToken,
    this.refreshToken,
    this.sessionKey,
    this.errorMessage,
  });

  /// Initial uninitialized state before storage check
  const AuthState.initial()
      : status = AuthStatus.initial,
        user = null,
        accessToken = null,
        refreshToken = null,
        sessionKey = null,
        errorMessage = null;

  /// Unauthenticated state (logged out or no session)
  const AuthState.unauthenticated({String? message})
      : status = AuthStatus.unauthenticated,
        user = null,
        accessToken = null,
        refreshToken = null,
        sessionKey = null,
        errorMessage = message;

  /// Authenticating state during login / signup / token verification
  const AuthState.authenticating({this.user})
      : status = AuthStatus.authenticating,
        accessToken = null,
        refreshToken = null,
        sessionKey = null,
        errorMessage = null;

  /// Fully authenticated state with active tokens and unlocked session key
  const AuthState.authenticated({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
    this.sessionKey,
  })  : status = AuthStatus.authenticated,
        errorMessage = null;

  /// Vault Locked state: User is logged in (tokens present) but encryption key is cleared
  const AuthState.locked({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
  })  : status = AuthStatus.locked,
        sessionKey = null,
        errorMessage = null;

  /// Error state
  const AuthState.error({
    required String message,
    this.user,
  })  : status = AuthStatus.error,
        accessToken = null,
        refreshToken = null,
        sessionKey = null,
        errorMessage = message;

  // ---------------------------------------------------------------------------
  // Convenience Getters
  // ---------------------------------------------------------------------------

  bool get isAuthenticated =>
      status == AuthStatus.authenticated && accessToken != null && accessToken!.isNotEmpty;

  bool get isLocked => status == AuthStatus.locked;

  bool get isAuthenticating => status == AuthStatus.authenticating;

  bool get isUnauthenticated => status == AuthStatus.unauthenticated;

  bool get isInitial => status == AuthStatus.initial;

  bool get hasSessionKey => sessionKey != null && sessionKey!.isNotEmpty;

  bool get hasError => errorMessage != null && errorMessage!.isNotEmpty;

  // ---------------------------------------------------------------------------
  // CopyWith & Equality
  // ---------------------------------------------------------------------------

  AuthState copyWith({
    AuthStatus? status,
    UserModel? user,
    String? accessToken,
    String? refreshToken,
    List<int>? sessionKey,
    String? errorMessage,
    bool clearError = false,
    bool clearSessionKey = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      sessionKey: clearSessionKey ? null : (sessionKey ?? this.sessionKey),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AuthState &&
        other.status == status &&
        other.user == user &&
        other.accessToken == accessToken &&
        other.refreshToken == refreshToken &&
        listEquals(other.sessionKey, sessionKey) &&
        other.errorMessage == errorMessage;
  }

  @override
  int get hashCode => Object.hash(
        status,
        user,
        accessToken,
        refreshToken,
        sessionKey == null ? null : Object.hashAll(sessionKey!),
        errorMessage,
      );

  @override
  String toString() {
    return 'AuthState(status: $status, user: ${user?.email}, hasToken: ${accessToken != null}, hasSessionKey: $hasSessionKey, error: $errorMessage)';
  }
}
