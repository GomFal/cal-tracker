import 'package:flutter/foundation.dart';

import '../../../../data/repositories/nutrition_repository.dart';
import '../../../../domain/models/nutrition_models.dart';
import '../../../core/user_visible_error.dart';

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

  /// An error occurred; check [errorMessage].
  error,
}

/// Immutable UI state snapshot for [UsualFoodScanViewModel].
class UsualFoodScanUiState {
  const UsualFoodScanUiState({
    this.phase = UsualFoodScanPhase.idle,
    this.errorMessage,
    this.ocrText,
  });

  final UsualFoodScanPhase phase;
  final String? errorMessage;
  final String? ocrText;

  UsualFoodScanUiState copyWith({
    UsualFoodScanPhase? phase,
    Object? errorMessage = _unchanged,
    Object? ocrText = _unchanged,
  }) {
    return UsualFoodScanUiState(
      phase: phase ?? this.phase,
      errorMessage: identical(errorMessage, _unchanged)
          ? this.errorMessage
          : errorMessage as String?,
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
  String? get errorMessage => _uiState.errorMessage;
  String? get ocrText => _uiState.ocrText;

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
  /// [UsualFoodScanPhase.error] with a user-visible message.
  Future<void> init() async {
    _setPhase(UsualFoodScanPhase.requestingPermission);

    try {
      if (_requestCameraPermission != null) {
        final granted = await _requestCameraPermission();
        if (!granted) {
          _setError(
            'Camera access is required to scan a label. Enable it in Settings.',
          );
          return;
        }
      }

      await _initializeCamera();
      _setPhase(UsualFoodScanPhase.ready);
    } catch (e) {
      _setError(
        userVisibleErrorMessage(e, context: UserErrorContext.usualFoodScanOcr),
      );
    }
  }

  /// Capture a photo, run OCR, send text to draft endpoint.
  ///
  /// Transitions: ready → capturing → ocrProcessing → drafting → drafted.
  /// On error → error with user-visible message.
  Future<void> captureAndProcess() async {
    if (_uiState.phase == UsualFoodScanPhase.drafting ||
        _uiState.phase == UsualFoodScanPhase.ocrProcessing) {
      return;
    }

    _setPhase(UsualFoodScanPhase.capturing);

    String filePath;
    try {
      filePath = await _takePicture();
      _onCaptured?.call(filePath);
    } catch (e) {
      _setError(
        userVisibleErrorMessage(e, context: UserErrorContext.usualFoodScanOcr),
      );
      return;
    }

    // OCR
    _setPhase(UsualFoodScanPhase.ocrProcessing);
    String text;
    try {
      text = await _recognizeText(filePath);
      _setUiState(_uiState.copyWith(ocrText: text));
    } catch (e) {
      _setError(
        userVisibleErrorMessage(e, context: UserErrorContext.usualFoodScanOcr),
      );
      return;
    }

    if (text.trim().isEmpty) {
      _setError(
        'No text detected. Get closer, improve the lighting, '
        'and try again.',
      );
      return;
    }

    if (text.trim().length < 20) {
      _setError(
        'The image has too little text. Make sure the whole '
        'nutrition table is in frame.',
      );
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
      _setError(
        userVisibleErrorMessage(
          e,
          context: UserErrorContext.usualFoodScanDraft,
        ),
      );
    }
  }

  /// Go back to [UsualFoodScanPhase.ready] and allow retry.
  void retry() {
    draft = null;
    _setPhase(UsualFoodScanPhase.ready);
  }

  /// Override the internal state for testing purposes.
  @visibleForTesting
  void setUiStateForTest(UsualFoodScanUiState state) {
    _uiState = state;
    notifyListeners();
  }

  void _setPhase(UsualFoodScanPhase value) {
    _setUiState(_uiState.copyWith(phase: value));
  }

  void _setError(String message) {
    _setUiState(
      _uiState.copyWith(
        phase: UsualFoodScanPhase.error,
        errorMessage: message,
      ),
    );
  }

  void _setUiState(UsualFoodScanUiState value) {
    _uiState = value;
    notifyListeners();
  }
}
