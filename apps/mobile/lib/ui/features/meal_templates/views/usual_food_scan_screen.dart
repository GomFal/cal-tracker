import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/nutrition_repository.dart';
import '../../../../l10n/app_localizations_context.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../view_models/usual_food_scan_view_model.dart';

enum UsualFoodScanResultMode { usualFoodDraft, ocrText }

/// Full-screen camera viewfinder for scanning a nutrition label.
///
/// Opens a simple live camera preview. On capture, pauses the live preview
/// and shows a still image so the user can select the nutrition table crop. After
/// confirmation, runs on-device OCR on the still image. It can either send the
/// extracted text to the [NutritionRepository]'s existing [draftUsualFood]
/// endpoint and pop with a [UsualFoodDraft], or pop with the raw OCR text so
/// another flow, such as agent chat, can decide how to use it.
class UsualFoodScanScreen extends StatefulWidget {
  const UsualFoodScanScreen({
    super.key,
    this.resultMode = UsualFoodScanResultMode.usualFoodDraft,
  });

  static const route = '/templates/ingredients/scan';

  final UsualFoodScanResultMode resultMode;

  @override
  State<UsualFoodScanScreen> createState() => _UsualFoodScanScreenState();
}

class _UsualFoodScanScreenState extends State<UsualFoodScanScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  TextRecognizer? _textRecognizer;
  late UsualFoodScanViewModel _viewModel;
  bool _popped = false;
  Rect? _cropRect;
  ui.Size? _capturedImageSize;
  String? _loadedCapturedImagePath;

  static const _defaultCropRect = Rect.fromLTWH(0.08, 0.24, 0.84, 0.48);

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
      prepareImageForOcr: _cropImageForOcr,
      requestCameraPermission: () async {
        final status = await Permission.camera.request();
        return status.isGranted;
      },
      draftFromRecognizedText:
          widget.resultMode == UsualFoodScanResultMode.usualFoodDraft,
      onDrafted: (draft) {
        if (!mounted || _popped) return;
        _popped = true;
        Navigator.of(context).pop(draft);
      },
      onTextExtracted: (text) {
        if (!mounted || _popped) return;
        _popped = true;
        Navigator.of(context).pop(text);
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
    await _configureStillPhotoCamera(controller);
    if (!mounted) {
      controller.dispose();
      return;
    }
    setState(() => _cameraController = controller);
  }

  Future<void> _configureStillPhotoCamera(CameraController controller) async {
    try {
      await controller.setFlashMode(FlashMode.off);
    } catch (_) {
      // Unsupported on some devices/backends.
    }
    try {
      await controller.setFocusMode(FocusMode.auto);
    } catch (_) {
      // Unsupported on some devices/backends.
    }
    try {
      await controller.setExposureMode(ExposureMode.auto);
    } catch (_) {
      // Unsupported on some devices/backends.
    }
  }

  Future<String> _takePicture() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      throw Exception('Camera not ready.');
    }
    final xfile = await controller.takePicture();
    return xfile.path;
  }

  Future<void> _loadCapturedImageSize(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() {
        _capturedImageSize = ui.Size(
          frame.image.width.toDouble(),
          frame.image.height.toDouble(),
        );
        _cropRect = _defaultCropRect;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _capturedImageSize = null;
        _cropRect = _defaultCropRect;
      });
    }
  }

  Future<String?> _cropImageForOcr(String filePath) async {
    final cropRect = _cropRect ?? _defaultCropRect;
    final bytes = await File(filePath).readAsBytes();
    final source = img.decodeImage(bytes);
    if (source == null) return null;

    final x = (cropRect.left * source.width).round().clamp(0, source.width - 1);
    final y = (cropRect.top * source.height).round().clamp(
          0,
          source.height - 1,
        );
    final width = (cropRect.width * source.width).round().clamp(
          1,
          source.width - x,
        );
    final height = (cropRect.height * source.height).round().clamp(
          1,
          source.height - y,
        );
    final cropped = img.copyCrop(
      source,
      x: x,
      y: y,
      width: width,
      height: height,
    );
    final directory = await getTemporaryDirectory();
    final output = File(
      '${directory.path}/nutrition_label_crop_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await output.writeAsBytes(img.encodeJpg(cropped, quality: 92));
    return output.path;
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
    return formatNutritionLabelOcrText(result);
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
    final capturedPath = _viewModel.capturedFilePath;
    if (capturedPath != null && capturedPath != _loadedCapturedImagePath) {
      _loadedCapturedImagePath = capturedPath;
      unawaited(_loadCapturedImageSize(capturedPath));
    }
    if (capturedPath == null && _loadedCapturedImagePath != null) {
      _loadedCapturedImagePath = null;
      _capturedImageSize = null;
      _cropRect = null;
    }
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
    final hasStillImage = capturedFilePath != null &&
        (phase == UsualFoodScanPhase.previewing ||
            phase == UsualFoodScanPhase.ocrProcessing ||
            phase == UsualFoodScanPhase.drafting ||
            phase == UsualFoodScanPhase.drafted ||
            phase == UsualFoodScanPhase.error);
    if (hasStillImage) {
      return _CropSelectionPreview(
        key: const ValueKey('usual_food_scan_still_preview'),
        filePath: capturedFilePath,
        imageSize: _capturedImageSize,
        cropRect: _cropRect ?? _defaultCropRect,
        enabled: phase == UsualFoodScanPhase.previewing,
        onChanged: (rect) => setState(() => _cropRect = rect),
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

class _CropSelectionPreview extends StatefulWidget {
  const _CropSelectionPreview({
    super.key,
    required this.filePath,
    required this.imageSize,
    required this.cropRect,
    required this.enabled,
    required this.onChanged,
  });

  final String filePath;
  final ui.Size? imageSize;
  final Rect? cropRect;
  final bool enabled;
  final ValueChanged<Rect> onChanged;

  @override
  State<_CropSelectionPreview> createState() => _CropSelectionPreviewState();
}

class _CropSelectionPreviewState extends State<_CropSelectionPreview> {
  Offset? _dragStart;

  static const _defaultCrop = Rect.fromLTWH(0.08, 0.24, 0.84, 0.48);
  static const _minimumCropSide = 0.08;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final imageRect = _imageRectFor(constraints.biggest);
        final crop = widget.cropRect ?? _defaultCrop;
        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: Colors.black,
              child: Image.file(File(widget.filePath), fit: BoxFit.contain),
            ),
            Positioned.fromRect(
              rect: imageRect,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: widget.enabled
                    ? (details) {
                        _dragStart = _normalizedPoint(
                          details.localPosition,
                          imageRect.size,
                        );
                        widget.onChanged(
                          Rect.fromLTWH(
                            _dragStart!.dx,
                            _dragStart!.dy,
                            _minimumCropSide,
                            _minimumCropSide,
                          ),
                        );
                      }
                    : null,
                onPanUpdate: widget.enabled
                    ? (details) {
                        final start = _dragStart;
                        if (start == null) return;
                        final current = _normalizedPoint(
                          details.localPosition,
                          imageRect.size,
                        );
                        widget.onChanged(_normalizedRect(start, current));
                      }
                    : null,
                onPanEnd: (_) => _dragStart = null,
                onPanCancel: () => _dragStart = null,
                child: Semantics(
                  key: const ValueKey('usual_food_scan_crop_selector'),
                  container: true,
                  enabled: widget.enabled,
                  label: context.l10n.usualFoodsScanFrameLabel,
                  hint: context.l10n.usualFoodsScanPreviewHint,
                  child: CustomPaint(
                    painter: _CropSelectionPainter(crop: crop),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Rect _imageRectFor(Size bounds) {
    final imageSize = widget.imageSize;
    if (imageSize == null || imageSize.width <= 0 || imageSize.height <= 0) {
      return Offset.zero & bounds;
    }
    final fitted = applyBoxFit(
      BoxFit.contain,
      Size(imageSize.width, imageSize.height),
      bounds,
    );
    final size = fitted.destination;
    return Rect.fromLTWH(
      (bounds.width - size.width) / 2,
      (bounds.height - size.height) / 2,
      size.width,
      size.height,
    );
  }

  Offset _normalizedPoint(Offset localPosition, Size size) {
    final dx = size.width <= 0 ? 0.0 : localPosition.dx / size.width;
    final dy = size.height <= 0 ? 0.0 : localPosition.dy / size.height;
    return Offset(dx.clamp(0, 1).toDouble(), dy.clamp(0, 1).toDouble());
  }

  Rect _normalizedRect(Offset start, Offset current) {
    final left = math.min(start.dx, current.dx);
    final top = math.min(start.dy, current.dy);
    final right = math.max(start.dx, current.dx);
    final bottom = math.max(start.dy, current.dy);
    final width = math.max(right - left, _minimumCropSide);
    final height = math.max(bottom - top, _minimumCropSide);
    return Rect.fromLTWH(
      math.min(left, 1 - width),
      math.min(top, 1 - height),
      width,
      height,
    );
  }
}

class _CropSelectionPainter extends CustomPainter {
  const _CropSelectionPainter({required this.crop});

  final Rect crop;

  @override
  void paint(Canvas canvas, Size size) {
    final cropRect = Rect.fromLTWH(
      crop.left * size.width,
      crop.top * size.height,
      crop.width * size.width,
      crop.height * size.height,
    );
    final overlay = Path()..addRect(Offset.zero & size);
    final hole = Path()
      ..addRRect(RRect.fromRectAndRadius(cropRect, const Radius.circular(14)));
    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.46);
    canvas.drawPath(
      Path.combine(PathOperation.difference, overlay, hole),
      overlayPaint,
    );

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRRect(
      RRect.fromRectAndRadius(cropRect, const Radius.circular(14)),
      borderPaint,
    );

    final accentPaint = Paint()
      ..color = const Color(0xffc8f05a)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(cropRect.deflate(5), const Radius.circular(10)),
      accentPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CropSelectionPainter oldDelegate) {
    return oldDelegate.crop != crop;
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

class _HudPanel extends StatelessWidget {
  const _HudPanel({
    super.key,
    required this.child,
    this.backgroundColor,
    this.borderColor = Colors.white24,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
  });

  final Widget child;
  final Color? backgroundColor;
  final Color borderColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundColor ?? Colors.black.withValues(alpha: 0.62),
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(padding: padding, child: child),
        ),
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
        child: _HudPanel(
          key: const ValueKey('usual_food_scan_error_card'),
          backgroundColor: Colors.black.withValues(alpha: 0.72),
          borderColor: const Color(0xffff6f80).withValues(alpha: 0.72),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Color(0xffff6f80)),
              const SizedBox(height: 8),
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
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      child: Text(l10n.commonCancel),
                    ),
                  const SizedBox(width: 12),
                  if (onRetry != null)
                    FilledButton.tonal(
                      key: const ValueKey('usual_food_scan_retry_button'),
                      onPressed: onRetry,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.14),
                        foregroundColor: Colors.white,
                      ),
                      child: Text(l10n.usualFoodsScanRetake),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (phase == UsualFoodScanPhase.previewing) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _HudPanel(
          key: const ValueKey('usual_food_scan_preview_hint_card'),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.crop_free_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  l10n.usualFoodsScanPreviewHint,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ],
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
      child: _HudPanel(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showSpinner)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ],
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
            backgroundColor: Colors.black.withValues(alpha: 0.64),
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white30),
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
                  backgroundColor: Colors.black.withValues(alpha: 0.42),
                  side: const BorderSide(color: Colors.white54),
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
                  backgroundColor: Colors.black.withValues(alpha: 0.68),
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xffc8f05a)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NutritionLabelOcrLine {
  const NutritionLabelOcrLine({required this.text, required this.boundingBox});

  final String text;
  final Rect boundingBox;

  double get centerY => boundingBox.top + boundingBox.height / 2;
  double get centerX => boundingBox.left + boundingBox.width / 2;
}

String formatNutritionLabelOcrText(RecognizedText recognizedText) {
  final lines = [
    for (final block in recognizedText.blocks)
      for (final line in block.lines)
        if (line.text.trim().isNotEmpty)
          NutritionLabelOcrLine(
            text: _normalizeOcrCell(line.text),
            boundingBox: line.boundingBox,
          ),
  ];
  return formatNutritionLabelOcrLines(lines, fallbackText: recognizedText.text);
}

@visibleForTesting
String formatNutritionLabelOcrLines(
  List<NutritionLabelOcrLine> lines, {
  String fallbackText = '',
}) {
  final cleaned = lines
      .map(
        (line) => NutritionLabelOcrLine(
          text: _normalizeOcrCell(line.text),
          boundingBox: line.boundingBox,
        ),
      )
      .where((line) => line.text.isNotEmpty)
      .toList()
    ..sort((a, b) {
      final vertical = a.centerY.compareTo(b.centerY);
      if ((a.centerY - b.centerY).abs() > _rowTolerance(a, b)) {
        return vertical;
      }
      return a.boundingBox.left.compareTo(b.boundingBox.left);
    });

  if (cleaned.isEmpty) return fallbackText.trim();

  final rows = <List<NutritionLabelOcrLine>>[];
  for (final line in cleaned) {
    if (rows.isEmpty) {
      rows.add([line]);
      continue;
    }
    final row = rows.last;
    final rowCenter = row
            .map((item) => item.centerY)
            .reduce((value, element) => value + element) /
        row.length;
    final rowHeight = row
            .map((item) => item.boundingBox.height)
            .reduce((value, element) => value + element) /
        row.length;
    final tolerance = math.max(
      8,
      math.max(rowHeight, line.boundingBox.height) * 0.72,
    );
    if ((line.centerY - rowCenter).abs() <= tolerance) {
      row.add(line);
    } else {
      rows.add([line]);
    }
  }

  final formattedRows = rows
      .map((row) {
        row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
        return _mergeRowCells(row);
      })
      .where((row) => row.isNotEmpty)
      .toList();

  final formatted = formattedRows.join('\n').trim();
  if (formatted.isEmpty) return fallbackText.trim();
  return formatted;
}

String _mergeRowCells(List<NutritionLabelOcrLine> row) {
  if (row.isEmpty) return '';
  if (row.length == 1) return row.single.text;
  final cells = <String>[];
  var current = row.first.text;
  var previous = row.first;
  for (final cell in row.skip(1)) {
    final gap = cell.boundingBox.left - previous.boundingBox.right;
    final averageHeight =
        (cell.boundingBox.height + previous.boundingBox.height) / 2;
    if (gap > math.max(12, averageHeight * 0.65)) {
      cells.add(current.trim());
      current = cell.text;
    } else {
      current = '$current ${cell.text}';
    }
    previous = cell;
  }
  cells.add(current.trim());
  return cells.where((cell) => cell.isNotEmpty).join(' | ');
}

String _normalizeOcrCell(String value) {
  return value.replaceAll(RegExp(r'\s+'), ' ').replaceAll('：', ':').trim();
}

double _rowTolerance(NutritionLabelOcrLine a, NutritionLabelOcrLine b) {
  return math.max(
    8,
    math.max(a.boundingBox.height, b.boundingBox.height) * 0.72,
  );
}

/// Exists solely for testing — allows widget tests to inject a fake VM.
@visibleForTesting
UsualFoodScanViewModel Function(BuildContext)? testViewModelFactory;
