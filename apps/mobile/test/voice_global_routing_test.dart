import 'package:cal_tracker_mobile/data/repositories/nutrition_repository.dart';
import 'package:cal_tracker_mobile/data/services/audio_recorder_service.dart';
import 'package:cal_tracker_mobile/domain/models/nutrition_models.dart';
import 'package:cal_tracker_mobile/generated/api/cal_tracker_api.dart';
import 'package:cal_tracker_mobile/ui/core/app_shell.dart';
import 'package:cal_tracker_mobile/ui/features/voice_log/view_models/voice_log_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockCalTrackerApiClient extends Mock implements CalTrackerApiClient {}

class MockNutritionRepository extends Mock implements NutritionRepository {}

class MockAudioRecorderService extends Mock implements AudioRecorderService {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const UsualFoodInput(
        name: 'Fallback',
        servingGrams: 100,
        nutrition: _nutrition,
      ),
    );
    registerFallbackValue(<MealItem>[]);
    registerFallbackValue(<String>[]);
  });

  group('global voice routing', () {
    test('normal meal proposal routes to meal create', () {
      const result = AgentRunResult(
        kind: 'proposal',
        message: 'Meal proposal created.',
        proposal: _proposal,
      );

      final destination = globalVoiceRoutingDestinationFor(result);

      expect(destination?.location, '/meal/create');
      expect(destination?.extra, isNull);
    });

    test('usual food draft routes to ingredient editor with draft extra', () {
      const draft = UsualFoodDraft(
        name: 'Arroz Hacendado',
        servingGrams: 100,
        calories: 360,
        proteinGrams: 7,
        carbsGrams: 79,
        fatGrams: 1,
      );
      const result = AgentRunResult(
        kind: 'usual_food_draft',
        message: 'Review the draft before saving.',
        usualFoodDraft: draft,
      );

      final destination = globalVoiceRoutingDestinationFor(result);

      expect(destination?.location, '/templates/ingredients/new');
      expect(destination?.extra, same(draft));
    });

    test(
      'usual meal draft routes to meal template editor with draft extra',
      () {
        const draft = UsualMealDraft(title: 'Lunch template', items: [_item]);
        const result = AgentRunResult(
          kind: 'usual_meal_draft',
          message: 'Review the template before saving.',
          usualMealDraft: draft,
        );

        final destination = globalVoiceRoutingDestinationFor(result);

        expect(destination?.location, '/templates/meals/new');
        expect(destination?.extra, same(draft));
      },
    );
  });

  group('AgentRunResult parsing', () {
    late MockCalTrackerApiClient apiClient;
    late NutritionRepository repository;

    setUp(() {
      apiClient = MockCalTrackerApiClient();
      repository = NutritionRepository(apiClient: apiClient);
    });

    test('parses usual food draft result from runAgent', () async {
      when(() => apiClient.runAgent('create usual rice')).thenAnswer(
        (_) async => {
          'kind': 'usual_food_draft',
          'message': 'Review the draft before saving.',
          'draft': {
            'name': 'Arroz Hacendado',
            'brand': 'Hacendado',
            'servingGrams': 100,
            'nutrition': {
              'calories': 360,
              'proteinGrams': 7,
              'carbsGrams': 79,
              'fatGrams': 1,
            },
            'missingRequiredFields': <Object?>[],
          },
        },
      );

      final result = await repository.logText('create usual rice');

      expect(result.kind, 'usual_food_draft');
      expect(result.usualFoodDraft?.name, 'Arroz Hacendado');
      expect(result.usualFoodDraft?.brand, 'Hacendado');
      expect(result.usualFoodDraft?.calories, 360);
    });

    test('parses usual meal draft result from runAgent', () async {
      when(() => apiClient.runAgent('save my lunch')).thenAnswer(
        (_) async => {
          'kind': 'usual_meal_draft',
          'message': 'Review the template before saving.',
          'usualMealDraft': {
            'title': 'Lunch template',
            'items': [_item.toJson()],
            'aliases': ['work lunch'],
            'nutrition': _nutrition.toJson(),
            'missingRequiredFields': <Object?>[],
          },
        },
      );

      final result = await repository.logText('save my lunch');

      expect(result.kind, 'usual_meal_draft');
      expect(result.usualMealDraft?.title, 'Lunch template');
      expect(result.usualMealDraft?.items.single.name, 'Rice');
      expect(result.usualMealDraft?.aliases, ['work lunch']);
    });
  });

  group('VoiceLogViewModel draft state', () {
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

    test('keeps usual food draft in testable state without saving', () async {
      const draft = UsualFoodDraft(name: 'Arroz Hacendado');
      when(() => nutritionRepository.logText('save rice')).thenAnswer(
        (_) async => const AgentRunResult(
          kind: 'usual_food_draft',
          message: 'Review the draft before saving.',
          usualFoodDraft: draft,
        ),
      );

      await viewModel.submitText('save rice');

      expect(viewModel.state, VoiceLogState.resultReady);
      expect(viewModel.usualFoodDraft, same(draft));
      verifyNever(() => nutritionRepository.createUsualFood(any()));
    });

    test('keeps usual meal draft in testable state without saving', () async {
      const draft = UsualMealDraft(title: 'Lunch template', items: [_item]);
      when(() => nutritionRepository.logText('save lunch')).thenAnswer(
        (_) async => const AgentRunResult(
          kind: 'usual_meal_draft',
          message: 'Review the template before saving.',
          usualMealDraft: draft,
        ),
      );

      await viewModel.submitText('save lunch');

      expect(viewModel.state, VoiceLogState.resultReady);
      expect(viewModel.usualMealDraft, same(draft));
      verifyNever(
        () => nutritionRepository.createTemplate(
          title: any(named: 'title'),
          items: any(named: 'items'),
          aliases: any(named: 'aliases'),
        ),
      );
    });
  });
}

const _nutrition = NutritionSnapshot(
  calories: 180,
  proteinGrams: 4,
  carbsGrams: 40,
  fatGrams: 1,
);

const _item = MealItem(
  name: 'Rice',
  quantity: 150,
  unit: 'g',
  calories: 180,
  proteinGrams: 4,
  carbsGrams: 40,
  fatGrams: 1,
  source: 'user_custom',
);

const _proposal = MealProposal(
  id: 'proposal-1',
  title: 'Rice',
  confidence: 0.9,
  requiresConfirmation: true,
  trustedAutoCommitEligible: false,
  nutrition: _nutrition,
  items: [_item],
);
