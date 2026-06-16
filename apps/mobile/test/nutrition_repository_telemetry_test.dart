import 'dart:async';
import 'dart:convert';

import 'package:cal_tracker_mobile/data/repositories/nutrition_repository.dart';
import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:cal_tracker_mobile/data/services/client_metadata_provider.dart';
import 'package:cal_tracker_mobile/data/services/client_telemetry_service.dart';
import 'package:cal_tracker_mobile/data/services/secure_token_storage.dart';
import 'package:cal_tracker_mobile/generated/api/cal_tracker_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

class MockCalTrackerApiClient extends Mock implements CalTrackerApiClient {}

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

class _RecordingTelemetryService extends ClientTelemetryService {
  _RecordingTelemetryService()
    : super(
        apiConfig: const ApiConfig(baseUrl: 'http://localhost'),
        tokenStorage: _NoopTokenStorage(),
        metadataProvider: _FixedMetadataProvider(),
      );

  final List<ClientTelemetryEvent> events = <ClientTelemetryEvent>[];

  @override
  void record(ClientTelemetryEvent event) {
    events.add(event);
  }
}

class _NoopTokenStorage implements TokenStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<StoredTokens?> read() async => null;

  @override
  Future<void> write(StoredTokens tokens) async {}
}

void main() {
  group('NutritionRepository food search telemetry', () {
    test('emits food_search_completed on success with result counts', () async {
      final apiClient = MockCalTrackerApiClient();
      final telemetry = _RecordingTelemetryService();
      final repository = NutritionRepository(
        apiClient: apiClient,
        telemetryService: telemetry,
      );
      when(
        () => apiClient.searchFoodsWithRequestId(query: 'rice', limit: 10),
      ).thenAnswer(
        (_) async => const ApiCallResult<Map<String, Object?>>(
          requestId: 'req-1',
          body: <String, Object?>{
            'items': [
              <String, Object?>{
                'name': 'White rice',
                'quantity': 100,
                'unit': 'g',
                'calories': 130,
                'proteinGrams': 2.7,
                'carbsGrams': 28,
                'fatGrams': 0.3,
                'source': 'open_food_facts',
              },
            ],
          },
        ),
      );

      final result = await repository.searchFoods('rice');

      expect(result.items, hasLength(1));
      expect(telemetry.events, hasLength(1));
      final event = telemetry.events.single;
      expect(event.eventType, 'mobile.food_search_completed');
      expect(event.flow, 'food_search');
      expect(event.surface, 'mobile');
      expect(event.status, 'success');
      expect(event.route, '/v1/foods/search');
      expect(event.method, 'POST');
      expect(event.traceId, 'req-1');
      expect(event.durationMs, isNotNull);
      expect(event.metadata['resultCount'], 1);
      expect(event.metadata['zeroResults'], isFalse);
      expect(event.metadata['queryLength'], 4);
    });

    test(
      'emits food_search_completed with zeroResults flag when empty',
      () async {
        final apiClient = MockCalTrackerApiClient();
        final telemetry = _RecordingTelemetryService();
        final repository = NutritionRepository(
          apiClient: apiClient,
          telemetryService: telemetry,
        );
        when(
          () => apiClient.searchFoodsWithRequestId(query: 'unknown', limit: 10),
        ).thenAnswer(
          (_) async => const ApiCallResult<Map<String, Object?>>(
            requestId: 'req-empty',
            body: <String, Object?>{'items': <Object?>[]},
          ),
        );

        final result = await repository.searchFoods('unknown');

        expect(result.items, isEmpty);
        expect(telemetry.events, hasLength(1));
        final event = telemetry.events.single;
        expect(event.eventType, 'mobile.food_search_completed');
        expect(event.metadata['resultCount'], 0);
        expect(event.metadata['zeroResults'], isTrue);
      },
    );

    test('emits food_search_failed with error code on API exception', () async {
      final apiClient = MockCalTrackerApiClient();
      final telemetry = _RecordingTelemetryService();
      final repository = NutritionRepository(
        apiClient: apiClient,
        telemetryService: telemetry,
      );
      when(
        () => apiClient.searchFoodsWithRequestId(query: 'rice', limit: 10),
      ).thenThrow(
        const ApiException(
          503,
          'Search temporarily unavailable',
          code: 'search_unavailable',
          traceId: 'srv-trace-search',
        ),
      );

      await expectLater(
        repository.searchFoods('rice'),
        throwsA(isA<ApiException>()),
      );

      expect(telemetry.events, hasLength(1));
      final event = telemetry.events.single;
      expect(event.eventType, 'mobile.food_search_failed');
      expect(event.severity, 'error');
      expect(event.status, 'failure');
      expect(event.errorCode, 'search_unavailable');
      expect(event.traceId, 'srv-trace-search');
      expect(event.durationMs, isNotNull);
    });

    test(
      'attributes concurrent food searches to their own request ids',
      () async {
        final telemetry = _RecordingTelemetryService();
        final completers = <String, Completer<http.Response>>{
          'rice': Completer<http.Response>(),
          'beans': Completer<http.Response>(),
        };
        final requestIdsByQuery = <String, String>{};
        final apiClient = CalTrackerApiClient(
          config: const ApiConfig(baseUrl: 'http://localhost'),
          tokenStorage: _NoopTokenStorage(),
          metadataProvider: _FixedMetadataProvider(),
          httpClient: MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, Object?>;
            final query = body['query'] as String;
            requestIdsByQuery[query] = request.headers['X-Request-Id']!;
            return completers[query]!.future;
          }),
        );
        final repository = NutritionRepository(
          apiClient: apiClient,
          telemetryService: telemetry,
        );

        final rice = repository.searchFoods('rice');
        final beans = repository.searchFoods('beans');
        await Future<void>.delayed(Duration.zero);

        completers['beans']!.complete(
          http.Response(
            jsonEncode(<String, Object?>{'items': <Object?>[]}),
            200,
          ),
        );
        completers['rice']!.complete(
          http.Response(
            jsonEncode(<String, Object?>{
              'items': [
                <String, Object?>{
                  'name': 'White rice',
                  'quantity': 100,
                  'unit': 'g',
                  'calories': 130,
                  'proteinGrams': 2.7,
                  'carbsGrams': 28,
                  'fatGrams': 0.3,
                  'source': 'open_food_facts',
                },
              ],
            }),
            200,
          ),
        );

        await Future.wait(<Future<FoodSearchResult>>[rice, beans]);

        expect(telemetry.events, hasLength(2));
        final byQueryLength = <int, ClientTelemetryEvent>{
          for (final event in telemetry.events)
            event.metadata['queryLength'] as int: event,
        };
        expect(byQueryLength[4]!.traceId, requestIdsByQuery['rice']);
        expect(byQueryLength[5]!.traceId, requestIdsByQuery['beans']);
        expect(requestIdsByQuery['rice'], isNot(requestIdsByQuery['beans']));
      },
    );
  });
}
