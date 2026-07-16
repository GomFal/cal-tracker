import 'dart:convert';

import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:cal_tracker_mobile/data/services/secure_token_storage.dart';
import 'package:cal_tracker_mobile/generated/api/cal_tracker_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('clears stored tokens when a refresh token has been revoked', () async {
    final tokenStorage = _MemoryTokenStorage();
    await tokenStorage.write(
      const StoredTokens(
        accessToken: 'expired-access-token',
        refreshToken: 'revoked-refresh-token',
      ),
    );
    final requestedPaths = <String>[];
    final apiClient = CalTrackerApiClient(
      config: const ApiConfig(baseUrl: 'http://localhost'),
      tokenStorage: tokenStorage,
      httpClient: MockClient((request) async {
        requestedPaths.add(request.url.path);
        if (request.url.path == '/v1/auth/me') {
          return _jsonResponse({
            'error': {
              'code': 'token_expired',
              'message': 'Token expired or invalid',
            },
          }, 401);
        }
        if (request.url.path == '/v1/auth/refresh') {
          expect(jsonDecode(request.body), {
            'refreshToken': 'revoked-refresh-token',
          });
          return _jsonResponse({
            'error': {
              'code': 'invalid_refresh_token',
              'message': 'Sign in to continue.',
            },
          }, 401);
        }
        fail('Unexpected request to ${request.url.path}');
      }),
    );

    await expectLater(
      apiClient.getMe(),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having((error) => error.code, 'code', 'invalid_refresh_token'),
      ),
    );

    expect(await tokenStorage.read(), isNull);
    expect(requestedPaths, ['/v1/auth/me', '/v1/auth/refresh']);
  });
}

http.Response _jsonResponse(Map<String, Object?> body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
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
