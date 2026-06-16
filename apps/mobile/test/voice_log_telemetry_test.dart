import 'dart:io';

import 'package:cal_tracker_mobile/data/repositories/nutrition_repository.dart';
import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:cal_tracker_mobile/data/services/audio_recorder_service.dart';
import 'package:cal_tracker_mobile/data/services/client_metadata_provider.dart';
import 'package:cal_tracker_mobile/data/services/client_telemetry_service.dart';
import 'package:cal_tracker_mobile/data/services/secure_token_storage.dart';
import 'package:cal_tracker_mobile/generated/api/cal_tracker_api.dart';
import 'package:cal_tracker_mobile/ui/features/voice_log/view_models/voice_log_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockNutritionRepository extends Mock implements NutritionRepository {}

class MockAudioRecorderService extends Mock implements AudioRecorderService {}

class FakeFile extends Fake implements File {}

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

class _NoopTokenStorage implements TokenStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<StoredTokens?> read() async => null;

  @override
  Future<void> write(StoredTokens tokens) async {}
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

void main() {
  setUpAll(() {
    registerFallbackValue(FakeFile());
  });

  group('VoiceLogViewModel telemetry', () {
    late MockNutritionRepository mockNutritionRepository;
    late MockAudioRecorderService mockAudioRecorderService;
    late _RecordingTelemetryService telemetry;
    late VoiceLogViewModel viewModel;

    setUp(() {
      mockNutritionRepository = MockNutritionRepository();
      mockAudioRecorderService = MockAudioRecorderService();
      when(() => mockAudioRecorderService.dispose()).thenAnswer((_) async {});
      when(
        () => mockAudioRecorderService.stateStream,
      ).thenAnswer((_) => const Stream.empty());
      telemetry = _RecordingTelemetryService();
      viewModel = VoiceLogViewModel(
        nutritionRepository: mockNutritionRepository,
        audioRecorderService: mockAudioRecorderService,
        telemetryService: telemetry,
      );
    });

    tearDown(() {
      viewModel.dispose();
    });

    test('records voice_recording_start_failed on permission denied',
        () async {
      when(
        () => mockAudioRecorderService.start(),
      ).thenThrow(const RecorderException('permission_denied'));

      await viewModel.startRecording();

      expect(viewModel.state, VoiceLogState.error);
      expect(telemetry.events, hasLength(1));
      final event = telemetry.events.single;
      expect(event.eventType, 'mobile.voice_recording_start_failed');
      expect(event.flow, 'voice_meal');
      expect(event.surface, 'mobile');
      expect(event.severity, 'error');
      expect(event.status, 'failure');
      expect(event.errorCode, 'permission_denied');
      expect(event.metadata['stage'], 'start');
    });

    test('records voice_transcription_failed on transcribeAudio exception',
        () async {
      when(
        () => mockAudioRecorderService.hasPermission(),
      ).thenAnswer((_) async => true);
      when(() => mockAudioRecorderService.start()).thenAnswer((_) async {});
      when(() => mockAudioRecorderService.stop()).thenAnswer(
        (_) async => const RecordedAudio(
          path: '/tmp/test.m4a',
          mimeType: 'audio/m4a',
          sizeBytes: 1024,
        ),
      );
      when(
        () => mockNutritionRepository.transcribeAudio(any()),
      ).thenThrow(
        const ApiException(
          503,
          'STT provider down',
          code: 'stt_unavailable',
        ),
      );

      await viewModel.toggleRecording(); // start
      await viewModel.toggleRecording(); // stop -> transcribe
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(viewModel.state, VoiceLogState.error);
      // The first stop call will not produce a transcription event because
      // the call goes through _transcribe. Verify that at least one
      // transcription failure event was captured.
      final transcriptionFailures = telemetry.events
          .where((e) => e.eventType == 'mobile.voice_transcription_failed')
          .toList();
      expect(transcriptionFailures, hasLength(1));
      final event = transcriptionFailures.single;
      expect(event.errorCode, 'stt_unavailable');
      expect(event.metadata['stage'], 'transcription');
    });

    test('records voice_meal_run_failed on voice meal exception', () async {
      when(
        () => mockAudioRecorderService.hasPermission(),
      ).thenAnswer((_) async => true);
      when(() => mockAudioRecorderService.start()).thenAnswer((_) async {});
      when(() => mockAudioRecorderService.stop()).thenAnswer(
        (_) async => const RecordedAudio(
          path: '/tmp/test.m4a',
          mimeType: 'audio/m4a',
          sizeBytes: 1024,
        ),
      );
      when(() => mockNutritionRepository.logAudio(any())).thenThrow(
        const ApiException(
          502,
          'Agent provider unavailable',
          code: 'agent_provider_unavailable',
        ),
      );

      await viewModel.toggleGlobalRecording(); // start
      await viewModel.toggleGlobalRecording(); // stop -> run meal
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(viewModel.state, VoiceLogState.error);
      final mealFailures = telemetry.events
          .where((e) => e.eventType == 'mobile.voice_meal_run_failed')
          .toList();
      expect(mealFailures, hasLength(1));
      final event = mealFailures.single;
      expect(event.errorCode, 'agent_provider_unavailable');
      expect(event.metadata['stage'], 'meal_run');
    });
  });
}
