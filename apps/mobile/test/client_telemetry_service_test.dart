import 'dart:convert';

import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:cal_tracker_mobile/data/services/client_metadata_provider.dart';
import 'package:cal_tracker_mobile/data/services/client_telemetry_service.dart';
import 'package:cal_tracker_mobile/data/services/secure_token_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _MemoryTokenStorage implements TokenStorage {
  _MemoryTokenStorage([this._tokens]);

  StoredTokens? _tokens;

  @override
  Future<StoredTokens?> read() async => _tokens;

  @override
  Future<void> write(StoredTokens tokens) async {
    _tokens = tokens;
  }

  @override
  Future<void> clear() async {
    _tokens = null;
  }
}

class _FixedMetadataProvider extends ClientMetadataProvider {
  _FixedMetadataProvider()
    : super(packageInfoLoader: () async => throw Exception('unused'));

  @override
  Future<ClientMetadata> read() async {
    return const ClientMetadata(
      appVersion: '0.1.9',
      appBuild: '15',
      platform: 'android',
      sessionId: '01234567-89ab-4cde-9012-3456789abcdef',
    );
  }
}

class _CapturingSender {
  final List<Map<String, Object?>> sentBodies = [];
  final List<Uri> sentUris = [];
  final List<Map<String, String>?> sentHeaders = [];
  http.Response Function(Uri, {Map<String, String>? headers, Object? body})?
  responder;

  Future<http.Response> send(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    sentUris.add(uri);
    sentHeaders.add(headers);
    if (body is String) {
      sentBodies.add(jsonDecode(body) as Map<String, Object?>);
    }
    final fn = responder;
    if (fn != null) return fn(uri, headers: headers, body: body);
    return http.Response('{}', 200);
  }
}

