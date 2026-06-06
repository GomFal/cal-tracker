import 'dart:async';

/// Manages timers for [VoiceLogViewModel].
///
/// Encapsulates the recording duration tick timer and the proposal change
/// success auto-dismissal timer, keeping timer lifecycle management out of
/// the ViewModel.
class VoiceLogTimers {
  VoiceLogTimers({
    required void Function(Duration) onRecordingDurationTick,
    required void Function() onProposalChangeSuccessExpired,
    required DateTime Function() now,
  })  : _onRecordingDurationTick = onRecordingDurationTick,
        _onProposalChangeSuccessExpired = onProposalChangeSuccessExpired,
        _now = now;

  final void Function(Duration) _onRecordingDurationTick;
  final void Function() _onProposalChangeSuccessExpired;
  final DateTime Function() _now;

  Timer? _durationTimer;
  Timer? _proposalChangeSuccessTimer;
  DateTime? _recordingStartedAt;

  /// Starts the periodic recording duration timer.
  ///
  /// Records [now] as the start reference and fires
  /// [onRecordingDurationTick] every second with the elapsed duration.
  ///
  /// If a duration timer is already active, it is stopped first.
  void startRecordingDuration(DateTime now) {
    stopRecordingDuration();
    _recordingStartedAt = now;
    _durationTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _syncRecordingDuration(),
    );
  }

  /// Stops the recording duration timer and resets the start timestamp.
  void stopRecordingDuration() {
    _durationTimer?.cancel();
    _durationTimer = null;
    _recordingStartedAt = null;
  }

  /// Whether the recording duration timer is active.
  bool get isRecording => _durationTimer?.isActive ?? false;

  /// Schedules a call to [onProposalChangeSuccessExpired] after [duration].
  ///
  /// Cancels any previously scheduled proposal change success timer.
  void showProposalChangeSuccess(Duration duration) {
    _proposalChangeSuccessTimer?.cancel();
    _proposalChangeSuccessTimer = Timer(duration, () {
      _onProposalChangeSuccessExpired();
    });
  }

  /// Cancels any pending proposal change success timer.
  void clearProposalChangeSuccess() {
    _proposalChangeSuccessTimer?.cancel();
    _proposalChangeSuccessTimer = null;
  }

  void _syncRecordingDuration() {
    final startedAt = _recordingStartedAt;
    if (startedAt == null) return;
    final elapsed = _now().difference(startedAt);
    if (elapsed.isNegative) return;
    _onRecordingDurationTick(elapsed);
  }

  /// Cancels all active timers and resets internal state.
  void dispose() {
    stopRecordingDuration();
    clearProposalChangeSuccess();
  }
}
