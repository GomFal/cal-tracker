import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design_system.dart';

const voiceActionRecordingPulseKey = ValueKey('voice_action_recording_pulse');
const voiceActionRecordingStaticRingKey =
    ValueKey('voice_action_recording_static_ring');
const voiceActionProcessingSpinnerKey =
    ValueKey('voice_action_processing_spinner');
const voiceActionProcessingStaticRingKey =
    ValueKey('voice_action_processing_static_ring');

class VoiceActionHaptics {
  const VoiceActionHaptics._();

  static void recordingStarted() {
    unawaited(HapticFeedback.lightImpact());
  }

  static void recordingStopped() {
    unawaited(HapticFeedback.mediumImpact());
  }
}

class VoiceActionButtonChrome extends StatefulWidget {
  const VoiceActionButtonChrome({
    super.key,
    required this.dimension,
    required this.backgroundColor,
    required this.isRecording,
    required this.child,
    this.recordingScale = 1.1,
    this.isProcessing = false,
  });

  final double dimension;
  final Color backgroundColor;
  final bool isRecording;
  final Widget child;
  final double recordingScale;
  final bool isProcessing;

  @override
  State<VoiceActionButtonChrome> createState() =>
      _VoiceActionButtonChromeState();
}

class _VoiceActionButtonChromeState extends State<VoiceActionButtonChrome>
    with SingleTickerProviderStateMixin {
  static const _scaleDuration = Duration(milliseconds: 180);
  static const _pulseDuration = Duration(milliseconds: 1250);
  static const _easeOut = Cubic(0.22, 1, 0.36, 1);

  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: _pulseDuration,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant VoiceActionButtonChrome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording != oldWidget.isRecording) {
      _syncPulse();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final scale = widget.isRecording ? widget.recordingScale : 1.0;
    final shadowColor = widget.isRecording ? palette.coral : palette.lime;
    final showShadow = Theme.of(context).brightness == Brightness.dark;

    return SizedBox.square(
      dimension: widget.dimension,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (widget.isProcessing && !widget.isRecording)
            _ProcessingSpinner(
              dimension: widget.dimension,
              reduceMotion: reduceMotion,
            ),
          if (widget.isRecording)
            _RecordingPulse(
              controller: _pulseController,
              dimension: widget.dimension,
              reduceMotion: reduceMotion,
            ),
          AnimatedScale(
            scale: scale,
            duration: reduceMotion ? Duration.zero : _scaleDuration,
            curve: _easeOut,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: widget.backgroundColor,
                shape: BoxShape.circle,
                boxShadow: showShadow
                    ? [
                        BoxShadow(
                          color: shadowColor.withValues(alpha: 0.22),
                          blurRadius: widget.isRecording ? 28 : 22,
                          offset: const Offset(0, 10),
                          spreadRadius: widget.isRecording ? 1 : 0,
                        ),
                      ]
                    : const [],
              ),
              child: SizedBox.square(
                dimension: widget.dimension,
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _syncPulse() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (widget.isRecording && !reduceMotion) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat();
      }
      return;
    }
    _pulseController.stop();
    _pulseController.value = 0;
  }
}

class _RecordingPulse extends StatelessWidget {
  const _RecordingPulse({
    required this.controller,
    required this.dimension,
    required this.reduceMotion,
  });

  final Animation<double> controller;
  final double dimension;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion) {
      return _PulseRing(
        key: voiceActionRecordingStaticRingKey,
        size: dimension * 1.22,
        opacity: 0.28,
      );
    }

    return AnimatedBuilder(
      key: voiceActionRecordingPulseKey,
      animation: controller,
      builder: (context, child) {
        final progress = controller.value;
        final easedProgress = Curves.easeOut.transform(progress);
        return _PulseRing(
          size: dimension * (1.16 + easedProgress * 0.26),
          opacity: (1 - progress) * 0.22,
        );
      },
    );
  }
}

class _PulseRing extends StatelessWidget {
  const _PulseRing({
    super.key,
    required this.size,
    required this.opacity,
  });

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return IgnorePointer(
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: palette.coral.withValues(alpha: opacity),
              width: 2,
            ),
            color: palette.coral.withValues(alpha: opacity * 0.28),
          ),
        ),
      ),
    );
  }
}

class _ProcessingSpinner extends StatelessWidget {
  const _ProcessingSpinner({
    required this.dimension,
    required this.reduceMotion,
  });

  final double dimension;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final size = dimension + 12;

    if (reduceMotion) {
      return ExcludeSemantics(
        child: IgnorePointer(
          child: SizedBox.square(
            key: voiceActionProcessingStaticRingKey,
            dimension: size,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: palette.water.withValues(alpha: 0.28),
                  width: 2.5,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return ExcludeSemantics(
      child: SizedBox.square(
        key: voiceActionProcessingSpinnerKey,
        dimension: size,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: palette.water,
          backgroundColor: Colors.transparent,
        ),
      ),
    );
  }
}
