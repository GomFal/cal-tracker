import 'package:cal_tracker_mobile/app/theme.dart';
import 'package:cal_tracker_mobile/data/repositories/nutrition_repository.dart';
import 'package:cal_tracker_mobile/data/services/audio_recorder_service.dart';
import 'package:cal_tracker_mobile/domain/models/nutrition_models.dart';
import 'package:cal_tracker_mobile/ui/features/voice_log/view_models/voice_log_view_model.dart';
import 'package:cal_tracker_mobile/ui/features/voice_log/views/voice_log_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockNutritionRepository extends Mock implements NutritionRepository {}

class MockAudioRecorderService extends Mock implements AudioRecorderService {}

void main() {
  group('MealCreateScreen food candidates', () {
    late MockNutritionRepository nutritionRepository;
    late MockAudioRecorderService audioRecorderService;
    late VoiceLogViewModel viewModel;

    setUp(() {
      nutritionRepository = MockNutritionRepository();
      audioRecorderService = MockAudioRecorderService();
      when(() => audioRecorderService.dispose()).thenAnswer((_) async {});
      when(
        () => audioRecorderService.stateStream,
      ).thenAnswer((_) => const Stream.empty());
      viewModel = VoiceLogViewModel(
        nutritionRepository: nutritionRepository,
        audioRecorderService: audioRecorderService,
      );
    });

    tearDown(() {
      viewModel.dispose();
    });

    testWidgets('renders compact top 10 candidates without overflow', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final group = _candidateGroup(
        canonicalEnglishName: 'very_long_food',
        candidates: [
          for (var index = 0; index < 10; index++)
            _mealItem(
              name:
                  'Very long branded food candidate number ${index + 1} with extra descriptive words',
              calories: 100 + index,
              externalId: 'long_food_${index + 1}',
            ),
        ],
      );
      when(() => nutritionRepository.logText('long food')).thenAnswer(
        (_) async => AgentRunResult(
          kind: 'clarification_required',
          message: 'Choose a food match.',
          candidateGroups: [group],
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<VoiceLogViewModel>.value(
          value: viewModel,
          child: MaterialApp(
            theme: buildTheme(),
            home: const MealCreateScreen(),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('meal_text_field')),
        'long food',
      );
      await tester.tap(find.byKey(const ValueKey('submit_meal_button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('food_candidate_very_long_food_0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('food_candidate_very_long_food_9')),
        findsNothing,
      );

      final toggleFinder = find.byKey(
        const ValueKey('food_candidate_toggle_very_long_food'),
      );
      await tester.ensureVisible(toggleFinder);
      await tester.pumpAndSettle();
      await tester.tap(toggleFinder);
      await tester.pumpAndSettle();
      final candidateNineFinder = find.byKey(
        const ValueKey('food_candidate_very_long_food_9'),
      );
      await tester.ensureVisible(candidateNineFinder);
      await tester.pumpAndSettle();

      expect(candidateNineFinder, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps candidate options in proposal editor', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final group = _candidateGroup(
        canonicalEnglishName: 'chicken_breast',
        candidates: [
          for (var index = 0; index < 10; index++)
            _mealItem(
              name: 'Chicken candidate ${index + 1}',
              calories: 100 + index,
              externalId: 'chicken_${index + 1}',
            ),
        ],
      );
      final proposal = MealProposal(
        id: 'prop_chicken',
        title: 'Chicken',
        confidence: 0.82,
        requiresConfirmation: true,
        trustedAutoCommitEligible: false,
        nutrition: const NutritionSnapshot(
          calories: 100,
          proteinGrams: 7,
          carbsGrams: 1,
          fatGrams: 8,
        ),
        items: [group.candidates.first],
      );
      when(() => nutritionRepository.logText('chicken')).thenAnswer(
        (_) async => AgentRunResult(
          kind: 'clarification_required',
          message: 'Choose a food match.',
          candidateGroups: [group],
        ),
      );
      when(
        () => nutritionRepository.createProposalFromItems(
          phrase: any(named: 'phrase'),
          items: any(named: 'items'),
        ),
      ).thenAnswer((_) async => proposal);

      await tester.pumpWidget(
        ChangeNotifierProvider<VoiceLogViewModel>.value(
          value: viewModel,
          child: MaterialApp(
            theme: buildTheme(),
            home: const MealCreateScreen(),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('meal_text_field')),
        'chicken',
      );
      await tester.tap(find.byKey(const ValueKey('submit_meal_button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('food_candidate_chicken_breast_0')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit_proposal_button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('proposal_item_0_candidate_0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('proposal_item_0_candidate_9')),
        findsNothing,
      );
      final editorToggleFinder = find.byKey(
        const ValueKey('proposal_item_0_candidate_toggle'),
      );
      await tester.ensureVisible(editorToggleFinder);
      await tester.pumpAndSettle();
      await tester.tap(editorToggleFinder);
      await tester.pumpAndSettle();
      final editorCandidateNineFinder = find.byKey(
        const ValueKey('proposal_item_0_candidate_9'),
      );
      await tester.ensureVisible(editorCandidateNineFinder);
      await tester.pumpAndSettle();
      expect(editorCandidateNineFinder, findsOneWidget);
      expect(
        find.byKey(const ValueKey('proposal_item_calories_0')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('proposal_item_protein_0')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('edit_proposal_item_nutrition_0')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('proposal_nutrition_calories')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('proposal_nutrition_protein')),
        findsOneWidget,
      );
    });

    testWidgets('shows proposal item canonical names in request language', (
      tester,
    ) async {
      final proposal = MealProposal(
        id: 'prop_pan',
        title: 'Pan',
        confidence: 0.82,
        requiresConfirmation: true,
        trustedAutoCommitEligible: false,
        nutrition: const NutritionSnapshot(
          calories: 265,
          proteinGrams: 9,
          carbsGrams: 49,
          fatGrams: 3,
        ),
        items: [
          _mealItem(
            name: 'Bread, white, commercially prepared',
            canonicalName: 'pan',
            calories: 265,
            externalId: '501',
          ),
        ],
      );
      when(() => nutritionRepository.logText('100 gramos de pan')).thenAnswer(
        (_) async => AgentRunResult(
          kind: 'proposal',
          message: 'Meal proposal created.',
          proposal: proposal,
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<VoiceLogViewModel>.value(
          value: viewModel,
          child: MaterialApp(
            theme: buildTheme(),
            home: const MealCreateScreen(),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('meal_text_field')),
        '100 gramos de pan',
      );
      await tester.tap(find.byKey(const ValueKey('submit_meal_button')));
      await tester.pumpAndSettle();

      expect(find.text('pan 100 g'), findsOneWidget);
      expect(
        find.textContaining('Bread, white, commercially prepared'),
        findsNothing,
      );
    });

    testWidgets(
      'keeps text correction controls available for active proposal',
      (tester) async {
        const initialProposal = MealProposal(
          id: 'prop_1',
          title: 'Bread and butter',
          confidence: 0.85,
          requiresConfirmation: true,
          trustedAutoCommitEligible: false,
          nutrition: NutritionSnapshot(
            calories: 408,
            proteinGrams: 9.2,
            carbsGrams: 49,
            fatGrams: 19.4,
          ),
          items: [],
        );
        const updatedProposal = MealProposal(
          id: 'prop_1',
          title: 'Bread and butter',
          confidence: 0.85,
          requiresConfirmation: true,
          trustedAutoCommitEligible: false,
          nutrition: NutritionSnapshot(
            calories: 552,
            proteinGrams: 9.4,
            carbsGrams: 49,
            fatGrams: 35.6,
          ),
          items: [],
        );
        when(() => nutritionRepository.logText('bread and butter')).thenAnswer(
          (_) async => const AgentRunResult(
            kind: 'proposal',
            message: 'Meal proposal created.',
            proposal: initialProposal,
          ),
        );
        when(
          () => nutritionRepository.logText(
            'make the butter 40 grams',
            activeProposalId: 'prop_1',
          ),
        ).thenAnswer(
          (_) async => const AgentRunResult(
            kind: 'proposal',
            message: 'Meal proposal updated.',
            proposal: updatedProposal,
          ),
        );

        await tester.pumpWidget(
          ChangeNotifierProvider<VoiceLogViewModel>.value(
            value: viewModel,
            child: MaterialApp(
              theme: buildTheme(),
              home: const MealCreateScreen(),
            ),
          ),
        );

        await tester.enterText(
          find.byKey(const ValueKey('meal_text_field')),
          'bread and butter',
        );
        await tester.tap(find.byKey(const ValueKey('submit_meal_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('meal_text_field')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('submit_meal_button')),
          findsOneWidget,
        );
        expect(viewModel.proposal, initialProposal);

        await tester.enterText(
          find.byKey(const ValueKey('meal_text_field')),
          'make the butter 40 grams',
        );
        await tester.tap(find.byKey(const ValueKey('submit_meal_button')));
        await tester.pumpAndSettle();

        expect(viewModel.proposal, updatedProposal);
        verify(
          () => nutritionRepository.logText(
            'make the butter 40 grams',
            activeProposalId: 'prop_1',
          ),
        ).called(1);
      },
    );
  });
}

FoodCandidateGroup _candidateGroup({
  required String canonicalEnglishName,
  required List<MealItem> candidates,
}) {
  return FoodCandidateGroup(
    mention: FoodMention(
      originalText: canonicalEnglishName,
      canonicalEnglishName: canonicalEnglishName,
      quantity: 100,
      unit: 'g',
      confidence: 0.9,
      marketProduct: false,
    ),
    candidates: candidates,
  );
}

MealItem _mealItem({
  required String name,
  required int calories,
  required String externalId,
  String? canonicalName,
}) {
  return MealItem(
    name: name,
    quantity: 100,
    unit: 'g',
    calories: calories,
    proteinGrams: 7,
    carbsGrams: 1,
    fatGrams: 8,
    source: 'open_food_facts',
    externalSource: 'Open Food Facts',
    externalId: externalId,
    canonicalName: canonicalName,
    license: 'CC BY-SA',
    confidence: 0.91,
    resolvedGrams: 100,
  );
}
