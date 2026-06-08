import 'package:cal_tracker_mobile/data/repositories/nutrition_repository.dart';
import 'package:cal_tracker_mobile/domain/models/nutrition_models.dart';
import 'package:cal_tracker_mobile/ui/features/meal_templates/view_models/usual_food_scan_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockNutritionRepository extends Mock implements NutritionRepository {}

void main() {
  group('UsualFoodScanViewModel', () {
    late _MockNutritionRepository mockNutritionRepository;
    late List<String> capturedPaths;
    late UsualFoodDraft? draftedDraft;
    late int initializeCameraCalls;
    late int takePictureCalls;
    late int recognizeTextCalls;
    String? initializeCameraError;
    String? takePictureError;
    String? recognizeTextError;
    String? recognizeTextReturn;
    bool? cameraPermissionResult;

    UsualFoodScanViewModel createViewModel() {
      return UsualFoodScanViewModel(
        nutritionRepository: mockNutritionRepository,
        initializeCamera: () async {
          initializeCameraCalls++;
          if (initializeCameraError != null) {
            throw Exception(initializeCameraError);
          }
        },
        takePicture: () async {
          takePictureCalls++;
          if (takePictureError != null) {
            throw Exception(takePictureError);
          }
          return '/tmp/test_photo_$takePictureCalls.jpg';
        },
        recognizeText: (path) async {
          recognizeTextCalls++;
          capturedPaths.add(path);
          if (recognizeTextError != null) {
            throw Exception(recognizeTextError);
          }
          return recognizeTextReturn ?? 'Calories 200\nProtein 10g\nCarbs 30g';
        },
        requestCameraPermission: () async {
          return cameraPermissionResult ?? true;
        },
        onDrafted: (draft) {
          draftedDraft = draft;
        },
      );
    }

    setUp(() {
      mockNutritionRepository = _MockNutritionRepository();
      capturedPaths = <String>[];
      draftedDraft = null;
      initializeCameraCalls = 0;
      takePictureCalls = 0;
      recognizeTextCalls = 0;
      initializeCameraError = null;
      takePictureError = null;
      recognizeTextError = null;
      recognizeTextReturn = null;
      cameraPermissionResult = true;
    });

    test('initial phase is idle', () {
      final vm = createViewModel();
      expect(vm.phase, UsualFoodScanPhase.idle);
      expect(vm.isBusy, isFalse);
      expect(vm.errorCode, UsualFoodScanError.none);
      expect(vm.ocrText, isNull);
      expect(vm.draft, isNull);
      vm.dispose();
    });

    test('init transitions through requestingPermission to ready', () async {
      final vm = createViewModel();
      await vm.init();
      expect(vm.phase, UsualFoodScanPhase.ready);
      expect(vm.isBusy, isFalse);
      expect(initializeCameraCalls, 1);
      vm.dispose();
    });

    test('init transitions to error when camera permission denied', () async {
      cameraPermissionResult = false;
      final vm = createViewModel();
      await vm.init();
      expect(vm.phase, UsualFoodScanPhase.error);
      expect(vm.errorCode, UsualFoodScanError.cameraDenied);
      expect(initializeCameraCalls, 0);
      vm.dispose();
    });

    test('init transitions to error when camera initialization fails', () async {
      initializeCameraError = 'camera_error';
      final vm = createViewModel();
      await vm.init();
      expect(vm.phase, UsualFoodScanPhase.error);
      expect(vm.errorCode, UsualFoodScanError.cameraUnavailable);
      vm.dispose();
    });

    test('init without permission checker still works', () async {
      final vm = UsualFoodScanViewModel(
        nutritionRepository: mockNutritionRepository,
        initializeCamera: () async {
          initializeCameraCalls++;
        },
        takePicture: () async => '/tmp/test.jpg',
        recognizeText: (_) async => 'Calories 200',
      );
      await vm.init();
      expect(vm.phase, UsualFoodScanPhase.ready);
      expect(initializeCameraCalls, 1);
      vm.dispose();
    });

    test('captureAndProcess success calls all steps and triggers onDrafted',
        () async {
      when(
        () => mockNutritionRepository.draftUsualFood(any()),
      ).thenAnswer(
        (_) async => const UsualFoodDraft(
          name: 'Test Food',
          servingGrams: 100,
          calories: 200,
          proteinGrams: 10,
          carbsGrams: 30,
          fatGrams: 5,
        ),
      );

      final vm = createViewModel();
      await vm.init();
      await vm.captureAndProcess();

      expect(vm.phase, UsualFoodScanPhase.drafted);
      expect(vm.isBusy, isFalse);
      expect(takePictureCalls, 1);
      expect(recognizeTextCalls, 1);
      expect(vm.ocrText, isNotNull);
      expect(vm.draft, isNotNull);
      expect(draftedDraft, isNotNull);
      expect(draftedDraft!.name, 'Test Food');
      expect(capturedPaths.length, 1);
      vm.dispose();
    });

    test('captureAndProcess returns error when no text detected', () async {
      recognizeTextReturn = '';
      when(() => mockNutritionRepository.draftUsualFood(any()))
          .thenAnswer((_) async => const UsualFoodDraft());

      final vm = createViewModel();
      await vm.init();
      await vm.captureAndProcess();

      expect(vm.phase, UsualFoodScanPhase.error);
      expect(vm.errorCode, UsualFoodScanError.ocrEmpty);
      expect(takePictureCalls, 1);
      expect(recognizeTextCalls, 1);
      // Should NOT call draft because OCR was empty
      verifyNever(() => mockNutritionRepository.draftUsualFood(any()));
      vm.dispose();
    });

    test('captureAndProcess returns error when text is too short', () async {
      recognizeTextReturn = 'X';
      when(() => mockNutritionRepository.draftUsualFood(any()))
          .thenAnswer((_) async => const UsualFoodDraft());

      final vm = createViewModel();
      await vm.init();
      await vm.captureAndProcess();

      expect(vm.phase, UsualFoodScanPhase.error);
      expect(vm.errorCode, UsualFoodScanError.ocrTooShort);
      verifyNever(() => mockNutritionRepository.draftUsualFood(any()));
      vm.dispose();
    });

    test('captureAndProcess returns error when takePicture fails', () async {
      takePictureError = 'capture_error';
      final vm = createViewModel();
      await vm.init();
      await vm.captureAndProcess();

      expect(vm.phase, UsualFoodScanPhase.error);
      expect(vm.errorCode, UsualFoodScanError.captureFailed);
      expect(recognizeTextCalls, 0);
      verifyNever(() => mockNutritionRepository.draftUsualFood(any()));
      vm.dispose();
    });

    test('captureAndProcess returns error when recognizeText fails', () async {
      recognizeTextError = 'ocr_error';
      final vm = createViewModel();
      await vm.init();
      await vm.captureAndProcess();

      expect(vm.phase, UsualFoodScanPhase.error);
      expect(takePictureCalls, 1);
      expect(recognizeTextCalls, 1);
      verifyNever(() => mockNutritionRepository.draftUsualFood(any()));
      vm.dispose();
    });

    test('captureAndProcess returns error when draftUsualFood fails',
        () async {
      when(() => mockNutritionRepository.draftUsualFood(any()))
          .thenThrow(Exception('draft_error'));

      final vm = createViewModel();
      await vm.init();
      await vm.captureAndProcess();

      expect(vm.phase, UsualFoodScanPhase.error);
      expect(vm.errorCode, UsualFoodScanError.draftFailed);
      vm.dispose();
    });

    test(
        'captureAndProcess is a no-op if already in drafting or ocrProcessing',
        () async {
      final vm = createViewModel();
      vm.setUiStateForTest(
        const UsualFoodScanUiState(phase: UsualFoodScanPhase.drafting),
      );
      await vm.captureAndProcess();
      expect(takePictureCalls, 0);
      vm.dispose();
    });

    test('retry goes back to ready and clears draft', () async {
      when(
        () => mockNutritionRepository.draftUsualFood(any()),
      ).thenAnswer(
        (_) async => const UsualFoodDraft(name: 'Test Food'),
      );

      final vm = createViewModel();
      await vm.init();
      await vm.captureAndProcess();
      expect(vm.phase, UsualFoodScanPhase.drafted);

      vm.retry();
      expect(vm.phase, UsualFoodScanPhase.ready);
      expect(vm.draft, isNull);
      vm.dispose();
    });

    test('calling init while already initialized is safe', () async {
      final vm = createViewModel();
      await vm.init();
      expect(vm.phase, UsualFoodScanPhase.ready);

      // second call is also fine (re-initializes camera)
      initializeCameraCalls = 0;
      await vm.init();
      expect(vm.phase, UsualFoodScanPhase.ready);
      expect(initializeCameraCalls, 1);
      vm.dispose();
    });
  });
}
