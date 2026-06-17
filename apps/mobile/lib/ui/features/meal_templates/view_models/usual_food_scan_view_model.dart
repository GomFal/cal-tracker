import 'package:camera/camera.dart' show CameraException;
import 'package:flutter/foundation.dart';

import '../../../../data/repositories/nutrition_repository.dart';
import '../../../../domain/models/nutrition_models.dart';

/// Phases of the nutrition label scan flow.
enum UsualFoodScanPhase {
  /// Initial idle state before any interaction.
  idle,

  /// Requesting camera permission at runtime.
  requestingPermission,

  /// Camera is initialized and live preview is on.
  ready,

  /// Taking a picture with the camera.
  capturing,

  /// The user is reviewing a still image of the captured photo before
  /// deciding whether to use it or retake it. The camera live preview is
  /// paused in this phase.
  previewing,

  /// Running on-device OCR (ML Kit) on the captured photo.
  ocrProcessing,

  /// Sending OCR text to the backend LLM to build a UsualFoodDraft.
  drafting,

  /// A UsualFoodDraft was successfully produced.
  drafted,

  /// An error occurred; check [errorCode].
  error,
}

/// Typed error codes emitted by [UsualFoodScanViewModel] instead of raw strings.
///
/// The screen maps each value to a localized user-visible message via
/// [AppLocalizations] so the VM remains context-free.
enum UsualFoodScanError {
  none,
  cameraDenied,
  cameraUnavailable,
  cameraInitFailed,
  captureFailed,
  ocrFailed,
  ocrEmpty,
  ocrTooShort,
  draftFailed,
  unknown,
}

/// Immutable UI state snapshot for [UsualFoodScanViewModel].
class UsualFoodScanUiState {
  const UsualFoodScanUiState({
    this.phase = UsualFoodScanPhase.idle,
    this.capturedFilePath,
    this.ocrText,
  });

  final UsualFoodScanPhase phase;

  /// Local file path of the captured still image, populated once the user
  /// reaches the [UsualFoodScanPhase.previewing] phase. The screen uses this
  /// to render the preview via `Image.file`.
  final String? capturedFilePath;

  /// Text extracted by OCR. Exposed for debugging and tests; the production
  /// flow does not display this to the user (the backend LLM consumes it
  /// directly).
  final String? ocrText;

  UsualFoodScanUiState copyWith({
    UsualFoodScanPhase? phase,
    Object? capturedFilePath = _unchanged,
    Object? ocrText = _unchanged,
  }) {
    return UsualFoodScanUiState(
      phase: phase ?? this.phase,
      capturedFilePath: identical(capturedFilePath, _unchanged)
          ? this.capturedFilePath
          : capturedFilePath as String?,
      ocrText:
          identical(ocrText, _unchanged) ? this.ocrText : ocrText as String?,
    );
  }
}

const Object _unchanged = Object();

/// ViewModel for the nutrition-label scan flow.
///
/// Delegates camera, OCR, and permission to injected closures so the
/// ViewModel remains testable without real hardware.
///
/// Flow:
///   init → ready → capture() → previewing → confirmCapture() →
///     ocrProcessing → drafting → drafted (pops with draft)
///
/// From `previewing` the user can also call `retakeCapture()` to discard the
/// photo and return to `ready`. The camera live preview is paused while in
/// `previewing`/`ocrProcessing`/`drafting` so the user can see the still
/// image they captured without the live video overwriting it.
class UsualFoodScanViewModel extends ChangeNotifier {
  UsualFoodScanViewModel({
    required NutritionRepository nutritionRepository,
    required Future<void> Function() initializeCamera,
    required Future<String> Function() takePicture,
    required Future<void> Function() pausePreview,
    required Future<void> Function() resumePreview,
    required Future<String> Function(String filePath) recognizeText,
    required Future<void> Function(String filePath) deleteCapturedFile,
    Future<String?> Function(String filePath)? prepareImageForOcr,
    Future<bool> Function()? requestCameraPermission,
    bool draftFromRecognizedText = true,
    void Function(UsualFoodDraft draft)? onDrafted,
    void Function(String text)? onTextExtracted,
  })  : _nutritionRepository = nutritionRepository,
        _initializeCamera = initializeCamera,
        _takePicture = takePicture,
        _pausePreview = pausePreview,
        _resumePreview = resumePreview,
        _recognizeText = recognizeText,
        _deleteCapturedFile = deleteCapturedFile,
        _prepareImageForOcr = prepareImageForOcr,
        _requestCameraPermission = requestCameraPermission,
        _draftFromRecognizedText = draftFromRecognizedText,
        _onDrafted = onDrafted,
        _onTextExtracted = onTextExtracted;

