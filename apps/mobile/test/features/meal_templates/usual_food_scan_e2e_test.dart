// End-to-end test for the "scan nutrition label" flow.
//
// Exercises the full user journey without an emulator, Marionette, or
// Patrol. We drive the Flutter widget tree with `WidgetTester` and stub
// the camera, the ML Kit text recognizer, and the backend draft endpoint
// at the ViewModel boundary.
//
// The flow under test:
//   1. Open the UsualFoodEditorScreen ("Add usual ingredient" form).
//   2. The "Scan from photo" CTA is visible inside the form.
//   3. Tap the CTA → push UsualFoodScanScreen on the navigator.
//   4. The scan screen mounts with a fake VM in `ready` phase.
//   5. Tap "Capture" → the fake VM advances to `previewing` and stores
//      a fake file path. The screen shows the still-image preview with
//      "Use this photo" / "Retake" buttons.
//   6. Tap "Use this photo" → the fake VM runs OCR + draft and pops with
//      a UsualFoodDraft.
//   7. The editor receives the draft, applies it, and the form fields
//      are populated with the values from the draft.
//   8. Tap "Save" → the fake repository's `createUsualFood` is called
//      with those values.

import 'package:cal_tracker_mobile/data/repositories/nutrition_repository.dart';
import 'package:cal_tracker_mobile/domain/models/nutrition_models.dart';
import 'package:cal_tracker_mobile/l10n/generated/app_localizations.dart';
import 'package:cal_tracker_mobile/ui/features/meal_templates/view_models/meal_templates_view_model.dart';
import 'package:cal_tracker_mobile/ui/features/meal_templates/view_models/usual_food_scan_view_model.dart';
import 'package:cal_tracker_mobile/ui/features/meal_templates/views/usual_food_editor_screen.dart';
import 'package:cal_tracker_mobile/ui/features/meal_templates/views/usual_food_scan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class _FakeRepo extends Mock implements NutritionRepository {}

class _FakeUsualFoodInput extends Fake implements UsualFoodInput {}

// Fake VM that drives the full flow synchronously when the screen calls
// capture() / confirmCapture(). It is wired into UsualFoodScanScreen via
// the `testViewModelFactory` hook.
//
// The screen normally wires its own `onDrafted` callback in
// `_buildViewModel` to pop the navigator with the draft. When the
// factory is used, `_buildViewModel` short-circuits before wiring the
// callback, so the test must install its own pop callback via
// [onPoppedForTest].
class _FakeScanViewModel extends UsualFoodScanViewModel {
  _FakeScanViewModel({
    required this.fakeCapturedFilePath,
    required this.draftToReturn,
    required this.repository,
  }) : super(
          nutritionRepository: repository,
          initializeCamera: () async {},
          takePicture: () async => fakeCapturedFilePath,
          pausePreview: () async {},
          resumePreview: () async {},
          recognizeText: (_) async => 'Calories 250\nProtein 8g\nCarbs 40g\nFat 6g',
          deleteCapturedFile: (_) async {},
        );

  final String fakeCapturedFilePath;
  final UsualFoodDraft draftToReturn;
  final NutritionRepository repository;

  /// Callback the test sets to receive the popped draft.
  void Function(UsualFoodDraft draft)? onPoppedForTest;

  @override
  Future<void> capture() async {
    // Replicate the production VM: ready → capturing → previewing,
    // store the file path, notify listeners.
    setUiStateForTest(
      UsualFoodScanUiState(
        phase: UsualFoodScanPhase.previewing,
        capturedFilePath: fakeCapturedFilePath,
      ),
    );
  }

  @override
  Future<void> confirmCapture() async {
    // Replicate the production VM: previewing → ocrProcessing →
    // drafting → drafted.
    setUiStateForTest(
      UsualFoodScanUiState(
        phase: UsualFoodScanPhase.ocrProcessing,
        capturedFilePath: fakeCapturedFilePath,
      ),
    );
    draft = draftToReturn;
    setUiStateForTest(
      UsualFoodScanUiState(
        phase: UsualFoodScanPhase.drafted,
        capturedFilePath: fakeCapturedFilePath,
        ocrText: 'Calories 250\nProtein 8g\nCarbs 40g\nFat 6g',
      ),
    );
    onPoppedForTest?.call(draftToReturn);
  }
}

