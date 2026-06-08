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

  /// Camera is initialized and ready to capture.
  ready,

  /// Taking a picture with the camera.
  capturing,

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
    this.ocrText,
  });

  final UsualFoodScanPhase phase;
  final String? ocrText;

  UsualFoodScanUiState copyWith({
    UsualFoodScanPhase? phase,
    Object? ocrText = _unchanged,
  }) {
    return UsualFoodScanUiState(
      phase: phase ?? this.phase,
      ocrText: identical(ocrText, _unchanged)
          ? this.ocrText
          : ocrText as String?,
    );
  }
}

const Object _unchanged = Object();

/// ViewModel for the nutrition-label scan flow.
///
/// Delegates camera, OCR, and permission to injected closures so the
/// ViewModel remains testable without real hardware.
class UsualFoodScanViewModel extends ChangeNotifier {
  UsualFoodScanViewModel({
    required NutritionRepository nutritionRepository,
    required Future<void> Function() initializeCamera,
    required Future<String> Function() takePicture,
    required Future<String> Function(String filePath) recognizeText,
    Future<bool> Function()? requestCameraPermission,
    void Function(UsualFoodDraft draft)? onDrafted,
    void Function(String filePath)? onCaptured,
  })  : _nutritionRepository = nutritionRepository,
        _initializeCamera = initializeCamera,
        _takePicture = takePicture,
        _recognizeText = recognizeText,
        _requestCameraPermission = requestCameraPermission,
        _onDrafted = onDrafted,
        _onCaptured = onCaptured;

  final NutritionRepository _nutritionRepository;
  final Future<void> Function() _initializeCamera;
  final Future<String> Function() _takePicture;
  final Future<String> Function(String filePath) _recognizeText;
  final Future<bool> Function()? _requestCameraPermission;
  final void Function(UsualFoodDraft draft)? _onDrafted;
  final void Function(String filePath)? _onCaptured;

  UsualFoodScanUiState _uiState = const UsualFoodScanUiState();

  UsualFoodScanPhase get phase => _uiState.phase;
  String? get ocrText => _uiState.ocrText;

  /// The typed error code; [UsualFoodScanError.none] when no error.
  UsualFoodScanError errorCode = UsualFoodScanError.none;

  /// True while an async operation is in progress.
  bool get isBusy =>
      _uiState.phase == UsualFoodScanPhase.requestingPermission ||
      _uiState.phase == UsualFoodScanPhase.capturing ||
      _uiState.phase == UsualFoodScanPhase.ocrProcessing ||
      _uiState.phase == UsualFoodScanPhase.drafting;

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

  /// Capture a photo, run OCR, send text to draft endpoint.
  ///
  /// Transitions: ready → capturing → ocrProcessing → drafting → drafted.
  /// On error → error with typed [errorCode].
  Future<void> captureAndProcess() async {
    if (_uiState.phase == UsualFoodScanPhase.drafting ||
        _uiState.phase == UsualFoodScanPhase.ocrProcessing) {
      return;
    }

    _clearError();
    _setPhase(UsualFoodScanPhase.capturing);

    String filePath;
    try {
      filePath = await _takePicture();
      _onCaptured?.call(filePath);
    } catch (e) {
      _setErrorCode(UsualFoodScanError.captureFailed);
      return;
    }

    // OCR
    _setPhase(UsualFoodScanPhase.ocrProcessing);
    String text;
    try {
      text = await _recognizeText(filePath);
      _setUiState(_uiState.copyWith(ocrText: text));
    } catch (e) {
      _setErrorCode(UsualFoodScanError.ocrFailed);
      return;
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

    // Draft via LLM
    _setPhase(UsualFoodScanPhase.drafting);
    try {
      final result = await _nutritionRepository.draftUsualFood(text);
      draft = result;
      _setPhase(UsualFoodScanPhase.drafted);
      _onDrafted?.call(result);
    } catch (e) {
      _setErrorCode(UsualFoodScanError.draftFailed);
    }
  }

  /// Go back to [UsualFoodScanPhase.ready] and allow retry.
  void retry() {
    draft = null;
    _clearError();
    _setPhase(UsualFoodScanPhase.ready);
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
