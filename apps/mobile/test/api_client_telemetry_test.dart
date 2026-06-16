import 'dart:convert';
import 'dart:io';

import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:cal_tracker_mobile/data/services/client_metadata_provider.dart';
import 'package:cal_tracker_mobile/data/services/client_telemetry_service.dart';
import 'package:cal_tracker_mobile/data/services/secure_token_storage.dart';
import 'package:cal_tracker_mobile/generated/api/cal_tracker_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _MemoryTokenStorage implements TokenStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<StoredTokens?> read() async => null;

  @override
  Future<void> write(StoredTokens tokens) async {}
}

class _FixedMetadataProvider extends ClientMetadataProvider {
  _FixedMetadataProvider()
      : super(
          packageInfoLoader: () async => throw Exception('unused'),
        );

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

class _RecordingTelemetryService extends ClientTelemetryService {
  _RecordingTelemetryService()
      : super(
          apiConfig: const ApiConfig(baseUrl: 'http://localhost'),
          tokenStorage: _MemoryTokenStorage(),
          metadataProvider: _FixedMetadataProvider(),
        );

  final List<ClientTelemetryEvent> events = <ClientTelemetryEvent>[];

  @override
  void record(ClientTelemetryEvent event) {
    events.add(event);
  }
}

void main() {
  group('CalTrackerApiClient telemetry', () {
    test('sends X-Request-Id on JSON requests', () async {
      final seenRequestIds = <String>[];
      final client = CalTrackerApiClient(
        config: const ApiConfig(baseUrl: 'http://localhost'),
        tokenStorage: _MemoryTokenStorage(),
        metadataProvider: _FixedMetadataProvider(),
        httpClient: MockClient((request) async {
          seenRequestIds.add(request.headers['X-Request-Id'] ?? '');
          return http.Response(jsonEncode(<String, Object?>{}), 200);
        }),
      );

      await client.runAgent('100 grams rice');
      await client.runAgent('another run');

      expect(seenRequestIds, hasLength(2));
      for (final id in seenRequestIds) {
        expect(id.length, 36);
        expect(id[14], '4');
      }
      // Two independent runs should have distinct request ids.
      expect(seenRequestIds[0], isNot(seenRequestIds[1]));
    });

    test('attaches client metadata headers on JSON requests', () async {
      Map<String, String>? seenHeaders;
      final client = CalTrackerApiClient(
        config: const ApiConfig(baseUrl: 'http://localhost'),
        tokenStorage: _MemoryTokenStorage(),
        metadataProvider: _FixedMetadataProvider(),
        httpClient: MockClient((request) async {
          seenHeaders = request.headers;
          return http.Response(jsonEncode(<String, Object?>{}), 200);
        }),
      );

      await client.runAgent('100 grams rice');

      expect(seenHeaders, isNotNull);
      final headers = seenHeaders!;
      expect(headers['X-App-Version'], '0.1.9');
      expect(headers['X-App-Build'], '15');
      expect(headers['X-Client-Platform'], 'android');
      expect(headers['X-Client-Session-Id'],
          '01234567-89ab-4cde-9012-3456789abcdef');
    });

    test('sends X-Request-Id on multipart voice requests', () async {
      // The multipart path uses a dedicated IOClient that bypasses the
      // injected MockClient. We instead exercise the same header attachment
      // code by hitting a small local HTTP server. This validates that the
      // X-Request-Id, X-App-Version, X-App-Build, X-Client-Platform, and
      // X-Client-Session-Id headers are sent on multipart requests too.
      // Create a small temp file so the real MultipartFile.fromPath can
      // stream it through the server.
      final tempDir = await Directory.systemTemp.createTemp('api_telemetry_');
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      final audioFile = File('${tempDir.path}/sample.m4a');
      await audioFile.writeAsBytes(List<int>.filled(16, 0));

      Map<String, String>? seenHeaders;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });
      server.listen((request) async {
        final flat = <String, String>{};
        request.headers.forEach((name, values) {
          if (values.isNotEmpty) flat[name] = values.first;
        });
        seenHeaders = flat;
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'transcript': '100 grams rice',
            'provider': 'test',
            'model': 'test',
            'traceId': 'srv-trace-multi',
            'result': <String, Object?>{
              'kind': 'proposal',
              'message': '',
              'proposal': <String, Object?>{
                'id': 'p1',
                'title': 'Rice',
                'confidence': 0.9,
                'requiresConfirmation': true,
                'trustedAutoCommitEligible': false,
                'nutrition': <String, Object?>{
                  'calories': 100,
                  'proteinGrams': 1,
                  'carbsGrams': 1,
                  'fatGrams': 1,
                },
                'items': <Object?>[],
              },
            },
          }),
        );
        await request.response.close();
      });

