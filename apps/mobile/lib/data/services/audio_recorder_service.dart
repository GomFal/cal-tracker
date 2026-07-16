import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

enum RecorderState {
  idle,
  recording,
  stopping,
  error,
}

class RecorderException implements Exception {
  const RecorderException(this.code, [this.message]);

  final String code;
  final String? message;

  @override
  String toString() => message ?? 'RecorderException($code)';
}

enum VoiceAudioFormat {
  m4a,
  wav,
}

class RecordedAudio {
  const RecordedAudio({
    required this.path,
    required this.mimeType,
    required this.sizeBytes,
  });

  final String path;
  final String mimeType;
  final int sizeBytes;
}

class AudioRecorderService {
  AudioRecorderService({
    AudioRecorder? recorder,
    VoiceAudioFormat? preferredFormat,
    int minimumBytes = 512,
  })  : _recorder = recorder ?? AudioRecorder(),
        _preferredFormat = preferredFormat ?? _defaultFormat(),
        _minimumBytes = minimumBytes;

  final AudioRecorder _recorder;
  final VoiceAudioFormat _preferredFormat;
  final int _minimumBytes;
  final _stateController = StreamController<RecorderState>.broadcast();

  Stream<RecorderState> get stateStream => _stateController.stream;

  String? _currentPath;
  String? get currentPath => _currentPath;

  Future<bool> hasPermission() async => _recorder.hasPermission();

  Future<void> start() async {
    if (!await hasPermission()) {
      throw const RecorderException('permission_denied');
    }
    final dir = await getTemporaryDirectory();
    final format = await _resolveFormat();
    final path =
        '${dir.path}/voice_log_${DateTime.now().millisecondsSinceEpoch}.${_extensionFor(format)}';
    await _recorder.start(
      RecordConfig(
        encoder: _encoderFor(format),
        sampleRate: 44100,
        bitRate: 128000,
      ),
      path: path,
    );
    _currentPath = path;
    _stateController.add(RecorderState.recording);
  }

  Future<RecordedAudio?> stop() async {
    final path = await _recorder.stop();
    _currentPath = null;
    _stateController.add(RecorderState.stopping);
    if (path == null) return null;

    final file = File(path);
    if (!await file.exists()) {
      throw const RecorderException(
          'missing_file', 'No audio file was created.');
    }

    final sizeBytes = await file.length();
    if (sizeBytes < _minimumBytes) {
      throw const RecorderException(
        'empty_audio',
        'The recording was empty or too short. Try again and speak clearly after the recording indicator appears.',
      );
    }

    return RecordedAudio(
      path: path,
      mimeType: _mimeTypeFor(path),
      sizeBytes: sizeBytes,
    );
  }

  Future<void> cancel() async {
    await _recorder.stop();
    if (_currentPath != null) {
      try {
        await File(_currentPath!).delete();
      } catch (_) {
        // Ignore cleanup failures for temporary recordings.
      }
    }
    _currentPath = null;
    _stateController.add(RecorderState.idle);
  }

  Future<void> dispose() async {
    await _recorder.dispose();
    await _stateController.close();
  }

  Future<VoiceAudioFormat> _resolveFormat() async {
    if (_preferredFormat == VoiceAudioFormat.wav &&
        await _recorder.isEncoderSupported(AudioEncoder.wav)) {
      return VoiceAudioFormat.wav;
    }
    if (_preferredFormat == VoiceAudioFormat.m4a &&
        await _recorder.isEncoderSupported(AudioEncoder.aacLc)) {
      return VoiceAudioFormat.m4a;
    }
    if (await _recorder.isEncoderSupported(AudioEncoder.wav)) {
      return VoiceAudioFormat.wav;
    }
    if (await _recorder.isEncoderSupported(AudioEncoder.aacLc)) {
      return VoiceAudioFormat.m4a;
    }
    throw const RecorderException('unsupported_encoder',
        'No supported audio encoder is available on this device.');
  }

  static VoiceAudioFormat _defaultFormat() {
    const configured = String.fromEnvironment('VOICE_AUDIO_FORMAT');
    if (configured == 'm4a') return VoiceAudioFormat.m4a;
    if (configured == 'wav') return VoiceAudioFormat.wav;
    return kDebugMode ? VoiceAudioFormat.wav : VoiceAudioFormat.m4a;
  }

  static AudioEncoder _encoderFor(VoiceAudioFormat format) {
    return switch (format) {
      VoiceAudioFormat.wav => AudioEncoder.wav,
      VoiceAudioFormat.m4a => AudioEncoder.aacLc,
    };
  }

  static String _extensionFor(VoiceAudioFormat format) {
    return switch (format) {
      VoiceAudioFormat.wav => 'wav',
      VoiceAudioFormat.m4a => 'm4a',
    };
  }

  static String _mimeTypeFor(String path) {
    return path.toLowerCase().endsWith('.wav') ? 'audio/wav' : 'audio/m4a';
  }
}