Widget _wrap({
  required Widget child,
  required NutritionRepository repository,
}) {
  final router = GoRouter(
    initialLocation: '/editor',
    routes: [
      GoRoute(
        path: '/editor',
        builder: (context, state) => child,
      ),
    ],
  );
  return MaterialApp.router(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: router,
    builder: (context, routerChild) {
      return MultiProvider(
        providers: [
          Provider<NutritionRepository>.value(value: repository),
          ChangeNotifierProvider<MealTemplatesViewModel>(
            create: (_) => MealTemplatesViewModel(
              nutritionRepository: repository,
            )..load(forceRefresh: false),
          ),
        ],
        child: routerChild,
      );
    },
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeUsualFoodInput());
  });

  testWidgets(
    'Scan from photo: full flow fills editor and saves',
    (tester) async {
      // -----------------------------------------------------------------
      // Arrange: fake repository + draft to be returned by OCR/LLM.
      // -----------------------------------------------------------------
      final repo = _FakeRepo();
      when(() => repo.dataChanges).thenAnswer((_) => const Stream.empty());
      const draft = UsualFoodDraft(
        name: 'Greek Yogurt Fage',
        brand: 'Fage',
        servingGrams: 100,
        calories: 97,
        proteinGrams: 10,
        carbsGrams: 4,
        fatGrams: 5,
        nutrients: {'saltGrams': 0.1, 'fiberGrams': 0.0},
      );

      when(() => repo.draftUsualFood(any())).thenAnswer((_) async => draft);
      when(() => repo.createUsualFood(any())).thenAnswer((invocation) async {
        final input = invocation.positionalArguments.first as UsualFoodInput;
        return UsualFood(
          id: 'food-new',
          name: input.name,
          brand: input.brand,
          servingGrams: input.servingGrams,
          nutrition: input.nutrition,
          nutrients: input.nutrients,
          aliases: input.aliases,
        );
      });
      when(() => repo.getTemplates()).thenAnswer((_) async => const []);
      when(() => repo.getUsualFoods()).thenAnswer((_) async => const []);
      when(() => repo.refreshTemplates(force: any(named: 'force')))
          .thenAnswer((_) async => const []);
      when(() => repo.refreshUsualFoods(force: any(named: 'force')))
          .thenAnswer((_) async => const []);
      when(() => repo.cachedTemplates())
          .thenAnswer((_) async => null);
      when(() => repo.cachedUsualFoods())
          .thenAnswer((_) async => null);
      when(() => repo.putCachedTemplates(any()))
          .thenAnswer((_) async {});
      when(() => repo.putCachedUsualFoods(any()))
          .thenAnswer((_) async {});

      // -----------------------------------------------------------------
      // The scan screen reads testViewModelFactory at build time to decide
      // which VM to instantiate. Wire the fake VM before pumping the
      // editor so the CTA's push picks it up.
      // -----------------------------------------------------------------
      late _FakeScanViewModel fakeVm;
      fakeVm = _FakeScanViewModel(
        fakeCapturedFilePath: '/tmp/fake_capture.jpg',
        draftToReturn: draft,
        repository: repo,
      );
      testViewModelFactory = (context) {
        // Install a pop callback that mirrors what the production
        // _buildViewModel wires up (Navigator.pop with the draft).
        fakeVm.onPoppedForTest = (d) => Navigator.of(context).pop(d);
        return fakeVm;
      };
      addTearDown(() => testViewModelFactory = null);

      await tester.binding.setSurfaceSize(const Size(600, 900));

      await tester.pumpWidget(
        _wrap(
          repository: repo,
          child: const UsualFoodEditorScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // -----------------------------------------------------------------
      // 1. The "Scan from photo" CTA is visible inside the form.
      // -----------------------------------------------------------------
      final cta = find.byKey(const ValueKey('usual_food_scan_from_photo_cta'));
      expect(cta, findsOneWidget);

      // -----------------------------------------------------------------
      // 2. Tap the CTA → the scan screen is pushed.
      // -----------------------------------------------------------------
      await tester.ensureVisible(cta);
      await tester.tap(cta);
      await tester.pumpAndSettle();

      // The scan screen's close button is now on stage.
      expect(
        find.byKey(const ValueKey('usual_food_scan_close_button')),
        findsOneWidget,
      );
      // The capture button is visible (fake VM is in `ready`).
      expect(
        find.byKey(const ValueKey('usual_food_scan_capture_button')),
        findsOneWidget,
      );

      // -----------------------------------------------------------------
      // 3. Tap "Capture" → fake VM advances to previewing. The still
      //    image surface + confirm / retake buttons appear.
      // -----------------------------------------------------------------
      await tester.tap(
        find.byKey(const ValueKey('usual_food_scan_capture_button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('usual_food_scan_still_preview')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('usual_food_scan_confirm_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('usual_food_scan_retake_button')),
        findsOneWidget,
      );

      // -----------------------------------------------------------------
      // 4. Tap "Use this photo" → fake VM runs OCR + draft, screen pops
      //    with the draft, editor applies it via _applyDraft.
      // -----------------------------------------------------------------
      await tester.tap(
        find.byKey(const ValueKey('usual_food_scan_confirm_button')),
      );
      await tester.pumpAndSettle();

      // We are back on the editor — the form fields reflect the draft.
      expect(
        find.byKey(const ValueKey('usual_food_scan_close_button')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('usual_food_name_field')),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextFormField, 'Greek Yogurt Fage'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextFormField, 'Fage'),
        findsOneWidget,
      );
      // Numeric fields — values from the draft.
      expect(
        find.widgetWithText(TextFormField, '100'),
        findsOneWidget,
      ); // servingGrams
      expect(
        find.widgetWithText(TextFormField, '97'),
        findsOneWidget,
      ); // calories
      expect(
        find.widgetWithText(TextFormField, '10'),
        findsOneWidget,
      ); // protein
      expect(
        find.widgetWithText(TextFormField, '4'),
        findsOneWidget,
      ); // carbs
      expect(
        find.widgetWithText(TextFormField, '5'),
        findsOneWidget,
      ); // fat

      // -----------------------------------------------------------------
      // 5. Save the form. The fake repository's createUsualFood is called
      //    with the values from the draft.
      // -----------------------------------------------------------------
      final saveButton = find.byKey(const ValueKey('usual_food_save_button'));
      expect(saveButton, findsOneWidget);
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      final captured = verify(() => repo.createUsualFood(captureAny())).captured;
      expect(captured, hasLength(1));
      final input = captured.first as UsualFoodInput;
      expect(input.name, 'Greek Yogurt Fage');
      expect(input.brand, 'Fage');
      expect(input.servingGrams, 100);
      expect(input.nutrition.calories, 97);
      expect(input.nutrition.proteinGrams, 10);
      expect(input.nutrition.carbsGrams, 4);
      expect(input.nutrition.fatGrams, 5);
      expect(input.nutrients['saltGrams'], 0.1);
    },
  );
}
