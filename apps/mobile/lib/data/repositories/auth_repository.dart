import '../../domain/models/auth_models.dart';
import '../../generated/api/cal_tracker_api.dart';
import '../services/google_sign_in_service.dart';
import '../services/secure_token_storage.dart';

class AuthRepository {
  AuthRepository(
      {required CalTrackerApiClient apiClient,
      required TokenStorage tokenStorage,
      GoogleSignInService? googleSignInService})
      : _apiClient = apiClient,
        _tokenStorage = tokenStorage,
        _googleSignInService =
            googleSignInService ?? GoogleSignInServiceImpl();

  final CalTrackerApiClient _apiClient;
  final TokenStorage _tokenStorage;
  final GoogleSignInService _googleSignInService;

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    await _apiClient.register(
        email: email, password: password, displayName: displayName);
  }

  Future<AuthSession> confirmEmail(String token) async {
    final json = await _apiClient.confirmEmail(token: token);
    final session = AuthSession.fromJson(json);
    await _tokenStorage.write(StoredTokens(
        accessToken: session.accessToken, refreshToken: session.refreshToken));
    return session;
  }

  Future<AuthSession> login(
      {required String email, required String password}) async {
    final json = await _apiClient.login(email: email, password: password);
    final session = AuthSession.fromJson(json);
    await _tokenStorage.write(StoredTokens(
        accessToken: session.accessToken, refreshToken: session.refreshToken));
    return session;
  }

  Future<AuthSession?> loginWithGoogle() async {
    final idToken = await _googleSignInService.signIn();
    if (idToken == null) return null;
    final json = await _apiClient.loginWithGoogle(idToken: idToken);
    final session = AuthSession.fromJson(json);
    await _tokenStorage.write(StoredTokens(
        accessToken: session.accessToken, refreshToken: session.refreshToken));
    return session;
  }

  Future<AuthUser?> restoreSession() async {
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

  Future<void> logout() async {
    await _tokenStorage.clear();
    try {
      await _googleSignInService.signOut();
    } on Object {
      // Local logout must not fail because the Google SDK has no active session.
    }
  }
}
