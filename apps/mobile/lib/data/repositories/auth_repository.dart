import 'dart:async';

import '../../domain/models/auth_models.dart';
import '../../generated/api/cal_tracker_api.dart';
import '../services/google_sign_in_service.dart';
import '../services/secure_token_storage.dart';

class AuthRepository {
  AuthRepository({
    required CalTrackerApiClient apiClient,
    required TokenStorage tokenStorage,
    GoogleSignInService? googleSignInService,
    Duration logoutTimeout = const Duration(seconds: 3),
  })  : _apiClient = apiClient,
        _tokenStorage = tokenStorage,
        _googleSignInService = googleSignInService ?? GoogleSignInServiceImpl(),
        _logoutTimeout = logoutTimeout;

  final CalTrackerApiClient _apiClient;
  final TokenStorage _tokenStorage;
  final GoogleSignInService _googleSignInService;
  final Duration _logoutTimeout;
  Future<void>? _logoutInFlight;

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    await _waitForLogoutTeardown();
    await _apiClient.register(
      email: email,
      password: password,
      displayName: displayName,
    );
  }

  Future<AuthSession> confirmEmail(String token) async {
    await _waitForLogoutTeardown();
    final json = await _apiClient.confirmEmail(token: token);
    final session = AuthSession.fromJson(json);
    await _tokenStorage.write(
      StoredTokens(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
      ),
    );
    return session;
  }

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    await _waitForLogoutTeardown();
    final json = await _apiClient.login(email: email, password: password);
    final session = AuthSession.fromJson(json);
    await _tokenStorage.write(
      StoredTokens(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
      ),
    );
    return session;
  }

  Future<AuthSession?> loginWithGoogle() async {
    await _waitForLogoutTeardown();
    final idToken = await _googleSignInService.signIn();
    if (idToken == null) return null;
    final json = await _apiClient.loginWithGoogle(idToken: idToken);
    final session = AuthSession.fromJson(json);
    await _tokenStorage.write(
      StoredTokens(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
      ),
    );
    return session;
  }

  Future<AuthUser?> restoreSession() async {
    await _waitForLogoutTeardown();
    final tokens = await _tokenStorage.read();
    if (tokens == null) return null;
    try {
      final user = AuthUser.fromJson(await _apiClient.getMe());
      return user;
    } on Object {
      await _tokenStorage.clear();
      return null;
    }
  }

  Future<AuthUser> updateTrustedMode(bool enabled) async {
    final json = await _apiClient.updateSettings(trustedModeEnabled: enabled);
    return AuthUser.fromJson(json['user'] as Map<String, Object?>);
  }

  Future<void> logout() {
    final inFlight = _logoutInFlight;
    if (inFlight != null) return inFlight;

    final operation = _performLogout();
    _logoutInFlight = operation;
    unawaited(
      operation.then<void>(
        (_) => _clearLogoutInFlight(operation),
        onError: (_) => _clearLogoutInFlight(operation),
      ),
    );
    return operation;
  }

  Future<void> _performLogout() async {
    StoredTokens? tokens;
    try {
      tokens = await _tokenStorage.read();
    } on Object {
      // A storage read failure must not prevent the destructive local cleanup.
    }

    final remoteLogout = tokens == null
        ? Future<void>.value()
        : _revokeRemoteSession(tokens.refreshToken);
    final googleLogout = _signOutFromGoogle();

    // Both external attempts have started before the only local token copy is
    // destroyed. Neither external system can delay or prevent local cleanup.
    await _ignoreFailure(Future<void>.sync(_tokenStorage.clear));
    await Future.wait([remoteLogout, googleLogout]);
  }

  Future<void> _revokeRemoteSession(String refreshToken) async {
    try {
      await _apiClient
          .logout(refreshToken: refreshToken)
          .timeout(_logoutTimeout);
    } on Object {
      // Logout is best-effort while offline. The token is never persisted for
      // retries and no credential content is exposed through logs or errors.
    }
  }

  Future<void> _signOutFromGoogle() async {
    await _ignoreFailure(
      Future<void>.sync(_googleSignInService.signOut).timeout(_logoutTimeout),
    );
  }

  Future<void> _ignoreFailure(Future<void> operation) async {
    try {
      await operation;
    } on Object {
      // Each logout cleanup is independent and intentionally non-failing.
    }
  }

  void _clearLogoutInFlight(Future<void> operation) {
    if (identical(_logoutInFlight, operation)) {
      _logoutInFlight = null;
    }
  }

  Future<void> _waitForLogoutTeardown() async {
    final logout = _logoutInFlight;
    if (logout != null) await logout;
  }
}
