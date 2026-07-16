import 'dart:io';

import 'package:cal_tracker_mobile/data/services/audio_recorder_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:record/record.dart';

class MockAudioRecorder extends Mock implements AudioRecorder {}

class FakeRecordConfig extends Fake implements RecordConfig {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(FakeRecordConfig());
  });

  group('AudioRecorderService', () {
    late MockAudioRecorder mockRecorder;
    late AudioRecorderService service;
    late String tempDir;

    setUp(() {
      mockRecorder = MockAudioRecorder();
      service = AudioRecorderService(
        recorder: mockRecorder,
        preferredFormat: VoiceAudioFormat.m4a,
        minimumBytes: 1,
      );
      when(() => mockRecorder.dispose()).thenAnswer((_) async {});
      when(() => mockRecorder.isEncoderSupported(AudioEncoder.aacLc))
          .thenAnswer((_) async => true);
      when(() => mockRecorder.isEncoderSupported(AudioEncoder.wav))
          .thenAnswer((_) async => true);

      // Mock path_provider platform channel
      tempDir = Directory.systemTemp.createTempSync('audio_test').path;
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getTemporaryDirectory') {
          return tempDir;
        }
        return null;
      });
    });

    tearDown(() async {
      await service.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'), null);
    });

    test('hasPermission delegates to recorder', () async {
      when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);
      final result = await service.hasPermission();
      expect(result, isTrue);
    });

    test('does not request microphone permission before recording starts',
        () async {
      verifyNever(() => mockRecorder.hasPermission());
    });

    test('start recording emits recording state and sets currentPath',
        () async {
      when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);
      when(() => mockRecorder.start(any(), path: any(named: 'path')))
          .thenAnswer((_) async {});

      final futureState = service.stateStream.first;
      await service.start();

      expect(await futureState, RecorderState.recording);
      expect(service.currentPath, isNotNull);
      expect(service.currentPath!.endsWith('.m4a'), isTrue);
    });

    test('start without permission throws RecorderException', () async {
      when(() => mockRecorder.hasPermission()).thenAnswer((_) async => false);
      when(() => mockRecorder.start(any(), path: any(named: 'path')))
          .thenAnswer((_) async {});

      expect(
        () => service.start(),
        throwsA(isA<RecorderException>()
            .having((e) => e.code, 'code', 'permission_denied')
            .having((e) => e.message, 'message', isNull)),
      );
      verifyNever(
        () => mockRecorder.start(any(), path: any(named: 'path')),
      );
    });

    test('stop returns path and clears currentPath', () async {
      when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);
      when(() => mockRecorder.start(any(), path: any(named: 'path')))
          .thenAnswer((_) async {});

      await service.start();
      expect(service.currentPath, isNotNull);
      final filePath = service.currentPath!;
      await File(filePath).writeAsString('audio');
      when(() => mockRecorder.stop()).thenAnswer((_) async => filePath);

      final audio = await service.stop();
      expect(audio?.path, filePath);
      expect(audio?.mimeType, 'audio/m4a');
      expect(service.currentPath, isNull);
    });

    test('cancel deletes file and emits idle state', () async {
      when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);
      when(() => mockRecorder.start(any(), path: any(named: 'path')))
          .thenAnswer((_) async {});
      when(() => mockRecorder.stop()).thenAnswer((_) async => null);

      await service.start();
      final filePath = service.currentPath!;

      // Create the file so we can verify deletion
      final file = File(filePath);
      await file.create(recursive: true);
      expect(await file.exists(), isTrue);

      final futureState = service.stateStream.first;
      await service.cancel();

      expect(await futureState, RecorderState.idle);
      expect(service.currentPath, isNull);
      expect(await file.exists(), isFalse);
    });
  });
}