  final NutritionRepository _nutritionRepository;
  final Future<void> Function() _initializeCamera;
  final Future<String> Function() _takePicture;
  final Future<void> Function() _pausePreview;
  final Future<void> Function() _resumePreview;
  final Future<String> Function(String filePath) _recognizeText;
  final Future<void> Function(String filePath) _deleteCapturedFile;
  final Future<String?> Function(String filePath)? _prepareImageForOcr;
  final Future<bool> Function()? _requestCameraPermission;
  final bool _draftFromRecognizedText;
  final void Function(UsualFoodDraft draft)? _onDrafted;
  final void Function(String text)? _onTextExtracted;

  UsualFoodScanUiState _uiState = const UsualFoodScanUiState();

  UsualFoodScanPhase get phase => _uiState.phase;
  String? get capturedFilePath => _uiState.capturedFilePath;
  String? get ocrText => _uiState.ocrText;

  /// The typed error code; [UsualFoodScanError.none] when no error.
  UsualFoodScanError errorCode = UsualFoodScanError.none;

  /// True while an async operation is in progress.
  bool get isBusy =>
      _uiState.phase == UsualFoodScanPhase.requestingPermission ||
      _uiState.phase == UsualFoodScanPhase.capturing ||
      _uiState.phase == UsualFoodScanPhase.ocrProcessing ||
      _uiState.phase == UsualFoodScanPhase.drafting;

  /// True when the user is reviewing a still image and can confirm or retake.
  bool get isPreviewing => _uiState.phase == UsualFoodScanPhase.previewing;

  /// The draft returned by the [nutritionRepository] on success.
  UsualFoodDraft? draft;

  /// Initialize the camera and transition to [UsualFoodScanPhase.ready].
  ///
  /// Requests runtime camera permission when [requestCameraPermission] is
  /// provided, then calls [initializeCamera]. On failure transitions to
  /// [UsualFoodScanPhase.error] with a typed [errorCode].
  Future<void> init() async {
    _clearError();
    _setPhase(UsualFoodScanPhase.requestingPermission);

    try {
      if (_requestCameraPermission != null) {
        final granted = await _requestCameraPermission();
        if (!granted) {
          _setErrorCode(UsualFoodScanError.cameraDenied);
          return;
        }
      }

      await _initializeCamera();
      _setPhase(UsualFoodScanPhase.ready);
    } on CameraException catch (e) {
      _setErrorCode(
        e.code == 'cameraNotAvailable'
            ? UsualFoodScanError.cameraUnavailable
            : UsualFoodScanError.cameraInitFailed,
      );
    } catch (_) {
      // The screen throws 'No camera available on this device.' when
      // availableCameras() returns [] — treat as cameraUnavailable.
      _setErrorCode(UsualFoodScanError.cameraUnavailable);
    }
  }

  /// Capture a still photo and pause the live preview so the user can review
  /// the image before deciding to send it to the OCR/LLM pipeline.
  ///
  /// Transitions: ready → capturing → previewing.
  /// On error → error with typed [errorCode].
  Future<void> capture() async {
    if (_uiState.phase != UsualFoodScanPhase.ready) {
      return;
    }

    _clearError();
    _setPhase(UsualFoodScanPhase.capturing);

    String filePath;
    try {
      filePath = await _takePicture();
    } catch (_) {
      _setErrorCode(UsualFoodScanError.captureFailed);
      return;
    }

    // Stop the live preview so it does not overwrite the still image the
    // user is about to see. Best effort — failure to pause is non-fatal.
    try {
      await _pausePreview();
    } catch (_) {
      // ignore
    }

    _setUiState(
      _uiState.copyWith(
        phase: UsualFoodScanPhase.previewing,
        capturedFilePath: filePath,
      ),
    );
  }