      final client = CalTrackerApiClient(
        config: ApiConfig(baseUrl: 'http://${server.address.host}:${server.port}'),
        tokenStorage: _MemoryTokenStorage(),
        metadataProvider: _FixedMetadataProvider(),
      );

      await client.runVoiceMeal(audioFile);

      expect(seenHeaders, isNotNull);
      final headers = seenHeaders!;
      final requestId = headers['x-request-id'] ?? headers['X-Request-Id'];
      expect(requestId, isNotNull);
      expect(requestId!.length, 36);
      expect(requestId[14], '4');
      expect(
        headers['x-app-version'] ?? headers['X-App-Version'],
        '0.1.9',
      );
      expect(
        headers['x-app-build'] ?? headers['X-App-Build'],
        '15',
      );
      expect(
        headers['x-client-platform'] ?? headers['X-Client-Platform'],
        'android',
      );
      expect(
        headers['x-client-session-id'] ?? headers['X-Client-Session-Id'],
        '01234567-89ab-4cde-9012-3456789abcdef',
      );
    });

    test(
        'emits api_request_failed telemetry with status + server traceId on 4xx',
        () async {
      final telemetry = _RecordingTelemetryService();
      final client = CalTrackerApiClient(
        config: const ApiConfig(baseUrl: 'http://localhost'),
        tokenStorage: _MemoryTokenStorage(),
        metadataProvider: _FixedMetadataProvider(),
        telemetryService: telemetry,
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode(<String, Object?>{
              'error': <String, Object?>{
                'code': 'rate_limited',
                'message': 'Too many requests',
                'traceId': 'srv-trace-1234',
              },
            }),
            429,
            headers: <String, String>{'x-request-id': 'srv-trace-1234'},
          );
        }),
      );

      await expectLater(
        client.runAgent('100 grams rice'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 429)
            .having((e) => e.code, 'code', 'rate_limited')
            .having((e) => e.traceId, 'traceId', 'srv-trace-1234')),
      );

      expect(telemetry.events, hasLength(1));
      final event = telemetry.events.single;
      expect(event.eventType, 'mobile.api_request_failed');
      expect(event.severity, 'warning');
      expect(event.status, 'failure');
      expect(event.route, '/v1/agent/runs');
      expect(event.method, 'POST');
      expect(event.errorCode, 'rate_limited');
      expect(event.traceId, 'srv-trace-1234');
      expect(event.durationMs, isNotNull);
      expect(event.metadata['status'], 429);
    });

    test('emits error severity telemetry on 5xx responses', () async {
      final telemetry = _RecordingTelemetryService();
      final client = CalTrackerApiClient(
        config: const ApiConfig(baseUrl: 'http://localhost'),
        tokenStorage: _MemoryTokenStorage(),
        metadataProvider: _FixedMetadataProvider(),
        telemetryService: telemetry,
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode(<String, Object?>{
              'error': <String, Object?>{
                'code': 'internal_error',
                'message': 'boom',
                'traceId': 'srv-trace-9999',
              },
            }),
            500,
          );
        }),
      );

      await expectLater(
        client.runAgent('100 grams rice'),
        throwsA(isA<ApiException>()),
      );

      expect(telemetry.events, hasLength(1));
      final event = telemetry.events.single;
      expect(event.severity, 'error');
      expect(event.metadata['status'], 500);
      expect(event.errorCode, 'internal_error');
    });

    test('does not emit telemetry on successful 2xx responses', () async {
      final telemetry = _RecordingTelemetryService();
      final client = CalTrackerApiClient(
        config: const ApiConfig(baseUrl: 'http://localhost'),
        tokenStorage: _MemoryTokenStorage(),
        metadataProvider: _FixedMetadataProvider(),
        telemetryService: telemetry,
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode(<String, Object?>{
              'kind': 'proposal',
              'message': 'ok',
              'proposal': <String, Object?>{
                'id': 'p1',
                'title': 'Rice',
                'confidence': 0.9,
                'requiresConfirmation': true,
                'trustedAutoCommitEligible': false,
                'nutrition': <String, Object?>{
                  'calories': 100,
                  'proteinGrams': 1,
                  'carbsGrams': 1,
                  'fatGrams': 1,
                },
                'items': <Object?>[],
              },
            }),
            200,
          );
        }),
      );

      await client.runAgent('100 grams rice');

      expect(telemetry.events, isEmpty);
    });
  });
}