void main() {
  group('ClientTelemetryService', () {
    test('flush posts queued events to /v1/telemetry/client-events', () async {
      final sender = _CapturingSender();
      final service = ClientTelemetryService(
        apiConfig: const ApiConfig(baseUrl: 'http://api.example.com'),
        tokenStorage: _MemoryTokenStorage(
          const StoredTokens(accessToken: 'access', refreshToken: 'refresh'),
        ),
        metadataProvider: _FixedMetadataProvider(),
        httpSender: sender.send,
      );

      service.record(
        const ClientTelemetryEvent(
          eventType: 'mobile.api_request_failed',
          flow: 'voice_meal',
          surface: 'mobile',
          severity: 'warning',
          status: 'failure',
          route: '/v1/agent/runs',
          method: 'POST',
          errorCode: 'agent_provider_unavailable',
        ),
      );
      service.record(
        const ClientTelemetryEvent(
          eventType: 'mobile.food_search_completed',
          flow: 'food_search',
          surface: 'mobile',
          severity: 'info',
          status: 'success',
          route: '/v1/foods/search',
          metadata: <String, Object?>{'resultCount': 3},
        ),
      );
      expect(service.pendingCount, 2);

      await service.flush();
      expect(service.pendingCount, 0);

      expect(sender.sentUris, hasLength(1));
      expect(
        sender.sentUris.single.toString(),
        'http://api.example.com/v1/telemetry/client-events',
      );
      final headers = sender.sentHeaders.single!;
      expect(headers['authorization'], 'Bearer access');
      expect(headers['X-App-Version'], '0.1.9');
      expect(headers['X-App-Build'], '15');
      expect(headers['X-Client-Platform'], 'android');
      expect(
        headers['X-Client-Session-Id'],
        '01234567-89ab-4cde-9012-3456789abcdef',
      );
      final body = sender.sentBodies.single;
      final events = body['events'] as List<Object?>;
      expect(events, hasLength(2));
      final first = events[0] as Map<String, Object?>;
      expect(first['eventType'], 'mobile.api_request_failed');
      expect(first['route'], '/v1/agent/runs');
      expect(first['sessionId'], '01234567-89ab-4cde-9012-3456789abcdef');
      expect(first['appVersion'], '0.1.9');
      expect(first['appBuild'], '15');
      expect(first['platform'], 'android');
      final second = events[1] as Map<String, Object?>;
      expect(second['eventType'], 'mobile.food_search_completed');
      expect(second['sessionId'], '01234567-89ab-4cde-9012-3456789abcdef');
      expect((second['metadata'] as Map<String, Object?>)['resultCount'], 3);
    });

    test('flush swallows errors so telemetry never breaks UX', () async {
      final service = ClientTelemetryService(
        apiConfig: const ApiConfig(baseUrl: 'http://api.example.com'),
        tokenStorage: _MemoryTokenStorage(),
        metadataProvider: _FixedMetadataProvider(),
        httpSender: (uri, {headers, body}) async {
          throw const SocketFailure('backend offline');
        },
      );

      service.record(
        const ClientTelemetryEvent(
          eventType: 'mobile.cache_write_failed',
          surface: 'mobile',
          severity: 'warning',
          status: 'failure',
        ),
      );

      await service.flush();
      expect(service.pendingCount, 1, reason: 'failed batch must be requeued');
    });

    test('flush requeues a batch when ingestion returns non-2xx', () async {
      final sender = _CapturingSender()
        ..responder = (uri, {headers, body}) => http.Response('', 503);
      final service = ClientTelemetryService(
        apiConfig: const ApiConfig(baseUrl: 'http://api.example.com'),
        tokenStorage: _MemoryTokenStorage(),
        metadataProvider: _FixedMetadataProvider(),
        httpSender: sender.send,
      );

      service.record(
        const ClientTelemetryEvent(
          eventType: 'mobile.cache_write_failed',
          surface: 'mobile',
          severity: 'warning',
          status: 'failure',
        ),
      );

      await service.flush();

      expect(sender.sentUris, hasLength(1));
      expect(service.pendingCount, 1);
    });

    test('requeue remains bounded by max buffer size', () async {
      final service = ClientTelemetryService(
        apiConfig: const ApiConfig(baseUrl: 'http://api.example.com'),
        tokenStorage: _MemoryTokenStorage(),
        metadataProvider: _FixedMetadataProvider(),
        maxBatchSize: 3,
        maxBufferSize: 3,
        httpSender: (uri, {headers, body}) async {
          throw const SocketFailure('backend offline');
        },
      );

      service.record(
        const ClientTelemetryEvent(
          eventType: 'a',
          surface: 'mobile',
          severity: 'info',
        ),
      );
      service.record(
        const ClientTelemetryEvent(
          eventType: 'b',
          surface: 'mobile',
          severity: 'info',
        ),
      );
      service.record(
        const ClientTelemetryEvent(
          eventType: 'c',
          surface: 'mobile',
          severity: 'info',
        ),
      );

      await service.flush();
      service.record(
        const ClientTelemetryEvent(
          eventType: 'd',
          surface: 'mobile',
          severity: 'info',
        ),
      );

      expect(service.pendingCount, 3);
    });

    test('buffer overflow drops the oldest event to bound memory', () {
      final service = ClientTelemetryService(
        apiConfig: const ApiConfig(baseUrl: 'http://api.example.com'),
        tokenStorage: _MemoryTokenStorage(),
        metadataProvider: _FixedMetadataProvider(),
        maxBufferSize: 3,
      );

      service.record(
        const ClientTelemetryEvent(
          eventType: 'a',
          surface: 'mobile',
          severity: 'info',
        ),
      );
      service.record(
        const ClientTelemetryEvent(
          eventType: 'b',
          surface: 'mobile',
          severity: 'info',
        ),
      );
      service.record(
        const ClientTelemetryEvent(
          eventType: 'c',
          surface: 'mobile',
          severity: 'info',
        ),
      );
      service.record(
        const ClientTelemetryEvent(
          eventType: 'd',
          surface: 'mobile',
          severity: 'info',
        ),
      );

      expect(service.pendingCount, 3);
    });

    test('record is a no-op after dispose', () {
      final service = ClientTelemetryService(
        apiConfig: const ApiConfig(baseUrl: 'http://api.example.com'),
        tokenStorage: _MemoryTokenStorage(),
        metadataProvider: _FixedMetadataProvider(),
      );
      service.dispose();
      service.record(
        const ClientTelemetryEvent(
          eventType: 'a',
          surface: 'mobile',
          severity: 'info',
        ),
      );
      expect(service.pendingCount, 0);
    });

    test('does not send bearer token when storage has no session', () async {
      final sender = _CapturingSender();
      final service = ClientTelemetryService(
        apiConfig: const ApiConfig(baseUrl: 'http://api.example.com'),
        tokenStorage: _MemoryTokenStorage(),
        metadataProvider: _FixedMetadataProvider(),
        httpSender: sender.send,
      );

      service.record(
        const ClientTelemetryEvent(
          eventType: 'a',
          surface: 'mobile',
          severity: 'info',
        ),
      );
      await service.flush();

      final headers = sender.sentHeaders.single!;
      expect(headers.containsKey('authorization'), isFalse);
      expect(
        headers['X-Client-Session-Id'],
        '01234567-89ab-4cde-9012-3456789abcdef',
      );
    });
  });
}

class SocketFailure implements Exception {
  const SocketFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