  /// User confirmed the captured photo. Resume the OCR + LLM draft pipeline.
  ///
  /// Transitions: previewing → ocrProcessing → drafting → drafted.
  /// On error → error with typed [errorCode]. The captured file remains on
  /// disk in the error case so a retry can re-use it.
  Future<void> confirmCapture() async {
    if (_uiState.phase != UsualFoodScanPhase.previewing) {
      return;
    }
    final filePath = _uiState.capturedFilePath;
    if (filePath == null) {
      _setErrorCode(UsualFoodScanError.captureFailed);
      return;
    }

    _clearError();
    _setPhase(UsualFoodScanPhase.ocrProcessing);

    String text;
    String? preparedFilePath;
    try {
      preparedFilePath = await _prepareImageForOcr?.call(filePath);
      text = await _recognizeText(preparedFilePath ?? filePath);
      _setUiState(_uiState.copyWith(ocrText: text));
    } catch (_) {
      _setErrorCode(UsualFoodScanError.ocrFailed);
      return;
    } finally {
      if (preparedFilePath != null && preparedFilePath != filePath) {
        try {
          await _deleteCapturedFile(preparedFilePath);
        } catch (_) {
          // best effort
        }
      }
    }

    // Reject very short text — 20-char floor ensures we have at least
    // a few nutritional fields before asking the LLM.
    if (text.trim().isEmpty) {
      _setErrorCode(UsualFoodScanError.ocrEmpty);
      return;
    }
    if (text.trim().length < 20) {
      _setErrorCode(UsualFoodScanError.ocrTooShort);
      return;
    }

    if (!_draftFromRecognizedText) {
      _setPhase(UsualFoodScanPhase.drafted);
      _onTextExtracted?.call(text.trim());
      return;
    }

    _setPhase(UsualFoodScanPhase.drafting);
    try {
      final result = await _nutritionRepository.draftUsualFood(text);
      draft = result;
      _setPhase(UsualFoodScanPhase.drafted);
      _onDrafted?.call(result);
    } catch (_) {
      _setErrorCode(UsualFoodScanError.draftFailed);
    }
  }

  /// User rejected the captured photo. Delete the file, resume the live
  /// preview, and return to [UsualFoodScanPhase.ready].
  Future<void> retakeCapture() async {
    if (_uiState.phase != UsualFoodScanPhase.previewing) {
      return;
    }
    final filePath = _uiState.capturedFilePath;
    _setUiState(
      _uiState.copyWith(
        phase: UsualFoodScanPhase.ready,
        capturedFilePath: null,
      ),
    );
    if (filePath != null) {
      try {
        await _deleteCapturedFile(filePath);
      } catch (_) {
        // best effort
      }
    }
    try {
      await _resumePreview();
    } catch (_) {
      // ignore
    }
  }

  /// Recover from an error state. Returns to [UsualFoodScanPhase.ready] and
  /// resumes the live preview.
  Future<void> retry() async {
    if (_uiState.phase == UsualFoodScanPhase.error) {
      _clearError();
      _setPhase(UsualFoodScanPhase.ready);
      try {
        await _resumePreview();
      } catch (_) {
        // ignore
      }
    }
  }

  /// Cancel out of the scan and discard the captured photo (if any). Used by
  /// the close button on the screen to leave the screen cleanly.
  Future<void> cancel() async {
    final filePath = _uiState.capturedFilePath;
    if (filePath != null) {
      try {
        await _deleteCapturedFile(filePath);
      } catch (_) {
        // best effort
      }
    }
  }

  /// Override the internal state for testing purposes.
  @visibleForTesting
  void setUiStateForTest(UsualFoodScanUiState state) {
    _uiState = state;
    notifyListeners();
  }

  void _setPhase(UsualFoodScanPhase value) {
    _clearError();
    _setUiState(_uiState.copyWith(phase: value));
  }

  void _setErrorCode(UsualFoodScanError code) {
    errorCode = code;
    _setUiState(_uiState.copyWith(phase: UsualFoodScanPhase.error));
  }

  void _clearError() {
    errorCode = UsualFoodScanError.none;
  }

  void _setUiState(UsualFoodScanUiState value) {
    _uiState = value;
    notifyListeners();
  }
}
