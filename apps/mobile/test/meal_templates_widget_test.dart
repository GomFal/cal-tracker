import 'dart:async';
import 'dart:io';

import 'package:cal_tracker_mobile/app/theme.dart';
import 'package:cal_tracker_mobile/data/repositories/nutrition_repository.dart';
import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:cal_tracker_mobile/data/services/audio_recorder_service.dart';
import 'package:cal_tracker_mobile/data/services/secure_token_storage.dart';
import 'package:cal_tracker_mobile/domain/models/nutrition_models.dart';
import 'package:cal_tracker_mobile/generated/api/cal_tracker_api.dart';
import 'package:cal_tracker_mobile/l10n/generated/app_localizations.dart';
import 'package:cal_tracker_mobile/ui/features/meal_templates/view_models/meal_templates_view_model.dart';
import 'package:cal_tracker_mobile/ui/features/meal_templates/views/meal_templates_screen.dart';
import 'package:cal_tracker_mobile/ui/features/meal_templates/views/usual_food_editor_screen.dart';
import 'package:cal_tracker_mobile/ui/features/voice_log/views/voice_log_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('renders meals and ingredients tabs with empty ingredient state',
      (
    tester,
  ) async {
    await _pumpScreen(tester, _FakeNutritionRepository());

    expect(find.text('Habituals'), findsOneWidget);
    expect(find.text('Meals'), findsOneWidget);
    expect(find.text('Ingredients'), findsOneWidget);

    await tester.tap(find.text('Ingredients').hitTestable());
    await tester.pumpAndSettle();

    expect(find.text('No usual ingredients yet'), findsOneWidget);
    expect(
      find.text(
        'Add foods you use often so they appear first in search and meal logging.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('usual ingredient form validates required fields', (
    tester,
  ) async {
    await _pumpScreen(tester, _FakeNutritionRepository());
    await _openIngredientsTab(tester);

    await tester.tap(find.byTooltip('Add usual ingredient'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('usual_food_save_button')));
    await tester.pumpAndSettle();

    expect(find.text('Enter a value.'), findsWidgets);
    expect(find.text('Enter a number greater than 0.'), findsOneWidget);
    expect(find.text('Enter 0 or a greater number.'), findsWidgets);
  });

  testWidgets('creates a usual ingredient', (tester) async {
    final repository = _FakeNutritionRepository();
    await _pumpScreen(tester, repository);
    await _openIngredientsTab(tester);

    await tester.tap(find.byTooltip('Add usual ingredient'));
    await tester.pumpAndSettle();
    await _fillRequiredIngredientFields(tester, name: 'Test ingredient');
    await tester.enterText(
      find.byKey(const ValueKey('usual_food_brand_field')),
      'Test brand',
    );
    await tester.tap(find.byKey(const ValueKey('usual_food_save_button')));
    await tester.pumpAndSettle();

    expect(repository.createdInputs.single.name, 'Test ingredient');
    expect(find.text('Test ingredient'), findsOneWidget);
    expect(find.textContaining('Test brand'), findsOneWidget);
    expect(find.textContaining('per 100 g'), findsOneWidget);
  });

  testWidgets('navigates from ingredient add action to dedicated editor', (
    tester,
  ) async {
    await _pumpScreen(tester, _FakeNutritionRepository());
    await _openIngredientsTab(tester);

    await tester.tap(find.byTooltip('Add usual ingredient'));
    await tester.pumpAndSettle();

    expect(find.text('New usual ingredient'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    'fills usual ingredient fields from voice draft without auto-saving',
    (tester) async {
      final repository = _FakeNutritionRepository(
        draft: const UsualFoodDraft(
          name: 'AI rice',
          brand: 'Draft brand',
          servingGrams: 100,
          calories: 360,
          proteinGrams: 7,
          carbsGrams: 79,
          fatGrams: 1,
          nutrients: {'saltGrams': 0.01},
        ),
        transcript:
            'My rice per 100 g has 360 kcal, 79 g carbs, 7 g protein and 1 g fat.',
      );
      final recorder = _FakeAudioRecorderService();
      await _pumpEditor(tester, repository, audioRecorderService: recorder);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('usual_food_voice_draft_button')),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Recording'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('usual_food_voice_draft_button')),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(recorder.startCount, 1);
      expect(recorder.stopCount, 1);
      expect(repository.transcribedAudioPaths, hasLength(1));
      expect(repository.draftTexts, [
        'My rice per 100 g has 360 kcal, 79 g carbs, 7 g protein and 1 g fat.',
      ]);
      expect(repository.createdInputs, isEmpty);
      expect(
        find.text('Draft applied. Review the fields before saving.'),
        findsOneWidget,
      );
      expect(find.text('Transcript'), findsOneWidget);
      expect(
        find.text(
          'My rice per 100 g has 360 kcal, 79 g carbs, 7 g protein and 1 g fat.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('usual_food_name_field')),
            )
            .controller
            ?.text,
        'AI rice',
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('usual_food_calories_field')),
            )
            .controller
            ?.text,
        '360',
      );

      await tester.tap(find.byKey(const ValueKey('usual_food_save_button')));
      await tester.pumpAndSettle();

      expect(repository.createdInputs.single.name, 'AI rice');
      expect(repository.createdInputs.single.nutrients['saltGrams'], 0.01);
    },
  );

  testWidgets('blocks usual ingredient form while voice draft is pending', (
    tester,
  ) async {
    final draftCompleter = Completer<UsualFoodDraft>();
    final repository = _FakeNutritionRepository(
      transcript: 'usual rice',
      draftCompleter: draftCompleter,
    );
    final recorder = _FakeAudioRecorderService();
    await _pumpEditor(tester, repository, audioRecorderService: recorder);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('usual_food_voice_draft_button')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('usual_food_voice_draft_button')),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('usual_food_voice_blocking_message')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('usual_food_save_button')),
          )
          .onPressed,
      isNull,
    );

    draftCompleter.complete(
      const UsualFoodDraft(
        name: 'Pending rice',
        servingGrams: 100,
        calories: 130,
        proteinGrams: 2,
        carbsGrams: 28,
        fatGrams: 1,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('usual_food_voice_blocking_message')),
      findsNothing,
    );
    expect(
      find.text('Draft applied. Review the fields before saving.'),
      findsOneWidget,
    );
  });

  testWidgets('tapping a usual meal opens create meal with template items', (
    tester,
  ) async {
    final repository = _FakeNutritionRepository(
      templates: [
        const MealTemplate(
          id: 'template-1',
          title: 'Usual lunch',
          trustedAutoCommitEnabled: false,
          nutrition: NutritionSnapshot(
            calories: 130,
            proteinGrams: 2.7,
            carbsGrams: 28,
            fatGrams: 0.3,
          ),
          items: [_publicRice],
          aliases: ['lunch shortcut'],
        ),
      ],
    );
    await _pumpScreen(tester, repository);

    await tester.tap(find.text('Usual lunch'));
    await tester.pumpAndSettle();

    expect(find.text('Create meal payload'), findsOneWidget);
    expect(find.text('Public rice'), findsOneWidget);
  });

  testWidgets('edits a usual ingredient', (tester) async {
    final repository = _FakeNutritionRepository(
      usualFoods: [_usualFood(id: 'food-1', name: 'Original ingredient')],
    );
    await _pumpScreen(tester, repository);
    await _openIngredientsTab(tester);

    await tester.tap(find.byKey(const ValueKey('usual_food_edit_food-1')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('usual_food_name_field')),
      'Updated ingredient',
    );
    await tester.enterText(
      find.byKey(const ValueKey('usual_food_calories_field')),
      '123',
    );
    await tester.tap(find.byKey(const ValueKey('usual_food_save_button')));
    await tester.pumpAndSettle();

    expect(repository.updatedInputs.single.name, 'Updated ingredient');
    expect(find.text('Updated ingredient'), findsOneWidget);
    expect(find.text('Original ingredient'), findsNothing);
    expect(find.text('123 Kcal'), findsOneWidget);
  });

  testWidgets('deletes a usual ingredient after confirmation', (tester) async {
    final repository = _FakeNutritionRepository(
      usualFoods: [_usualFood(id: 'food-1', name: 'Ingredient to delete')],
    );
    await _pumpScreen(tester, repository);
    await _openIngredientsTab(tester);

    await tester.tap(find.byKey(const ValueKey('usual_food_delete_food-1')));
    await tester.pumpAndSettle();
    expect(
      find.text('Delete Ingredient to delete from your usual ingredients?'),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('usual_food_confirm_delete_button')),
    );
    await tester.pumpAndSettle();

    expect(repository.deletedIds, ['food-1']);
    expect(find.text('Ingredient to delete'), findsNothing);
    expect(find.text('No usual ingredients yet'), findsOneWidget);
  });
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _FakeNutritionRepository repository,
) async {
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => MealTemplatesViewModel(nutritionRepository: repository),
      child: const _TestApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openIngredientsTab(WidgetTester tester) async {
  await tester.tap(find.text('Ingredients').hitTestable());
  await tester.pumpAndSettle();
}

Future<void> _fillRequiredIngredientFields(
  WidgetTester tester, {
  required String name,
}) async {
  await tester.enterText(
    find.byKey(const ValueKey('usual_food_name_field')),
    name,
  );
  await tester.enterText(
    find.byKey(const ValueKey('usual_food_serving_grams_field')),
    '100',
  );
  await tester.enterText(
    find.byKey(const ValueKey('usual_food_calories_field')),
    '250',
  );
  await tester.enterText(
    find.byKey(const ValueKey('usual_food_protein_field')),
    '10',
  );
  await tester.enterText(
    find.byKey(const ValueKey('usual_food_carbs_field')),
    '35',
  );
  await tester.enterText(
    find.byKey(const ValueKey('usual_food_fat_field')),
    '6',
  );
}

class _TestApp extends StatelessWidget {
  const _TestApp();

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      initialLocation: '/templates',
      routes: [
        GoRoute(
          path: '/templates',
          builder: (context, state) =>
              const Scaffold(body: MealTemplatesScreen()),
          routes: [
            GoRoute(
              path: 'ingredients/new',
              builder: (context, state) => const UsualFoodEditorScreen(),
            ),
            GoRoute(
              path: 'ingredients/:id/edit',
              builder: (context, state) =>
                  UsualFoodEditorScreen(foodId: state.pathParameters['id']),
            ),
          ],
        ),
        GoRoute(
          path: '/meal/create',
          builder: (context, state) {
            final extra = state.extra;
            final items = extra is MealCreateInitialItems
                ? extra.items
                : const <MealItem>[];
            return Scaffold(
              body: Column(
                children: [
                  const Text('Create meal payload'),
                  for (final item in items) Text(item.name),
                ],
              ),
            );
          },
        ),
      ],
    );
    return MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildLightTheme(),
      routerConfig: router,
    );
  }
}

