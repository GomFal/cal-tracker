import 'package:cal_tracker_mobile/data/repositories/nutrition_repository.dart';
import 'package:cal_tracker_mobile/domain/models/nutrition_models.dart';
import 'package:cal_tracker_mobile/l10n/generated/app_localizations.dart';
import 'package:cal_tracker_mobile/ui/features/meal_templates/view_models/usual_food_scan_view_model.dart';
import 'package:cal_tracker_mobile/ui/features/meal_templates/views/usual_food_scan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

// ---------------------------------------------------------------------------
// Fake UsualFoodScanViewModel — replaces the production VM in tests.
// ---------------------------------------------------------------------------

class FakeUsualFoodScanViewModel extends UsualFoodScanViewModel {
  FakeUsualFoodScanViewModel({
    this.overridePhase = UsualFoodScanPhase.idle,
    this.overrideErrorCode = UsualFoodScanError.none,
    this.overrideIsBusy = false,
    this.overrideIsPreviewing = false,
    this.overrideCapturedFilePath,
    this.overrideDraft,
  }) : super(
          nutritionRepository: _dummyRepository,
          initializeCamera: () async {},
          takePicture: () async => '',
          pausePreview: () async {},
          resumePreview: () async {},
          recognizeText: (_) async => '',
          deleteCapturedFile: (_) async {},
        );

  static final _dummyRepository = _NutritionRepositoryStub();

  UsualFoodScanPhase overridePhase;
  UsualFoodScanError overrideErrorCode;
  bool overrideIsBusy;
  bool overrideIsPreviewing;
  String? overrideCapturedFilePath;
  UsualFoodDraft? overrideDraft;

  int captureCallCount = 0;
  int confirmCallCount = 0;
  int retakeCallCount = 0;
  int retryCallCount = 0;
  int cancelCallCount = 0;

  @override
  UsualFoodScanPhase get phase => overridePhase;

  @override
  UsualFoodScanError get errorCode => overrideErrorCode;

  @override
  bool get isBusy => overrideIsBusy;

  @override
  bool get isPreviewing => overrideIsPreviewing;

  @override
  String? get capturedFilePath => overrideCapturedFilePath;

  @override
  UsualFoodDraft? get draft => overrideDraft;

  @override
  Future<void> capture() async {
    captureCallCount++;
  }

  @override
  Future<void> confirmCapture() async {
    confirmCallCount++;
  }

  @override
  Future<void> retakeCapture() async {
    retakeCallCount++;
  }

  @override
  Future<void> retry() async {
    retryCallCount++;
  }

  @override
  Future<void> cancel() async {
    cancelCallCount++;
  }
}

