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
    this.overrideDraft,
  }) : super(
          nutritionRepository: _dummyRepository,
          initializeCamera: () async {},
          takePicture: () async => '',
          recognizeText: (_) async => '',
        );

  static final _dummyRepository = _NutritionRepositoryStub();

  UsualFoodScanPhase overridePhase;
  UsualFoodScanError overrideErrorCode;
  bool overrideIsBusy;
  UsualFoodDraft? overrideDraft;

  int captureAndProcessCallCount = 0;
  int retryCallCount = 0;

  @override
  UsualFoodScanPhase get phase => overridePhase;

  @override
  UsualFoodScanError get errorCode => overrideErrorCode;

  @override
  bool get isBusy => overrideIsBusy;

  @override
  UsualFoodDraft? get draft => overrideDraft;

  @override
  Future<void> captureAndProcess() async {
    captureAndProcessCallCount++;
    // Simulate a successful scan: set phase to drafted and set a default
    // draft so the screen's listener can pop on phase change.
    if (overridePhase == UsualFoodScanPhase.ready) {
      overridePhase = UsualFoodScanPhase.drafted;
      overrideDraft ??= const UsualFoodDraft(name: 'Scanned Food');
      notifyListeners();
    }
  }

  @override
  void retry() {
    retryCallCount++;
    overridePhase = UsualFoodScanPhase.ready;
    notifyListeners();
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
    testWidgets('shows close button, capture button and hint on ready',
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
        find.byKey(const ValueKey('usual_food_scan_error_card')),
        findsNothing,
      );
    });

    testWidgets('capture button triggers captureAndProcess', (tester) async {
      final vm = FakeUsualFoodScanViewModel(
        overridePhase: UsualFoodScanPhase.ready,
      );
      await tester.pumpWidget(buildAppWithVm(vm));

      await tester.tap(
        find.byKey(const ValueKey('usual_food_scan_capture_button')),
      );
      expect(vm.captureAndProcessCallCount, 1);
    });

    testWidgets('error phase shows card, retry and cancel buttons',
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
      // Capture button hidden
      expect(
        find.byKey(const ValueKey('usual_food_scan_capture_button')),
        findsNothing,
      );
    });

    testWidgets('retry transitions back to ready and shows capture',
        (tester) async {
      final vm = FakeUsualFoodScanViewModel(
        overridePhase: UsualFoodScanPhase.error,
        overrideErrorCode: UsualFoodScanError.cameraDenied,
      );
      await tester.pumpWidget(buildAppWithVm(vm));

      // Tap retry
      await tester.ensureVisible(
        find.byKey(const ValueKey('usual_food_scan_retry_button')),
      );
      await tester.tap(
        find.byKey(const ValueKey('usual_food_scan_retry_button')),
      );
      await tester.pump(); // process VM notification

      expect(vm.retryCallCount, 1);
      expect(
        find.byKey(const ValueKey('usual_food_scan_capture_button')),
        findsOneWidget,
      );
    });

    testWidgets('shows spinner and label during OCR processing',
        (tester) async {
      final vm = FakeUsualFoodScanViewModel(
        overridePhase: UsualFoodScanPhase.ocrProcessing,
        overrideIsBusy: true,
      );
      await tester.pumpWidget(buildAppWithVm(vm));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // The ARB en key contains "Reading text…" — the screen reads via l10n
      expect(find.text('Reading text…'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('usual_food_scan_capture_button')),
        findsNothing,
      );
    });

    testWidgets('shows spinner and label during drafting', (tester) async {
      final vm = FakeUsualFoodScanViewModel(
        overridePhase: UsualFoodScanPhase.drafting,
        overrideIsBusy: true,
      );
      await tester.pumpWidget(buildAppWithVm(vm));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Filling fields…'), findsOneWidget);
    });

    testWidgets('drafted phase hides controls', (tester) async {
      final vm = FakeUsualFoodScanViewModel(
        overridePhase: UsualFoodScanPhase.drafted,
      );
      await tester.pumpWidget(buildAppWithVm(vm));

      expect(
        find.byKey(const ValueKey('usual_food_scan_capture_button')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('usual_food_scan_error_card')),
        findsNothing,
      );
    });
  });
}