Future<void> _pumpEditor(
  WidgetTester tester,
  _FakeNutritionRepository repository, {
  AudioRecorderService? audioRecorderService,
  String? foodId,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => MealTemplatesViewModel(nutritionRepository: repository),
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildLightTheme(),
        routerConfig: GoRouter(
          initialLocation: '/editor',
          routes: [
            GoRoute(
              path: '/editor',
              builder: (context, state) => UsualFoodEditorScreen(
                foodId: foodId,
                audioRecorderService: audioRecorderService,
              ),
            ),
            GoRoute(
              path: '/templates',
              builder: (context, state) => const Scaffold(
                body: MealTemplatesScreen(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _FakeNutritionRepository extends NutritionRepository {
  _FakeNutritionRepository({
    List<MealTemplate> templates = const [],
    List<UsualFood> usualFoods = const [],
    UsualFoodDraft? draft,
    this.draftCompleter,
    this.transcript = '',
  })  : templates = List.of(templates),
        usualFoods = List.of(usualFoods),
        draft = draft ?? const UsualFoodDraft(),
        super(apiClient: _unusedApiClient());

  List<MealTemplate> templates;
  List<UsualFood> usualFoods;
  UsualFoodDraft draft;
  String transcript;
  final List<UsualFoodInput> createdInputs = [];
  final List<UsualFoodInput> updatedInputs = [];
  final List<String> deletedIds = [];
  final List<String> draftTexts = [];
  final List<String> transcribedAudioPaths = [];
  final Completer<UsualFoodDraft>? draftCompleter;

  @override
  Future<List<MealTemplate>> getTemplates() async => templates;

  @override
  Future<List<UsualFood>> getUsualFoods() async => usualFoods;

  @override
  Future<UsualFood> createUsualFood(UsualFoodInput input) async {
    createdInputs.add(input);
    final food = _foodFromInput('food-${usualFoods.length + 1}', input);
    usualFoods = [...usualFoods, food];
    return food;
  }

  @override
  Future<UsualFood> updateUsualFood(String foodId, UsualFoodInput input) async {
    updatedInputs.add(input);
    final food = _foodFromInput(foodId, input);
    usualFoods = usualFoods
        .map((item) => item.id == foodId ? food : item)
        .toList(growable: false);
    return food;
  }

  @override
  Future<bool> deleteUsualFood(String foodId) async {
    deletedIds.add(foodId);
    usualFoods =
        usualFoods.where((item) => item.id != foodId).toList(growable: false);
    return true;
  }

  @override
  Future<UsualFoodDraft> draftUsualFood(String text) async {
    draftTexts.add(text);
    if (draftCompleter != null) return draftCompleter!.future;
    return draft;
  }

  @override
  Future<String> transcribeAudio(File audioFile) async {
    transcribedAudioPaths.add(audioFile.path);
    return transcript;
  }

  @override
  Future<bool> deleteTemplate(String templateId) async {
    templates = templates
        .where((item) => item.id != templateId)
        .toList(growable: false);
    return true;
  }
}

class _FakeAudioRecorderService implements AudioRecorderService {
  int startCount = 0;
  int stopCount = 0;
  String? _currentPath;

  @override
  String? get currentPath => _currentPath;

  @override
  Stream<RecorderState> get stateStream => const Stream.empty();

  @override
  Future<void> start() async {
    startCount += 1;
  }

  @override
  Future<RecordedAudio?> stop() async {
    stopCount += 1;
    final path =
        '${Directory.systemTemp.path}/usual_food_editor_test_${DateTime.now().microsecondsSinceEpoch}.wav';
    _currentPath = path;
    return RecordedAudio(
      path: path,
      mimeType: 'audio/wav',
      sizeBytes: 1024,
    );
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<bool> hasPermission() async => true;
}

UsualFood _foodFromInput(String id, UsualFoodInput input) {
  return UsualFood(
    id: id,
    name: input.name,
    canonicalName: input.canonicalName,
    brand: input.brand,
    barcode: input.barcode,
    servingGrams: input.servingGrams,
    nutrition: input.nutrition,
    aliases: input.aliases,
    nutrients: input.nutrients,
  );
}

UsualFood _usualFood({required String id, required String name}) {
  return UsualFood(
    id: id,
    name: name,
    brand: 'Existing brand',
    servingGrams: 100,
    nutrition: const NutritionSnapshot(
      calories: 250,
      proteinGrams: 10,
      carbsGrams: 35,
      fatGrams: 6,
    ),
  );
}

const _publicRice = MealItem(
  name: 'Public rice',
  quantity: 100,
  unit: 'g',
  calories: 130,
  proteinGrams: 2.7,
  carbsGrams: 28,
  fatGrams: 0.3,
  source: 'database',
  externalSource: 'usda',
  externalId: 'rice-1',
);

class _MemoryTokenStorage implements TokenStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<StoredTokens?> read() async => null;

  @override
  Future<void> write(StoredTokens tokens) async {}
}

CalTrackerApiClient _unusedApiClient() {
  return CalTrackerApiClient(
    config: const ApiConfig(baseUrl: 'http://localhost'),
    tokenStorage: _MemoryTokenStorage(),
  );
}