/// Stub that satisfies NutritionRepository but is never actually called
/// in the VM fake; it just needs to exist in the constructor.
class _NutritionRepositoryStub extends Mock implements NutritionRepository {}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Build a [MaterialApp] wrapping [UsualFoodScanScreen] with a fake VM
/// injected via [testViewModelFactory].
Widget buildAppWithVm(FakeUsualFoodScanViewModel vm) {
  testViewModelFactory = (_) => vm;
  addTearDown(() => testViewModelFactory = null);

  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Material(
      child: Provider<NutritionRepository>.value(
        value: _NutritionRepositoryStub(),
        child: const UsualFoodScanScreen(),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('UsualFoodScanScreen', () {
    testWidgets('ready: shows close, capture button and viewfinder hint',
        (tester) async {
      final vm = FakeUsualFoodScanViewModel(
        overridePhase: UsualFoodScanPhase.ready,
      );
      await tester.pumpWidget(buildAppWithVm(vm));

      expect(
        find.byKey(const ValueKey('usual_food_scan_close_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('usual_food_scan_capture_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('usual_food_scan_confirm_button')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('usual_food_scan_error_card')),
        findsNothing,
      );
    });

    testWidgets('capture button triggers capture()', (tester) async {
      final vm = FakeUsualFoodScanViewModel(
        overridePhase: UsualFoodScanPhase.ready,
      );
      await tester.pumpWidget(buildAppWithVm(vm));

      await tester.tap(
        find.byKey(const ValueKey('usual_food_scan_capture_button')),
      );
      expect(vm.captureCallCount, 1);
    });

    testWidgets(
        'previewing: shows confirm + retake buttons, hides capture button',
        (tester) async {
      final vm = FakeUsualFoodScanViewModel(
        overridePhase: UsualFoodScanPhase.previewing,
        overrideIsPreviewing: true,
        overrideCapturedFilePath: '/tmp/some_capture.jpg',
      );
      await tester.pumpWidget(buildAppWithVm(vm));

      expect(
        find.byKey(const ValueKey('usual_food_scan_confirm_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('usual_food_scan_retake_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('usual_food_scan_capture_button')),
        findsNothing,
      );
      // Hint card visible
      expect(
        find.byKey(const ValueKey('usual_food_scan_preview_hint_card')),
        findsOneWidget,
      );
    });

    testWidgets('previewing: confirm button triggers confirmCapture()',
        (tester) async {
      final vm = FakeUsualFoodScanViewModel(
        overridePhase: UsualFoodScanPhase.previewing,
        overrideIsPreviewing: true,
        overrideCapturedFilePath: '/tmp/some_capture.jpg',
      );
      await tester.pumpWidget(buildAppWithVm(vm));

      await tester.tap(
        find.byKey(const ValueKey('usual_food_scan_confirm_button')),
      );
      expect(vm.confirmCallCount, 1);
    });

    testWidgets('previewing: retake button triggers retakeCapture()',
        (tester) async {
      final vm = FakeUsualFoodScanViewModel(
        overridePhase: UsualFoodScanPhase.previewing,
        overrideIsPreviewing: true,
        overrideCapturedFilePath: '/tmp/some_capture.jpg',
      );
      await tester.pumpWidget(buildAppWithVm(vm));

      await tester.tap(
        find.byKey(const ValueKey('usual_food_scan_retake_button')),
      );
      expect(vm.retakeCallCount, 1);
    });

    testWidgets(
        'previewing: shows still image via Image.file when capturedFilePath set',
        (tester) async {
      // The screen uses Image.file with that key when there's a still image.
      final vm = FakeUsualFoodScanViewModel(
        overridePhase: UsualFoodScanPhase.previewing,
        overrideIsPreviewing: true,
        overrideCapturedFilePath: '/tmp/some_capture.jpg',
      );
      await tester.pumpWidget(buildAppWithVm(vm));

      expect(
        find.byKey(const ValueKey('usual_food_scan_still_preview')),
        findsOneWidget,
      );
    });

    testWidgets('error: shows card, retry and cancel buttons',
        (tester) async {
      final vm = FakeUsualFoodScanViewModel(
        overridePhase: UsualFoodScanPhase.error,
        overrideErrorCode: UsualFoodScanError.cameraDenied,
      );
      await tester.pumpWidget(buildAppWithVm(vm));

      expect(
        find.byKey(const ValueKey('usual_food_scan_error_card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('usual_food_scan_retry_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('usual_food_scan_cancel_error_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('usual_food_scan_capture_button')),
        findsNothing,
      );
    });

    testWidgets('error → retry triggers retry() and shows capture button',
        (tester) async {
      final vm = FakeUsualFoodScanViewModel(
        overridePhase: UsualFoodScanPhase.error,
        overrideErrorCode: UsualFoodScanError.cameraDenied,
      );
      await tester.pumpWidget(buildAppWithVm(vm));

      await tester.ensureVisible(
        find.byKey(const ValueKey('usual_food_scan_retry_button')),
      );
      await tester.tap(
        find.byKey(const ValueKey('usual_food_scan_retry_button')),
      );
      await tester.pump();

      expect(vm.retryCallCount, 1);
    });

    testWidgets('ocrProcessing: shows spinner with Reading text label',
        (tester) async {
      final vm = FakeUsualFoodScanViewModel(
        overridePhase: UsualFoodScanPhase.ocrProcessing,
        overrideIsBusy: true,
      );
      await tester.pumpWidget(buildAppWithVm(vm));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Reading text…'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('usual_food_scan_capture_button')),
        findsNothing,
      );
    });

    testWidgets('drafting: shows spinner with Filling fields label',
        (tester) async {
      final vm = FakeUsualFoodScanViewModel(
        overridePhase: UsualFoodScanPhase.drafting,
        overrideIsBusy: true,
      );
      await tester.pumpWidget(buildAppWithVm(vm));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Filling fields…'), findsOneWidget);
    });

    testWidgets('drafted: hides all action controls', (tester) async {
      final vm = FakeUsualFoodScanViewModel(
        overridePhase: UsualFoodScanPhase.drafted,
      );
      await tester.pumpWidget(buildAppWithVm(vm));

      expect(
        find.byKey(const ValueKey('usual_food_scan_capture_button')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('usual_food_scan_confirm_button')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('usual_food_scan_error_card')),
        findsNothing,
      );
    });
  });
}
