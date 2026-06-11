import 'package:cal_tracker_mobile/app/theme.dart';
import 'package:cal_tracker_mobile/data/repositories/nutrition_repository.dart';
import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:cal_tracker_mobile/data/services/secure_token_storage.dart';
import 'package:cal_tracker_mobile/domain/models/nutrition_models.dart';
import 'package:cal_tracker_mobile/generated/api/cal_tracker_api.dart';
import 'package:cal_tracker_mobile/l10n/generated/app_localizations.dart';
import 'package:cal_tracker_mobile/ui/core/design_system.dart';
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

    expect(find.text('Usuals'), findsOneWidget);
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

  testWidgets('usuals explanation and add action use dark palette', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      _FakeNutritionRepository(),
      themeMode: ThemeMode.dark,
    );

    var addButton = _addActionButton(tester);

    expect(
      find.text('Usual meals are trusted meals you can log quickly.'),
      findsOneWidget,
    );
    expect(
        find.byKey(const ValueKey('usuals_section_explanation')), findsNothing);
    expect(find.byKey(const ValueKey('usuals_explainer_card')), findsNothing);
    expect(addButton.backgroundColor, FreshPalette.dark.lime);

    await tester.tap(find.text('Ingredients').hitTestable());
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Usual ingredients are foods you enter manually so they appear first in search and meal logging.',
      ),
      findsOneWidget,
    );
    addButton = _addActionButton(tester);

    expect(addButton.backgroundColor, FreshPalette.dark.lime);
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
    expect(
        find.byKey(const ValueKey('usual_food_canonical_field')), findsNothing);
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

  testWidgets('usual meal cards match ingredient card structure in dark mode', (
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
    await _pumpScreen(tester, repository, themeMode: ThemeMode.dark);

    expect(find.text('Usual lunch'), findsOneWidget);
    expect(find.text('lunch shortcut'), findsOneWidget);
    expect(find.byIcon(Icons.restaurant_menu_rounded), findsOneWidget);
    expect(find.byType(FreshFoodStack), findsNothing);
    expect(
      find.byKey(const ValueKey('meal_template_edit_template-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('meal_template_delete_template-1')),
      findsOneWidget,
    );
    expect(find.text('130 Kcal'), findsOneWidget);
    expect(find.text('2.7 g'), findsOneWidget);
    expect(find.text('28 g'), findsOneWidget);
    expect(find.text('0.3 g'), findsOneWidget);
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
    WidgetTester tester, _FakeNutritionRepository repository,
    {ThemeMode themeMode = ThemeMode.light}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => MealTemplatesViewModel(nutritionRepository: repository),
      child: _TestApp(themeMode: themeMode),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openIngredientsTab(WidgetTester tester) async {
  await tester.tap(find.text('Ingredients').hitTestable());
  await tester.pumpAndSettle();
}

FreshIconButton _addActionButton(WidgetTester tester) {
  return tester
      .widgetList<FreshIconButton>(find.byType(FreshIconButton))
      .singleWhere((button) => button.icon == Icons.add_rounded);
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
  const _TestApp({this.themeMode = ThemeMode.light});

  final ThemeMode themeMode;

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
              builder: (context, state) {
                final draft = state.extra is UsualFoodDraft
                    ? state.extra as UsualFoodDraft
                    : null;
                return UsualFoodEditorScreen(initialDraft: draft);
              },
            ),
            GoRoute(
              path: 'ingredients/scan',
              builder: (context, state) =>
                  const Scaffold(body: Text('scan route stub')),
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
      darkTheme: buildDarkTheme(),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}

class _FakeNutritionRepository extends NutritionRepository {
  _FakeNutritionRepository({
    List<MealTemplate> templates = const [],
    List<UsualFood> usualFoods = const [],
  })  : templates = List.of(templates),
        usualFoods = List.of(usualFoods),
        super(apiClient: _unusedApiClient());

  List<MealTemplate> templates;
  List<UsualFood> usualFoods;
  final List<UsualFoodInput> createdInputs = [];
  final List<UsualFoodInput> updatedInputs = [];
  final List<String> deletedIds = [];

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
  Future<bool> deleteTemplate(String templateId) async {
    templates = templates
        .where((item) => item.id != templateId)
        .toList(growable: false);
    return true;
  }
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
