import 'dart:io';

import 'package:cal_tracker_mobile/app/theme.dart';
import 'package:cal_tracker_mobile/data/repositories/nutrition_repository.dart';
import 'package:cal_tracker_mobile/data/services/audio_recorder_service.dart';
import 'package:cal_tracker_mobile/domain/models/nutrition_models.dart';
import 'package:cal_tracker_mobile/l10n/generated/app_localizations.dart';
import 'package:cal_tracker_mobile/ui/features/voice_log/view_models/voice_log_view_model.dart';
import 'package:cal_tracker_mobile/ui/features/voice_log/views/voice_log_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockNutritionRepository extends Mock implements NutritionRepository {}

class MockAudioRecorderService extends Mock implements AudioRecorderService {}

class FakeFile extends Fake implements File {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeFile());
  });

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

    testWidgets(
        'starts voice-only and keeps voice action while reviewing a proposal',
        (tester) async {
      final proposal = MealProposal(
        id: 'prop_chicken_rice',
        title: 'Chicken and rice',
        confidence: 0.85,
        requiresConfirmation: true,
        trustedAutoCommitEligible: false,
        nutrition: const NutritionSnapshot(
          calories: 295,
          proteinGrams: 38,
          carbsGrams: 29,
          fatGrams: 4,
        ),
        items: [
          _mealItem(
            name: 'Chicken breast',
            calories: 165,
            externalId: 'chicken',
          ),
          _mealItem(
            name: 'Cooked rice',
            calories: 130,
            externalId: 'rice',
          ),
        ],
      );
      when(() => audioRecorderService.start()).thenAnswer((_) async {});
      when(() => audioRecorderService.stop()).thenAnswer(
        (_) async => const RecordedAudio(
          path: '/tmp/test.m4a',
          mimeType: 'audio/m4a',
          sizeBytes: 1024,
        ),
      );
      when(() => nutritionRepository.logAudio(any())).thenAnswer(
        (_) async => VoiceMealRunResult(
          transcript: 'chicken and rice',
          provider: 'test',
          model: 'test-model',
          traceId: 'trace-1',
          result: AgentRunResult(
            kind: 'proposal',
            message: 'Meal proposal created.',
            proposal: proposal,
          ),
        ),
      );
      final hapticCalls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            hapticCalls.add(call.arguments as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<VoiceLogViewModel>.value(
          value: viewModel,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildTheme(),
            home: const MealCreateScreen(),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('meal_text_field')), findsNothing);
      expect(find.byKey(const ValueKey('submit_meal_button')), findsNothing);
      expect(
        find.byKey(const ValueKey('meal_create_voice_action_button')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('mic_button')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('mic_button')));
      await tester.pump();

      expect(viewModel.state, VoiceLogState.recording);
      expect(hapticCalls, contains('HapticFeedbackType.lightImpact'));
      expect(find.byKey(const ValueKey('voice_action_recording_pulse')),
          findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('mic_button')));
      await tester.pumpAndSettle();

      expect(hapticCalls, contains('HapticFeedbackType.mediumImpact'));
      expect(find.text('Chicken and rice'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('voice_transcript_card')),
        findsOneWidget,
      );
      expect(find.text('I heard:'), findsOneWidget);
      expect(find.text('chicken and rice'), findsOneWidget);
      expect(find.byKey(const ValueKey('confirm_proposal_button')),
          findsOneWidget);
      expect(
          find.byKey(const ValueKey('edit_proposal_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('meal_text_field')), findsNothing);
      expect(find.byKey(const ValueKey('submit_meal_button')), findsNothing);
      expect(
        find.byKey(const ValueKey('meal_create_voice_action_button')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('mic_button')), findsOneWidget);

      await tester
          .tap(find.byKey(const ValueKey('voice_log_start_over_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('meal_text_field')), findsNothing);
      expect(find.byKey(const ValueKey('submit_meal_button')), findsNothing);
      expect(
        find.byKey(const ValueKey('voice_transcript_card')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('mic_button')), findsOneWidget);
    });

    testWidgets(
      'does not show voice transcript during text clarification',
      (tester) async {
        const transcript =
            'Añade 100 gramos de arroz, 100 gramos de pollo y 100 gramos de pan.';
        final group = _candidateGroup(
          canonicalEnglishName: 'arroz',
          candidates: const [],
        );
        when(() => nutritionRepository.logText(transcript)).thenAnswer(
          (_) async => AgentRunResult(
            kind: 'clarification_required',
            message:
                'I could not confidently match every ingredient. Please choose a food match or rephrase the meal.',
            candidateGroups: [group],
          ),
        );

        await tester.pumpWidget(
          ChangeNotifierProvider<VoiceLogViewModel>.value(
            value: viewModel,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: buildTheme(),
              home: const MealCreateScreen(),
            ),
          ),
        );

        await viewModel.submitText(transcript);
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('meal_text_field')), findsNothing);
        expect(find.byKey(const ValueKey('submit_meal_button')), findsNothing);
        expect(
          find.byKey(const ValueKey('voice_transcript_card')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('resolver_clarification_card')),
          findsOneWidget,
        );
      },
    );

    testWidgets('searches manual foods and creates a proposal', (tester) async {
      final bread = _mealItem(
        name: 'Bread',
        calories: 265,
        externalId: 'bread',
      );
      final proposal = MealProposal(
        id: 'prop_bread',
        title: 'Bread',
        confidence: 0.9,
        requiresConfirmation: true,
        trustedAutoCommitEligible: false,
        nutrition: const NutritionSnapshot(
          calories: 265,
          proteinGrams: 7,
          carbsGrams: 1,
          fatGrams: 8,
        ),
        items: [bread],
      );
      when(() => nutritionRepository.searchFoods('bread', limit: 10))
          .thenAnswer(
        (_) async => FoodSearchResult(items: [bread]),
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
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildTheme(),
            home: const MealCreateScreen(),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('manual_food_search_panel')),
          findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('manual_food_search_field')),
        'bread',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('manual_food_search_result_button_0')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('manual_food_draft_item_0')),
          findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('manual_food_review_meal_button')),
      );
      final reviewButton =
          find.byKey(const ValueKey('manual_food_review_meal_button'));
      await tester.tapAt(tester.getCenter(reviewButton) - const Offset(180, 0));
      await tester.pumpAndSettle();

      final captured = verify(
        () => nutritionRepository.createProposalFromItems(
          phrase: any(named: 'phrase'),
          items: captureAny(named: 'items'),
        ),
      ).captured.single as List<MealItem>;
      expect(captured.single.name, 'Bread');
      expect(find.text('Bread'), findsWidgets);
      expect(find.byKey(const ValueKey('confirm_proposal_button')),
          findsOneWidget);
    });

    testWidgets(
      'uses manual search to resolve an ingredient without candidates',
      (tester) async {
        final bread = _mealItem(
          name: 'Bread',
          calories: 265,
          externalId: 'bread',
        );
        final group = _candidateGroup(
          canonicalEnglishName: 'red meat',
          candidates: const [],
        );
        final proposal = MealProposal(
          id: 'prop_bread',
          title: 'Bread',
          confidence: 0.9,
          requiresConfirmation: true,
          trustedAutoCommitEligible: false,
          nutrition: const NutritionSnapshot(
            calories: 265,
            proteinGrams: 7,
            carbsGrams: 1,
            fatGrams: 8,
          ),
          items: [bread],
        );
        when(() => nutritionRepository.logText('red meat')).thenAnswer(
          (_) async => AgentRunResult(
            kind: 'clarification_required',
            message: 'Choose a food match.',
            candidateGroups: [group],
          ),
        );
        when(() => nutritionRepository.searchFoods('red meat', limit: 10))
            .thenAnswer((_) async => const FoodSearchResult(items: []));
        when(() => nutritionRepository.searchFoods('bread', limit: 10))
            .thenAnswer((_) async => FoodSearchResult(items: [bread]));
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
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: buildTheme(),
              home: const MealCreateScreen(),
            ),
          ),
        );

        await viewModel.submitText('red meat');
        await tester.pumpAndSettle();
        expect(
          find.byKey(
            const ValueKey('clarification_food_search_red meat_field'),
          ),
          findsOneWidget,
        );

        await tester.enterText(
          find.byKey(
            const ValueKey('clarification_food_search_red meat_field'),
          ),
          'bread',
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            const ValueKey(
              'clarification_food_search_red meat_result_button_0',
            ),
          ),
        );
        await tester.pumpAndSettle();

        verify(
          () => nutritionRepository.createProposalFromItems(
            phrase: any(named: 'phrase'),
            items: any(named: 'items'),
          ),
        ).called(1);
        expect(find.byKey(const ValueKey('confirm_proposal_button')),
            findsOneWidget);
      },
    );

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
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildTheme(),
            home: const MealCreateScreen(),
          ),
        ),
      );

      await viewModel.submitText('long food');
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

    testWidgets('does not show food matches after a proposal is created', (
      tester,
    ) async {
      final group = _candidateGroup(
        canonicalEnglishName: 'chicken',
        candidates: [
          for (var index = 0; index < 10; index++)
            _mealItem(
              name: 'Chicken candidate ${index + 1}',
              calories: 200 + index,
              externalId: 'chicken_${index + 1}',
            ),
        ],
      );
      final proposal = MealProposal(
        id: 'prop_chicken_bread_butter',
        title: 'Chicken, bread and butter',
        confidence: 0.86,
        requiresConfirmation: true,
        trustedAutoCommitEligible: false,
        nutrition: const NutritionSnapshot(
          calories: 1097,
          proteinGrams: 41,
          carbsGrams: 49,
          fatGrams: 88,
        ),
        items: [
          group.candidates.first,
          _mealItem(
            name: 'Bread, rye',
            calories: 259,
            externalId: 'bread_rye',
          ),
          _mealItem(
            name: 'Butter',
            calories: 717,
            externalId: 'butter',
          ),
        ],
      );
      when(() => nutritionRepository.logText('chicken bread butter'))
          .thenAnswer(
        (_) async => AgentRunResult(
          kind: 'proposal',
          message: 'Meal proposal created.',
          proposal: proposal,
          candidateGroups: [group],
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<VoiceLogViewModel>.value(
          value: viewModel,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildTheme(),
            home: const MealCreateScreen(),
          ),
        ),
      );

      await viewModel.submitText('chicken bread butter');
      await tester.pumpAndSettle();

      expect(viewModel.state, VoiceLogState.proposalReady);
      expect(find.text('Chicken, bread and butter'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('resolver_clarification_card')),
        findsNothing,
      );
      expect(find.text('Food matches'), findsNothing);

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

      final candidateNineFinder = find.byKey(
        const ValueKey('proposal_item_0_candidate_9'),
      );
      await tester.ensureVisible(candidateNineFinder);
      await tester.pumpAndSettle();
      expect(candidateNineFinder, findsOneWidget);
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
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildTheme(),
            home: const MealCreateScreen(),
          ),
        ),
      );

      await viewModel.submitText('chicken');
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

    testWidgets('searches a replacement in the proposal editor', (
      tester,
    ) async {
      final chicken = _mealItem(
        name: 'Chicken breast',
        calories: 165,
        externalId: 'chicken',
      ).copyWith(quantity: 150, calories: 248, proteinGrams: 46.5);
      final bread = _mealItem(
        name: 'Bread',
        calories: 265,
        externalId: 'bread',
      );
      final breadReplacement = bread.copyWith(
        quantity: 150,
        calories: 398,
        proteinGrams: 10.5,
        carbsGrams: 1.5,
        fatGrams: 12,
      );
      final proposal = MealProposal(
        id: 'prop_chicken',
        title: 'Chicken',
        confidence: 0.82,
        requiresConfirmation: true,
        trustedAutoCommitEligible: false,
        nutrition: const NutritionSnapshot(
          calories: 248,
          proteinGrams: 46.5,
          carbsGrams: 1,
          fatGrams: 8,
        ),
        items: [chicken],
      );
      final updatedProposal = MealProposal(
        id: 'prop_chicken',
        title: 'Bread',
        confidence: 0.82,
        requiresConfirmation: true,
        trustedAutoCommitEligible: false,
        nutrition: const NutritionSnapshot(
          calories: 398,
          proteinGrams: 10.5,
          carbsGrams: 1.5,
          fatGrams: 12,
        ),
        items: [breadReplacement],
      );
      when(() => nutritionRepository.logText('chicken')).thenAnswer(
        (_) async => AgentRunResult(
          kind: 'proposal',
          message: 'Meal proposal created.',
          proposal: proposal,
        ),
      );
      when(() => nutritionRepository.searchFoods('Chicken breast', limit: 10))
          .thenAnswer((_) async => const FoodSearchResult(items: []));
      when(() => nutritionRepository.searchFoods('bread', limit: 10))
          .thenAnswer((_) async => FoodSearchResult(items: [bread]));
      when(
        () => nutritionRepository.updateProposalItems(
          'prop_chicken',
          any(),
        ),
      ).thenAnswer((_) async => updatedProposal);

      await tester.pumpWidget(
        ChangeNotifierProvider<VoiceLogViewModel>.value(
          value: viewModel,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildTheme(),
            home: const MealCreateScreen(),
          ),
        ),
      );

      await viewModel.submitText('chicken');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit_proposal_button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('proposal_item_0_search_toggle')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('proposal_item_0_search_field')),
        'bread',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('proposal_item_0_search_result_button_0')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('save_proposal_edits_button')),
      );
      await tester
          .tap(find.byKey(const ValueKey('save_proposal_edits_button')));
      await tester.pumpAndSettle();

      final captured = verify(
        () => nutritionRepository.updateProposalItems(
          'prop_chicken',
          captureAny(),
        ),
      ).captured.single as List<MealItem>;
      expect(captured.single.name, 'Bread');
      expect(captured.single.quantity, 150);
      expect(captured.single.calories, 398);
      expect(find.text('Bread'), findsWidgets);
      await tester.pump(VoiceLogViewModel.proposalChangeSuccessDuration);
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
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildTheme(),
            home: const MealCreateScreen(),
          ),
        ),
      );

      await viewModel.submitText('100 gramos de pan');
      await tester.pumpAndSettle();

      expect(find.text('pan 100 g'), findsOneWidget);
      expect(
        find.textContaining('Bread, white, commercially prepared'),
        findsNothing,
      );
    });

    testWidgets('saving proposal edits without changes does not show success', (
      tester,
    ) async {
      final item = _mealItem(
        name: 'Rice, white, medium-grain, enriched, cooked',
        canonicalName: 'rice',
        calories: 130,
        externalId: 'rice',
      );
      final proposal = MealProposal(
        id: 'prop_rice',
        title: 'Rice',
        confidence: 0.85,
        requiresConfirmation: true,
        trustedAutoCommitEligible: false,
        nutrition: const NutritionSnapshot(
          calories: 130,
          proteinGrams: 2.7,
          carbsGrams: 28,
          fatGrams: 0.3,
        ),
        items: [item],
      );
      when(() => nutritionRepository.logText('rice')).thenAnswer(
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
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildTheme(),
            home: const MealCreateScreen(),
          ),
        ),
      );

      await viewModel.submitText('rice');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit_proposal_button')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('save_proposal_edits_button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('proposal_change_success_toast')),
        findsNothing,
      );
      verifyNever(() => nutritionRepository.updateProposalItems(any(), any()));
    });

    testWidgets(
      'keeps voice correction action available for active proposal',
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
          () => audioRecorderService.start(),
        ).thenAnswer((_) async {});
        when(
          () => audioRecorderService.stop(),
        ).thenAnswer(
          (_) async => const RecordedAudio(
            path: '/tmp/test.m4a',
            mimeType: 'audio/m4a',
            sizeBytes: 1024,
          ),
        );
        when(
          () => nutritionRepository.logAudio(
            any(),
            activeProposalId: 'prop_1',
          ),
        ).thenAnswer(
          (_) async => const VoiceMealRunResult(
            transcript: 'make the butter 40 grams',
            provider: 'test',
            model: 'test-model',
            traceId: 'trace-1',
            result: AgentRunResult(
              kind: 'proposal',
              message: 'Meal proposal updated.',
              proposal: updatedProposal,
            ),
          ),
        );

        await tester.pumpWidget(
          ChangeNotifierProvider<VoiceLogViewModel>.value(
            value: viewModel,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: buildTheme(),
              home: const MealCreateScreen(),
            ),
          ),
        );

        await viewModel.submitText('bread and butter');
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('meal_text_field')), findsNothing);
        expect(
          find.byKey(const ValueKey('submit_meal_button')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('meal_create_voice_action_button')),
          findsOneWidget,
        );
        expect(viewModel.proposal, initialProposal);

        await tester.tap(find.byKey(const ValueKey('mic_button')));
        await tester.pump();

        expect(viewModel.state, VoiceLogState.recording);
        expect(viewModel.proposal, initialProposal);
        expect(
            find.byKey(const ValueKey('voice_transcript_card')), findsNothing);

        await tester.tap(find.byKey(const ValueKey('mic_button')));
        await tester.pumpAndSettle();

        expect(viewModel.proposal, updatedProposal);
        expect(
          find.byKey(const ValueKey('proposal_change_success_toast')),
          findsOneWidget,
        );
        expect(find.text('Changes applied'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('voice_transcript_card')),
          findsOneWidget,
        );
        expect(find.text('make the butter 40 grams'), findsOneWidget);
        verify(
          () => nutritionRepository.logAudio(
            any(),
            activeProposalId: 'prop_1',
          ),
        ).called(1);

        await tester.pump(
          VoiceLogViewModel.proposalChangeSuccessDuration +
              const Duration(milliseconds: 100),
        );
        await tester.pump();

        expect(
          find.byKey(const ValueKey('proposal_change_success_toast')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'shows localized change success for Spanish active proposal correction',
      (tester) async {
        const initialProposal = MealProposal(
          id: 'prop_arroz',
          title: 'Arroz con mantequilla',
          confidence: 0.85,
          requiresConfirmation: true,
          trustedAutoCommitEligible: false,
          nutrition: NutritionSnapshot(
            calories: 230,
            proteinGrams: 3,
            carbsGrams: 28,
            fatGrams: 11,
          ),
          items: [],
        );
        const updatedProposal = MealProposal(
          id: 'prop_arroz',
          title: 'Arroz',
          confidence: 0.85,
          requiresConfirmation: true,
          trustedAutoCommitEligible: false,
          nutrition: NutritionSnapshot(
            calories: 130,
            proteinGrams: 2.7,
            carbsGrams: 28,
            fatGrams: 0.3,
          ),
          items: [],
        );
        when(() => nutritionRepository.logText('arroz con mantequilla'))
            .thenAnswer(
          (_) async => const AgentRunResult(
            kind: 'proposal',
            message: 'Propuesta de comida creada.',
            proposal: initialProposal,
          ),
        );
        when(
          () => nutritionRepository.logText(
            'elimina la mantequilla',
            activeProposalId: 'prop_arroz',
          ),
        ).thenAnswer(
          (_) async => const AgentRunResult(
            kind: 'proposal',
            message: 'Propuesta actualizada.',
            proposal: updatedProposal,
          ),
        );

        await tester.pumpWidget(
          ChangeNotifierProvider<VoiceLogViewModel>.value(
            value: viewModel,
            child: MaterialApp(
              locale: const Locale('es'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: buildTheme(),
              home: const MealCreateScreen(),
            ),
          ),
        );

        await viewModel.submitText('arroz con mantequilla');
        await tester.pumpAndSettle();
        await viewModel.submitText('elimina la mantequilla');
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('proposal_change_success_toast')),
          findsOneWidget,
        );
        expect(find.text('Cambios aplicados'), findsOneWidget);

        await tester.pump(
          VoiceLogViewModel.proposalChangeSuccessDuration +
              const Duration(milliseconds: 100),
        );
        await tester.pump();
      },
    );

    testWidgets(
      'shows voice transcript when voice correction needs clarification',
      (tester) async {
        const initialProposal = MealProposal(
          id: 'prop_rice',
          title: 'Rice noodles, cooked',
          confidence: 0.85,
          requiresConfirmation: true,
          trustedAutoCommitEligible: false,
          nutrition: NutritionSnapshot(
            calories: 108,
            proteinGrams: 1.8,
            carbsGrams: 24,
            fatGrams: 0.2,
          ),
          items: [],
        );
        when(() => nutritionRepository.logText('rice')).thenAnswer(
          (_) async => const AgentRunResult(
            kind: 'proposal',
            message: 'Meal proposal created.',
            proposal: initialProposal,
          ),
        );
        when(() => audioRecorderService.start()).thenAnswer((_) async {});
        when(() => audioRecorderService.stop()).thenAnswer(
          (_) async => const RecordedAudio(
            path: '/tmp/test.m4a',
            mimeType: 'audio/m4a',
            sizeBytes: 1024,
          ),
        );
        when(
          () => nutritionRepository.logAudio(
            any(),
            activeProposalId: 'prop_rice',
          ),
        ).thenAnswer(
          (_) async => const VoiceMealRunResult(
            transcript: 'change it to rice with chicken',
            provider: 'test',
            model: 'test-model',
            traceId: 'trace-1',
            result: AgentRunResult(
              kind: 'clarification_required',
              message:
                  'I am not sure what you would like to do. Could you rephrase?',
            ),
          ),
        );

        await tester.pumpWidget(
          ChangeNotifierProvider<VoiceLogViewModel>.value(
            value: viewModel,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: buildTheme(),
              home: const MealCreateScreen(),
            ),
          ),
        );

        await viewModel.submitText('rice');
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('mic_button')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('mic_button')));
        await tester.pumpAndSettle();

        expect(viewModel.proposal, initialProposal);
        expect(find.text('Rice noodles, cooked'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('voice_transcript_card')),
          findsOneWidget,
        );
        expect(find.text('change it to rice with chicken'), findsOneWidget);
        expect(find.text('Needs a little more detail'), findsOneWidget);
        expect(find.byKey(const ValueKey('mic_button')), findsOneWidget);
        expect(find.byKey(const ValueKey('meal_text_field')), findsNothing);
        expect(
          find.byKey(const ValueKey('submit_meal_button')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'shows food match clarification while keeping active proposal visible',
      (tester) async {
        const initialProposal = MealProposal(
          id: 'prop_chicken_rice',
          title: 'Chicken and rice',
          confidence: 0.85,
          requiresConfirmation: true,
          trustedAutoCommitEligible: false,
          nutrition: NutritionSnapshot(
            calories: 295,
            proteinGrams: 38,
            carbsGrams: 29,
            fatGrams: 4,
          ),
          items: [],
        );
        final group = _candidateGroup(
          canonicalEnglishName: 'red meat',
          candidates: const [],
        );
        when(() => nutritionRepository.logText('chicken and rice')).thenAnswer(
          (_) async => const AgentRunResult(
            kind: 'proposal',
            message: 'Meal proposal created.',
            proposal: initialProposal,
          ),
        );
        when(() => audioRecorderService.start()).thenAnswer((_) async {});
        when(() => audioRecorderService.stop()).thenAnswer(
          (_) async => const RecordedAudio(
            path: '/tmp/test.m4a',
            mimeType: 'audio/m4a',
            sizeBytes: 1024,
          ),
        );
        when(
          () => nutritionRepository.logAudio(
            any(),
            activeProposalId: 'prop_chicken_rice',
          ),
        ).thenAnswer(
          (_) async => VoiceMealRunResult(
            transcript: 'add 10 grams of red meat and delete the butter',
            provider: 'test',
            model: 'test-model',
            traceId: 'trace-1',
            result: AgentRunResult(
              kind: 'clarification_required',
              message:
                  'I need a food match for red meat before updating the meal proposal.',
              proposal: initialProposal,
              candidateGroups: [group],
            ),
          ),
        );

        await tester.pumpWidget(
          ChangeNotifierProvider<VoiceLogViewModel>.value(
            value: viewModel,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: buildTheme(),
              home: const MealCreateScreen(),
            ),
          ),
        );

        await viewModel.submitText('chicken and rice');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('mic_button')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('mic_button')));
        await tester.pumpAndSettle();

        expect(find.text('Chicken and rice'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('resolver_clarification_card')),
          findsOneWidget,
        );
        expect(find.text('red meat -> red meat'), findsOneWidget);
        expect(
          find.text(
            'No database match for this ingredient. Please repeat or rephrase it.',
          ),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('mic_button')), findsOneWidget);
        expect(find.byKey(const ValueKey('meal_text_field')), findsNothing);
        expect(
          find.byKey(const ValueKey('submit_meal_button')),
          findsNothing,
        );
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
