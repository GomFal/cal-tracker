import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cal_tracker_mobile/data/repositories/auth_repository.dart';
import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:cal_tracker_mobile/data/services/google_sign_in_service.dart';
import 'package:cal_tracker_mobile/data/services/secure_token_storage.dart';
import 'package:cal_tracker_mobile/generated/api/cal_tracker_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'logout sends the refresh token before clearing local credentials',
    () async {
      final storage = _MemoryTokenStorage(_tokens);
      final google = _FakeGoogleSignInService();
      var requestCount = 0;
      final repository = _repository(
        storage: storage,
        google: google,
        handler: (request) async {
          requestCount += 1;
          expect(request.url.path, '/v1/auth/logout');
          expect(request.method, 'POST');
          expect(jsonDecode(request.body), {
            'refreshToken': _tokens.refreshToken,
          });
          return _jsonResponse({'ok': true});
        },
      );

      await repository.logout();

      expect(requestCount, 1);
      expect(storage.tokens, isNull);
      expect(storage.clearCount, 1);
      expect(google.signOutCount, 1);
    },
  );

  test(
    'offline backend failure still clears tokens and signs out from Google',
    () async {
      final storage = _MemoryTokenStorage(_tokens);
      final google = _FakeGoogleSignInService();
      final repository = _repository(
        storage: storage,
        google: google,
        handler: (_) async => throw const SocketException('offline'),
      );

      await expectLater(repository.logout(), completes);

      expect(storage.tokens, isNull);
      expect(google.signOutCount, 1);
      expect(await repository.restoreSession(), isNull);
    },
  );

  test(
    'Google failure does not prevent backend revocation or local cleanup',
    () async {
      final storage = _MemoryTokenStorage(_tokens);
      final google = _FakeGoogleSignInService(throwOnSignOut: true);
      var backendRevoked = false;
      final repository = _repository(
        storage: storage,
        google: google,
        handler: (_) async {
          backendRevoked = true;
          return _jsonResponse({'ok': true});
        },
      );

      await expectLater(repository.logout(), completes);

      expect(backendRevoked, isTrue);
      expect(storage.tokens, isNull);
      expect(google.signOutCount, 1);
    },
  );

  test(
    'logout timeout does not delay cleanup or retain the refresh token',
    () async {
      final response = Completer<http.Response>();
      final storage = _MemoryTokenStorage(_tokens);
      final repository = _repository(
        storage: storage,
        google: _FakeGoogleSignInService(),
        timeout: const Duration(milliseconds: 10),
        handler: (_) => response.future,
      );

      await expectLater(repository.logout(), completes);

      expect(storage.tokens, isNull);
      response.complete(_jsonResponse({'ok': true}));
    },
  );

  test('a hanging Google sign-out cannot block logout or reauthentication',
      () async {
    final googleSignOut = Completer<void>();
    final storage = _MemoryTokenStorage(_tokens);
    final repository = _repository(
      storage: storage,
      google: _FakeGoogleSignInService(signOutFuture: googleSignOut.future),
      timeout: const Duration(milliseconds: 10),
      handler: (_) async => _jsonResponse({'ok': true}),
    );

    await expectLater(repository.logout(), completes);

    expect(storage.tokens, isNull);
    googleSignOut.complete();
  });

  test('concurrent logout calls share one destructive operation', () async {
    final response = Completer<http.Response>();
    final storage = _MemoryTokenStorage(_tokens);
    final google = _FakeGoogleSignInService();
    var requestCount = 0;
    final repository = _repository(
      storage: storage,
      google: google,
      handler: (_) {
        requestCount += 1;
        return response.future;
      },
    );

    final first = repository.logout();
    final second = repository.logout();
    await Future<void>.delayed(Duration.zero);

    expect(identical(first, second), isTrue);
    expect(requestCount, 1);
    expect(storage.tokens, isNull);

    response.complete(_jsonResponse({'ok': true}));
    await Future.wait([first, second]);

    expect(storage.clearCount, 1);
    expect(google.signOutCount, 1);
  });

  test('a new login cannot write tokens until logout teardown finishes',
      () async {
    final logoutResponse = Completer<http.Response>();
    final storage = _MemoryTokenStorage(_tokens);
    var loginRequests = 0;
    final repository = _repository(
      storage: storage,
      google: _FakeGoogleSignInService(),
      handler: (request) async {
        if (request.url.path == '/v1/auth/logout') {
          return logoutResponse.future;
        }
        if (request.url.path == '/v1/auth/login') {
          loginRequests += 1;
          return _jsonResponse({
            'accessToken': 'new-access-token',
            'refreshToken': 'new-refresh-token',
            'expiresAt': '2026-07-16T12:00:00.000Z',
            'user': {
              'id': 'user-id',
              'email': 'user@example.com',
              'displayName': 'User',
              'trustedModeEnabled': false,
              'createdAt': '2026-07-16T10:00:00.000Z',
            },
          });
        }
        fail('Unexpected request to ${request.url.path}');
      },
    );

    final logout = repository.logout();
    final login = repository.login(
      email: 'user@example.com',
      password: 'new-password',
    );
    await Future<void>.delayed(Duration.zero);

    expect(loginRequests, 0);
    expect(storage.tokens, isNull);

    logoutResponse.complete(_jsonResponse({'ok': true}));
    await logout;
    final session = await login;

    expect(loginRequests, 1);
    expect(session.accessToken, 'new-access-token');
    expect(storage.tokens?.refreshToken, 'new-refresh-token');
  });
}

AuthRepository _repository({
  required _MemoryTokenStorage storage,
  required _FakeGoogleSignInService google,
  required Future<http.Response> Function(http.Request request) handler,
  Duration timeout = const Duration(seconds: 3),
}) {
  return AuthRepository(
    apiClient: CalTrackerApiClient(
      config: const ApiConfig(baseUrl: 'http://localhost'),
      tokenStorage: storage,
      httpClient: MockClient(handler),
    ),
    tokenStorage: storage,
    googleSignInService: google,
    logoutTimeout: timeout,
  );
}

http.Response _jsonResponse(Map<String, Object?> body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );
}

const _tokens = StoredTokens(
  accessToken: 'access-token',
  refreshToken: 'refresh-token-that-is-longer-than-32-characters',
);

class _MemoryTokenStorage implements TokenStorage {
  _MemoryTokenStorage(this.tokens);

  StoredTokens? tokens;
  int clearCount = 0;

  @override
  Future<void> clear() async {
    clearCount += 1;
    tokens = null;
  }

  @override
  Future<StoredTokens?> read() async => tokens;

  @override
  Future<void> write(StoredTokens tokens) async {
    this.tokens = tokens;
  }
}

class _FakeGoogleSignInService implements GoogleSignInService {
  _FakeGoogleSignInService({
    this.throwOnSignOut = false,
    this.signOutFuture,
  });

  final bool throwOnSignOut;
  final Future<void>? signOutFuture;
  int signOutCount = 0;

  @override
  Future<String?> signIn() async => null;

  @override
  Future<void> signOut() async {
    signOutCount += 1;
    if (throwOnSignOut) throw StateError('Google SDK unavailable');
    final pending = signOutFuture;
    if (pending != null) await pending;
  }
}
