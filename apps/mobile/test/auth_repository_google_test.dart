import 'dart:convert';

import 'package:cal_tracker_mobile/data/repositories/auth_repository.dart';
import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:cal_tracker_mobile/data/services/google_sign_in_service.dart';
import 'package:cal_tracker_mobile/data/services/secure_token_storage.dart';
import 'package:cal_tracker_mobile/generated/api/cal_tracker_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('loginWithGoogle exchanges an ID token and stores API tokens', () async {
    final tokenStorage = _MemoryTokenStorage();
    final apiClient = CalTrackerApiClient(
      config: const ApiConfig(baseUrl: 'http://localhost'),
      tokenStorage: tokenStorage,
      httpClient: MockClient((request) async {
        expect(request.url.path, '/v1/auth/google/login');
        expect(jsonDecode(request.body), {'idToken': 'google-id-token'});
        return http.Response(
          jsonEncode({
            'accessToken': 'access-token',
            'refreshToken': 'refresh-token',
            'expiresAt': DateTime.now().toIso8601String(),
            'user': {
              'id': 'user-id',
              'email': 'google@example.com',
              'displayName': 'Google User',
              'trustedModeEnabled': false,
              'createdAt': DateTime.now().toIso8601String(),
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final repository = AuthRepository(
      apiClient: apiClient,
      tokenStorage: tokenStorage,
      googleSignInService: _FakeGoogleSignInService('google-id-token'),
    );

    final session = await repository.loginWithGoogle();

    expect(session?.user.email, 'google@example.com');
    expect(await tokenStorage.read(), isNotNull);
    expect((await tokenStorage.read())?.accessToken, 'access-token');
  });

  test('restoreSession refreshes an expired access token before returning me',
      () async {
    final tokenStorage = _MemoryTokenStorage();
    await tokenStorage.write(
      const StoredTokens(
        accessToken: 'expired-access-token',
        refreshToken: 'valid-refresh-token',
      ),
    );
    final requestedPaths = <String>[];
    final apiClient = CalTrackerApiClient(
      config: const ApiConfig(baseUrl: 'http://localhost'),
      tokenStorage: tokenStorage,
      httpClient: MockClient((request) async {
        requestedPaths.add(request.url.path);
        if (request.url.path == '/v1/auth/me' &&
            requestedPaths.where((path) => path == '/v1/auth/me').length == 1) {
          expect(_authorizationHeader(request), 'Bearer expired-access-token');
          return _jsonResponse({
            'error': {'message': 'Token expired or invalid'},
          }, 401);
        }
        if (request.url.path == '/v1/auth/refresh') {
          expect(jsonDecode(request.body), {
            'refreshToken': 'valid-refresh-token',
          });
          return _jsonResponse({
            'accessToken': 'fresh-access-token',
            'refreshToken': 'rotated-refresh-token',
          });
        }
        if (request.url.path == '/v1/auth/me') {
          expect(_authorizationHeader(request), 'Bearer fresh-access-token');
          return _jsonResponse(_userJson);
        }
        fail('Unexpected request to ${request.url.path}');
      }),
    );
    final repository = AuthRepository(
      apiClient: apiClient,
      tokenStorage: tokenStorage,
      googleSignInService: _FakeGoogleSignInService(null),
    );

    final user = await repository.restoreSession();

    expect(user?.email, 'user@example.com');
    expect((await tokenStorage.read())?.accessToken, 'fresh-access-token');
    expect((await tokenStorage.read())?.refreshToken, 'rotated-refresh-token');
    expect(requestedPaths, [
      '/v1/auth/me',
      '/v1/auth/refresh',
      '/v1/auth/me',
    ]);
  });
}

http.Response _jsonResponse(Map<String, Object?> body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

String? _authorizationHeader(http.Request request) {
  return request.headers['authorization'] ?? request.headers['Authorization'];
}

const _userJson = {
  'id': 'user-id',
  'email': 'user@example.com',
  'displayName': 'Saved User',
  'trustedModeEnabled': false,
};

class _FakeGoogleSignInService implements GoogleSignInService {
  _FakeGoogleSignInService(this.idToken);

  final String? idToken;

  @override
  Future<String?> signIn() async => idToken;

  @override
  Future<void> signOut() async {}
}

class _MemoryTokenStorage implements TokenStorage {
  StoredTokens? _tokens;

  @override
  Future<void> clear() async {
    _tokens = null;
  }

  @override
  Future<StoredTokens?> read() async => _tokens;

  @override
  Future<void> write(StoredTokens tokens) async {
    _tokens = tokens;
  }
}
