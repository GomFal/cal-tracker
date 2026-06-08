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
/// Opens the camera, displays a target rectangle, runs on-device OCR on the
/// captured photo, sends the extracted text to the [NutritionRepository]'s
/// existing [draftUsualFood] endpoint, and pops with the resulting
/// [UsualFoodDraft] when done.
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
  String? _capturedFilePath;

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
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.resumed) {
      // Re-initialize on return — some OSes release the camera.
      _cameraController = null;
      _viewModel.init();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _viewModel.removeListener(_onViewModelChanged);
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
      recognizeText: _recognizeText,
      requestCameraPermission: () async {
        final status = await Permission.camera.request();
        return status.isGranted;
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
    _capturedFilePath = xfile.path;
    return xfile.path;
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

  void _onViewModelChanged() {
    if (!mounted) return;
    if (_viewModel.phase == UsualFoodScanPhase.error) {
      _cleanupCapturedFile();
    }
    if (_viewModel.phase == UsualFoodScanPhase.drafted &&
        _viewModel.draft != null) {
      _cleanupCapturedFile();
      Navigator.of(context).pop(_viewModel.draft);
      return;
    }
    setState(() {});
  }

  Future<void> _cleanupCapturedFile() async {
    final path = _capturedFilePath;
    if (path == null) return;
    _capturedFilePath = null;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // best-effort
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Bottom: camera preview or placeholder
            _buildCameraPreview(),

            // Middle: viewfinder overlay
            const ScanViewfinderOverlay(),

            // Top-left: close button
            Positioned(
              top: 12,
              left: 12,
              child: _CloseButton(onPressed: () => Navigator.of(context).pop()),
            ),

            // Bottom: state panel + capture button
            _buildBottomPanel(context),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    final controller = _cameraController;
    if (controller != null && controller.value.isInitialized) {
      return CameraPreview(controller);
    }
    // Dark placeholder while camera initializes.
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
          // State card
          _StateCard(
            phase: phase,
            isBusy: isBusy,
            errorCode: errorCode,
            onRetry: () => _viewModel.retry(),
            onCancel: () => Navigator.of(context).pop(),
          ),

          // Capture button (always visible when ready)
          if (phase == UsualFoodScanPhase.ready)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  key: const ValueKey('usual_food_scan_capture_button'),
                  onPressed:
                      isBusy ? null : () => _viewModel.captureAndProcess(),
                  icon: const Icon(Icons.camera_alt_rounded),
                  label: Text(l10n.usualFoodsScanCapture),
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
      style: IconButton.styleFrom(
        backgroundColor: Colors.black38,
      ),
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
                        key: const ValueKey(
                          'usual_food_scan_cancel_error_button',
                        ),
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

    // Non-error states
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

/// Exists solely for testing — allows widget tests to inject a fake VM.
@visibleForTesting
UsualFoodScanViewModel Function(BuildContext)? testViewModelFactory;
