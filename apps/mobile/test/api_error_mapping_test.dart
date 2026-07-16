import 'dart:convert';

import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:cal_tracker_mobile/data/services/audio_recorder_service.dart';
import 'package:cal_tracker_mobile/data/services/secure_token_storage.dart';
import 'package:cal_tracker_mobile/generated/api/cal_tracker_api.dart';
import 'package:cal_tracker_mobile/ui/core/user_visible_error.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('microphone denial explains settings recovery and manual fallback', () {
    expect(
      userVisibleErrorMessage(
        const RecorderException('permission_denied'),
        context: UserErrorContext.voiceRecording,
      ),
      contains('Enable it in your device settings'),
    );
    expect(
      userVisibleErrorMessage(
        const RecorderException('permission_denied'),
        context: UserErrorContext.voiceMeal,
      ),
      contains('log your meal manually'),
    );
  });

  test(
    'ApiException keeps API metadata but stringifies as safe copy',
    () async {
      final client = CalTrackerApiClient(
        config: const ApiConfig(baseUrl: 'http://localhost'),
        tokenStorage: _MemoryTokenStorage(),
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {
                'code': 'email_already_registered',
                'message': 'An account already exists for this email',
                'traceId': 'trace-secret',
              },
            }),
            409,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      final error = await _captureApiException(
        client.register(
          email: 'test@example.com',
          password: 'password123',
          displayName: 'Test User',
        ),
      );

      expect(error.statusCode, 409);
      expect(error.code, 'email_already_registered');
      expect(error.traceId, 'trace-secret');
      expect(error.toString(), 'An account already exists for this email');
      expect(error.toString(), isNot(contains('ApiException')));
      expect(error.toString(), isNot(contains('409')));
      expect(error.toString(), isNot(contains('trace-secret')));
      expect(
        userVisibleErrorMessage(error, context: UserErrorContext.authRegister),
        'An account already exists for this email. Sign in instead.',
      );
    },
  );

  test(
    'agent_provider_unavailable shows contextual message for voiceAgent context',
    () async {
      final client = CalTrackerApiClient(
        config: const ApiConfig(baseUrl: 'http://localhost'),
        tokenStorage: _MemoryTokenStorage(),
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {
                'code': 'agent_provider_unavailable',
                'message': 'An error occurred. Please, try again.',
              },
            }),
            503,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      final error = await _captureApiException(
        client.login(email: 'test@example.com', password: 'password123'),
      );

      expect(error.code, 'agent_provider_unavailable');
      expect(
        userVisibleErrorMessage(error, context: UserErrorContext.voiceAgent),
        'We could not understand that meal yet. Try adding a little more detail.',
      );
    },
  );

  test(
    'agent_provider_unavailable shows generic message for non-voice contexts',
    () async {
      final client = CalTrackerApiClient(
        config: const ApiConfig(baseUrl: 'http://localhost'),
        tokenStorage: _MemoryTokenStorage(),
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {
                'code': 'agent_provider_unavailable',
                'message': 'An error occurred. Please, try again.',
              },
            }),
            503,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      final error = await _captureApiException(
        client.login(email: 'test@example.com', password: 'password123'),
      );

      expect(error.code, 'agent_provider_unavailable');
      expect(
        userVisibleErrorMessage(error, context: UserErrorContext.generic),
        'The nutrition assistant is taking longer than expected. Try again or use a shorter description.',
      );
    },
  );

  test('non-json server errors become generic safe API exceptions', () async {
    final client = CalTrackerApiClient(
      config: const ApiConfig(baseUrl: 'http://localhost'),
      tokenStorage: _MemoryTokenStorage(),
      httpClient: MockClient(
        (_) async =>
            http.Response('<html>provider secret exploded</html>', 500),
      ),
    );

    final error = await _captureApiException(
      client.login(email: 'test@example.com', password: 'password123'),
    );

    expect(error.statusCode, 500);
    expect(error.message, 'We could not complete that request.');
    expect(error.toString(), isNot(contains('provider secret exploded')));
    expect(
      userVisibleErrorMessage(error, context: UserErrorContext.authLogin),
      'Something went wrong on our side. Try again.',
    );
  });
}

Future<ApiException> _captureApiException(Future<Object?> future) async {
  try {
    await future;
  } on ApiException catch (error) {
    return error;
  }
  fail('Expected ApiException');
}

class _MemoryTokenStorage implements TokenStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<StoredTokens?> read() async => null;

  @override
  Future<void> write(StoredTokens tokens) async {}
}
