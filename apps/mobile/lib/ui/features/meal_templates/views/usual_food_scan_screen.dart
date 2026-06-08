import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/nutrition_repository.dart';
import '../../../../l10n/app_localizations_context.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../view_models/usual_food_scan_view_model.dart';
import '../widgets/scan_viewfinder_overlay.dart';

/// Full-screen camera viewfinder for scanning a nutrition label.
///
/// Opens the camera, displays a target rectangle. On capture, pauses the live
/// preview and shows a still image so the user can confirm or retake. After
/// confirmation, runs on-device OCR on the still image, sends the extracted
/// text to the [NutritionRepository]'s existing [draftUsualFood] endpoint,
/// and pops with the resulting [UsualFoodDraft].
class UsualFoodScanScreen extends StatefulWidget {
  const UsualFoodScanScreen({super.key});

  static const route = '/templates/ingredients/scan';

  @override
  State<UsualFoodScanScreen> createState() => _UsualFoodScanScreenState();
}

class _UsualFoodScanScreenState extends State<UsualFoodScanScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  TextRecognizer? _textRecognizer;
  late UsualFoodScanViewModel _viewModel;
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

    _viewModel = _buildViewModel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _viewModel.addListener(_onViewModelChanged);
      _viewModel.init();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Only re-init when in a terminal state; otherwise the camera plugin
    // and the OS handle suspend/resume automatically.
    final phase = _viewModel.phase;
    if (phase == UsualFoodScanPhase.idle || phase == UsualFoodScanPhase.error) {
      _cameraController?.dispose();
      _cameraController = null;
      _viewModel.init();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _viewModel.removeListener(_onViewModelChanged);
    // Best-effort cleanup of any captured file left on disk.
    _viewModel.cancel();
    _viewModel.dispose();
    _textRecognizer?.close();
    _cameraController?.dispose();
    super.dispose();
  }

  UsualFoodScanViewModel _buildViewModel() {
    final factory = testViewModelFactory;
    if (factory != null) return factory(context);
    final nutritionRepository = context.read<NutritionRepository>();
    return UsualFoodScanViewModel(
      nutritionRepository: nutritionRepository,
      initializeCamera: _initializeCamera,
      takePicture: _takePicture,
      pausePreview: _pausePreview,
      resumePreview: _resumePreview,
      recognizeText: _recognizeText,
      deleteCapturedFile: _deleteCapturedFile,
      requestCameraPermission: () async {
        final status = await Permission.camera.request();
        return status.isGranted;
      },
      onDrafted: (draft) {
        if (!mounted || _popped) return;
        _popped = true;
        Navigator.of(context).pop(draft);
      },
    );
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw Exception('No camera available on this device.');
    }
    // Prefer the rear camera for scanning product labels.
    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.external,
      orElse: () => cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      ),
    );
    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await controller.initialize();
    if (!mounted) {
      controller.dispose();
      return;
    }
    setState(() => _cameraController = controller);
  }

  Future<String> _takePicture() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      throw Exception('Camera not ready.');
    }
    final xfile = await controller.takePicture();
    return xfile.path;
  }

  Future<void> _pausePreview() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPreviewPaused) return;
    await controller.pausePreview();
  }

  Future<void> _resumePreview() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    if (!controller.value.isPreviewPaused) return;
    await controller.resumePreview();
  }

  Future<String> _recognizeText(String filePath) async {
    final recognizer = _textRecognizer;
    if (recognizer == null) {
      throw Exception('Text recognizer not initialized.');
    }
    final input = InputImage.fromFilePath(filePath);
    final result = await recognizer.processImage(input);
    return result.text;
  }

  Future<void> _deleteCapturedFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // best effort
    }
  }

  void _onViewModelChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _close() async {
    if (!mounted || _popped) return;
    _popped = true;
    await _viewModel.cancel();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_viewModel.isBusy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // The user is trying to leave mid-capture. Cancel and let the
        // navigator pop on the next attempt.
        final navigator = Navigator.of(context);
        await _viewModel.cancel();
        if (!mounted) return;
        navigator.pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Bottom: live camera preview OR still image preview
              _buildCameraSurface(context),

              // Middle: viewfinder overlay (only on live preview, not on
              // still preview where the user is reviewing their shot).
              if (_viewModel.phase == UsualFoodScanPhase.ready ||
                  _viewModel.phase ==
                      UsualFoodScanPhase.requestingPermission ||
                  _viewModel.phase == UsualFoodScanPhase.capturing)
                const ScanViewfinderOverlay(),

              // Top-left: close button
              Positioned(
                top: 12,
                left: 12,
                child: _CloseButton(onPressed: _close),
              ),

              // Bottom: state panel + capture / confirm / retake buttons
              _buildBottomPanel(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraSurface(BuildContext context) {
    final phase = _viewModel.phase;
    final capturedFilePath = _viewModel.capturedFilePath;

    // Once we have a captured file, show the still image (the live preview
    // is paused by the VM at this point).
    final hasStillImage =
        capturedFilePath != null &&
        (phase == UsualFoodScanPhase.previewing ||
            phase == UsualFoodScanPhase.ocrProcessing ||
            phase == UsualFoodScanPhase.drafting ||
            phase == UsualFoodScanPhase.drafted ||
            phase == UsualFoodScanPhase.error);
    if (hasStillImage) {
      return Image.file(
        File(capturedFilePath),
        fit: BoxFit.cover,
        key: const ValueKey('usual_food_scan_still_preview'),
      );
    }

    final controller = _cameraController;
    if (controller != null && controller.value.isInitialized) {
      return CameraPreview(controller);
    }
    return const ColoredBox(color: Colors.black);
  }

  Widget _buildBottomPanel(BuildContext context) {
    final l10n = context.l10n;
    final phase = _viewModel.phase;
    final isBusy = _viewModel.isBusy;
    final errorCode = _viewModel.errorCode;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top state card with hint / progress / error
          _StateCard(
            phase: phase,
            isBusy: isBusy,
            errorCode: errorCode,
            onRetry: () => _viewModel.retry(),
            onCancel: _close,
          ),

          // Action buttons row
          if (phase == UsualFoodScanPhase.ready)
            _CaptureActionBar(
              key: const ValueKey('usual_food_scan_capture_bar'),
              onPressed: () => _viewModel.capture(),
              label: l10n.usualFoodsScanCapture,
            )
          else if (phase == UsualFoodScanPhase.previewing)
            _ConfirmRetakeBar(
              key: const ValueKey('usual_food_scan_confirm_bar'),
              onConfirm: () => _viewModel.confirmCapture(),
              onRetake: () => _viewModel.retakeCapture(),
              confirmLabel: l10n.usualFoodsScanConfirmCapture,
              retakeLabel: l10n.usualFoodsScanRetake,
            ),
        ],
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return IconButton(
      key: const ValueKey('usual_food_scan_close_button'),
      icon: const Icon(Icons.close_rounded, color: Colors.white),
      tooltip: l10n.usualFoodsScanCloseTooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(backgroundColor: Colors.black38),
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.phase,
    required this.isBusy,
    this.errorCode = UsualFoodScanError.none,
    this.onRetry,
    this.onCancel,
  });

  final UsualFoodScanPhase phase;
  final bool isBusy;
  final UsualFoodScanError errorCode;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;

  String? _localizedErrorText(AppLocalizations l10n) {
    return switch (errorCode) {
      UsualFoodScanError.cameraDenied => l10n.usualFoodsScanCameraDenied,
      UsualFoodScanError.cameraUnavailable =>
        l10n.usualFoodsScanCameraUnavailable,
      UsualFoodScanError.cameraInitFailed =>
        l10n.usualFoodsScanCameraUnavailable,
      UsualFoodScanError.ocrEmpty => l10n.usualFoodsScanOcrEmpty,
      UsualFoodScanError.ocrTooShort => l10n.usualFoodsScanOcrTooShort,
      UsualFoodScanError.ocrFailed => l10n.usualFoodsScanFailedMessage,
      UsualFoodScanError.captureFailed => l10n.usualFoodsScanFailedMessage,
      UsualFoodScanError.draftFailed => l10n.usualFoodsScanFailedMessage,
      UsualFoodScanError.unknown => l10n.usualFoodsScanFailedMessage,
      UsualFoodScanError.none => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    if (phase == UsualFoodScanPhase.error) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Card(
          key: const ValueKey('usual_food_scan_error_card'),
          color: const Color(0xffe94f5f).withValues(alpha: 0.92),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.usualFoodsScanFailedTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                if (errorCode != UsualFoodScanError.none) ...[
                  const SizedBox(height: 6),
                  Text(
                    _localizedErrorText(l10n) ?? '',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (onCancel != null)
                      TextButton(
                        key: const ValueKey('usual_food_scan_cancel_error_button'),
                        onPressed: onCancel,
                        child: Text(
                          l10n.commonCancel,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    const SizedBox(width: 12),
                    if (onRetry != null)
                      FilledButton.tonal(
                        key: const ValueKey('usual_food_scan_retry_button'),
                        onPressed: onRetry,
                        child: Text(l10n.usualFoodsScanRetake),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (phase == UsualFoodScanPhase.previewing) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Card(
          key: const ValueKey('usual_food_scan_preview_hint_card'),
          color: Colors.white.withValues(alpha: 0.92),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.crop_free_rounded,
                  color: Colors.black87,
                  size: 18,
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    l10n.usualFoodsScanPreviewHint,
                    style: const TextStyle(color: Colors.black87, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Non-error, non-preview states: hint / progress.
    String? label;
    bool showSpinner = false;

    switch (phase) {
      case UsualFoodScanPhase.idle:
      case UsualFoodScanPhase.requestingPermission:
        label = l10n.usualFoodsScanProcessingDraft;
        showSpinner = true;
        break;
      case UsualFoodScanPhase.capturing:
      case UsualFoodScanPhase.ocrProcessing:
        label = l10n.usualFoodsScanProcessingOcr;
        showSpinner = true;
        break;
      case UsualFoodScanPhase.drafting:
        label = l10n.usualFoodsScanProcessingDraft;
        showSpinner = true;
        break;
      case UsualFoodScanPhase.ready:
        label = l10n.usualFoodsScanHint;
        showSpinner = false;
        break;
      case UsualFoodScanPhase.previewing:
      case UsualFoodScanPhase.drafted:
      case UsualFoodScanPhase.error:
        // handled above
        break;
    }

    if (label == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Card(
        color: Colors.white.withValues(alpha: 0.92),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showSpinner)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.black87, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaptureActionBar extends StatelessWidget {
  const _CaptureActionBar({
    super.key,
    required this.onPressed,
    required this.label,
  });

  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton.icon(
          key: const ValueKey('usual_food_scan_capture_button'),
          onPressed: onPressed,
          icon: const Icon(Icons.camera_alt_rounded),
          label: Text(label),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
        ),
      ),
    );
  }
}

class _ConfirmRetakeBar extends StatelessWidget {
  const _ConfirmRetakeBar({
    super.key,
    required this.onConfirm,
    required this.onRetake,
    required this.confirmLabel,
    required this.retakeLabel,
  });

  final VoidCallback onConfirm;
  final VoidCallback onRetake;
  final String confirmLabel;
  final String retakeLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                key: const ValueKey('usual_food_scan_retake_button'),
                onPressed: onRetake,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(retakeLabel),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 52,
              child: FilledButton.icon(
                key: const ValueKey('usual_food_scan_confirm_button'),
                onPressed: onConfirm,
                icon: const Icon(Icons.check_rounded),
                label: Text(confirmLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Exists solely for testing — allows widget tests to inject a fake VM.
@visibleForTesting
UsualFoodScanViewModel Function(BuildContext)? testViewModelFactory;
