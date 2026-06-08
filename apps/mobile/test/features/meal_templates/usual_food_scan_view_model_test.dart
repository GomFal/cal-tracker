import 'package:cal_tracker_mobile/data/repositories/nutrition_repository.dart';
import 'package:cal_tracker_mobile/domain/models/nutrition_models.dart';
import 'package:cal_tracker_mobile/ui/features/meal_templates/view_models/usual_food_scan_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockNutritionRepository extends Mock implements NutritionRepository {}

void main() {
  group('UsualFoodScanViewModel', () {
    late _MockNutritionRepository mockNutritionRepository;
    late List<String> recognizedPaths;
    late List<String> deletedPaths;
    late int pausePreviewCalls;
    late int resumePreviewCalls;
    late int initializeCameraCalls;
    late int takePictureCalls;
    late int recognizeTextCalls;
    late UsualFoodDraft? draftedDraft;
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
        pausePreview: () async {
          pausePreviewCalls++;
        },
        resumePreview: () async {
          resumePreviewCalls++;
        },
        recognizeText: (path) async {
          recognizeTextCalls++;
          recognizedPaths.add(path);
          if (recognizeTextError != null) {
            throw Exception(recognizeTextError);
          }
          return recognizeTextReturn ?? 'Calories 200\nProtein 10g\nCarbs 30g';
        },
        deleteCapturedFile: (path) async {
          deletedPaths.add(path);
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
      recognizedPaths = <String>[];
      deletedPaths = <String>[];
      pausePreviewCalls = 0;
      resumePreviewCalls = 0;
      initializeCameraCalls = 0;
      takePictureCalls = 0;
      recognizeTextCalls = 0;
      draftedDraft = null;
      initializeCameraError = null;
      takePictureError = null;
      recognizeTextError = null;
      recognizeTextReturn = null;
      cameraPermissionResult = true;
    });

    test('initial phase is idle and no error', () {
      final vm = createViewModel();
      expect(vm.phase, UsualFoodScanPhase.idle);
      expect(vm.isBusy, isFalse);
      expect(vm.isPreviewing, isFalse);
      expect(vm.errorCode, UsualFoodScanError.none);
      expect(vm.ocrText, isNull);
      expect(vm.capturedFilePath, isNull);
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

    test('init transitions to cameraUnavailable when no camera (generic throw)',
        () async {
      initializeCameraError = 'No camera available on this device.';
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
        pausePreview: () async {},
        resumePreview: () async {},
        recognizeText: (_) async => 'Calories 200',
        deleteCapturedFile: (_) async {},
      );
      await vm.init();
      expect(vm.phase, UsualFoodScanPhase.ready);
      expect(initializeCameraCalls, 1);
      vm.dispose();
    });

    group('capture()', () {
      test('from ready → previewing, pauses preview, stores file path',
          () async {
        final vm = createViewModel();
        await vm.init();
        await vm.capture();
        expect(vm.phase, UsualFoodScanPhase.previewing);
        expect(vm.isPreviewing, isTrue);
        expect(vm.isBusy, isFalse);
        expect(vm.capturedFilePath, '/tmp/test_photo_1.jpg');
        expect(takePictureCalls, 1);
        expect(pausePreviewCalls, 1);
        vm.dispose();
      });

      test('is a no-op when not in ready phase', () async {
        final vm = createViewModel();
        vm.setUiStateForTest(
          const UsualFoodScanUiState(phase: UsualFoodScanPhase.error),
        );
        await vm.capture();
        expect(takePictureCalls, 0);
        expect(pausePreviewCalls, 0);
        vm.dispose();
      });

      test('returns error when takePicture throws', () async {
        takePictureError = 'capture_error';
        final vm = createViewModel();
        await vm.init();
        await vm.capture();
        expect(vm.phase, UsualFoodScanPhase.error);
        expect(vm.errorCode, UsualFoodScanError.captureFailed);
        expect(pausePreviewCalls, 0); // pause not called if capture failed
        vm.dispose();
      });

      test('still enters previewing if pausePreview throws (non-fatal)',
          () async {
        final vm = UsualFoodScanViewModel(
          nutritionRepository: mockNutritionRepository,
          initializeCamera: () async {},
          takePicture: () async => '/tmp/test.jpg',
          pausePreview: () async {
            pausePreviewCalls++;
            throw Exception('pause failed');
          },
          resumePreview: () async {},
          recognizeText: (_) async => 'Calories 200',
          deleteCapturedFile: (_) async {},
        );
        await vm.init();
        await vm.capture();
        expect(vm.phase, UsualFoodScanPhase.previewing);
        expect(vm.capturedFilePath, '/tmp/test.jpg');
        vm.dispose();
      });
    });

    group('confirmCapture()', () {
      test('happy path: previewing → ocrProcessing → drafting → drafted',
          () async {
        when(() => mockNutritionRepository.draftUsualFood(any())).thenAnswer(
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
        await vm.capture();
        await vm.confirmCapture();

        expect(vm.phase, UsualFoodScanPhase.drafted);
        expect(vm.isBusy, isFalse);
        expect(recognizeTextCalls, 1);
        expect(vm.ocrText, isNotNull);
        expect(vm.draft, isNotNull);
        expect(draftedDraft, isNotNull);
        expect(draftedDraft!.name, 'Test Food');
        expect(recognizedPaths, ['/tmp/test_photo_1.jpg']);
        vm.dispose();
      });

      test('returns error with ocrEmpty when text is empty', () async {
        recognizeTextReturn = '';
        final vm = createViewModel();
        await vm.init();
        await vm.capture();
        await vm.confirmCapture();

        expect(vm.phase, UsualFoodScanPhase.error);
        expect(vm.errorCode, UsualFoodScanError.ocrEmpty);
        verifyNever(() => mockNutritionRepository.draftUsualFood(any()));
        vm.dispose();
      });

      test('returns error with ocrTooShort when text < 20 chars', () async {
        recognizeTextReturn = 'X';
        final vm = createViewModel();
        await vm.init();
        await vm.capture();
        await vm.confirmCapture();

        expect(vm.phase, UsualFoodScanPhase.error);
        expect(vm.errorCode, UsualFoodScanError.ocrTooShort);
        verifyNever(() => mockNutritionRepository.draftUsualFood(any()));
        vm.dispose();
      });

      test('returns error with ocrFailed when OCR throws', () async {
        recognizeTextError = 'ocr_error';
        final vm = createViewModel();
        await vm.init();
        await vm.capture();
        await vm.confirmCapture();

        expect(vm.phase, UsualFoodScanPhase.error);
        expect(vm.errorCode, UsualFoodScanError.ocrFailed);
        verifyNever(() => mockNutritionRepository.draftUsualFood(any()));
        vm.dispose();
      });

      test('returns error with draftFailed when repository throws', () async {
        when(() => mockNutritionRepository.draftUsualFood(any()))
            .thenThrow(Exception('draft_error'));
        final vm = createViewModel();
        await vm.init();
        await vm.capture();
        await vm.confirmCapture();

        expect(vm.phase, UsualFoodScanPhase.error);
        expect(vm.errorCode, UsualFoodScanError.draftFailed);
        vm.dispose();
      });

      test('is a no-op when not in previewing phase', () async {
        final vm = createViewModel();
        await vm.init();
        // not in previewing
        await vm.confirmCapture();
        expect(recognizeTextCalls, 0);
        vm.dispose();
      });

      test('is a no-op when capturedFilePath is null (corrupt state)', () async {
        final vm = createViewModel();
        await vm.init();
        // Force previewing without a file path
        vm.setUiStateForTest(
          const UsualFoodScanUiState(phase: UsualFoodScanPhase.previewing),
        );
        await vm.confirmCapture();
        expect(vm.phase, UsualFoodScanPhase.error);
        expect(vm.errorCode, UsualFoodScanError.captureFailed);
        expect(recognizeTextCalls, 0);
        vm.dispose();
      });
    });

    group('retakeCapture()', () {
      test('clears file, deletes it, resumes preview, returns to ready',
          () async {
        final vm = createViewModel();
        await vm.init();
        await vm.capture();
        expect(vm.phase, UsualFoodScanPhase.previewing);
        expect(vm.capturedFilePath, isNotNull);

        await vm.retakeCapture();

        expect(vm.phase, UsualFoodScanPhase.ready);
        expect(vm.capturedFilePath, isNull);
        expect(deletedPaths, ['/tmp/test_photo_1.jpg']);
        expect(resumePreviewCalls, 1);
        vm.dispose();
      });

      test('is a no-op when not in previewing', () async {
        final vm = createViewModel();
        await vm.init();
        await vm.retakeCapture();
        expect(resumePreviewCalls, 0);
        expect(deletedPaths, isEmpty);
        vm.dispose();
      });
    });

    group('retry()', () {
      test('from error → ready, resumes preview', () async {
        when(() => mockNutritionRepository.draftUsualFood(any()))
            .thenThrow(Exception('draft_error'));

        final vm = createViewModel();
        await vm.init();
        await vm.capture();
        await vm.confirmCapture();
        expect(vm.phase, UsualFoodScanPhase.error);

        await vm.retry();
        expect(vm.phase, UsualFoodScanPhase.ready);
        expect(vm.errorCode, UsualFoodScanError.none);
        expect(resumePreviewCalls, 1);
        vm.dispose();
      });
    });

    group('cancel()', () {
      test('deletes the captured file', () async {
        final vm = createViewModel();
        await vm.init();
        await vm.capture();
        await vm.cancel();
        expect(deletedPaths, ['/tmp/test_photo_1.jpg']);
        vm.dispose();
      });

      test('is safe when no file has been captured', () async {
        final vm = createViewModel();
        await vm.init();
        await vm.cancel();
        expect(deletedPaths, isEmpty);
        vm.dispose();
      });
    });
  });
}
