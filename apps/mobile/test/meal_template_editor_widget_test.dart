import 'package:cal_tracker_mobile/app/theme.dart';
import 'package:cal_tracker_mobile/data/repositories/nutrition_repository.dart';
import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:cal_tracker_mobile/data/services/secure_token_storage.dart';
import 'package:cal_tracker_mobile/domain/models/nutrition_models.dart';
import 'package:cal_tracker_mobile/generated/api/cal_tracker_api.dart';
import 'package:cal_tracker_mobile/l10n/generated/app_localizations.dart';
import 'package:cal_tracker_mobile/ui/features/meal_templates/view_models/meal_templates_view_model.dart';
import 'package:cal_tracker_mobile/ui/features/meal_templates/views/meal_template_editor_screen.dart';
import 'package:cal_tracker_mobile/ui/features/meal_templates/views/meal_templates_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('meals add button opens the dedicated meal editor', (
    tester,
  ) async {
    final repository = _FakeNutritionRepository();
    await tester.pumpWidget(_RouterTestApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add usual meal'));
    await tester.pumpAndSettle();

    expect(find.text('Create usual meal'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('meal_template_title_field')),
      findsOneWidget,
    );
  });

  testWidgets('creates a usual meal template with a public food item', (
    tester,
  ) async {
    final repository = _FakeNutritionRepository(searchItems: [_publicRice]);
    await _pumpEditor(tester, repository);

    await tester.enterText(
      find.byKey(const ValueKey('meal_template_title_field')),
      'Lunch bowl',
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('meal_template_add_from_search_button')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('meal_template_food_search_field')),
      'rice',
    );
    await tester.tap(
      find.byKey(const ValueKey('meal_template_food_search_submit')),
    );
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('meal_template_food_search_result_0')),
    );
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('meal_template_save_button')),
    );
    await tester.pumpAndSettle();

    expect(repository.createdTemplates, hasLength(1));
    final created = repository.createdTemplates.single;
    expect(created.title, 'Lunch bowl');
    expect(created.items.single.name, 'Public rice');
    expect(created.items.single.externalSource, 'usda');
    expect(created.trustedAutoCommitEnabled, isFalse);
  });

  testWidgets('applies a usual meal draft, allows edits, and saves', (
    tester,
  ) async {
    final repository = _FakeNutritionRepository();
    await _pumpEditor(
      tester,
      repository,
      initialDraft: const UsualMealDraft(
        title: 'Voice breakfast',
        aliases: ['my breakfast'],
        items: [_usualOats],
      ),
    );

    expect(
      find.text('Draft applied. Review and edit before saving.'),
      findsNothing,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('meal_template_title_field')),
          )
          .controller
          ?.text,
      'Voice breakfast',
    );

    await tester.enterText(
      find.byKey(const ValueKey('meal_template_item_quantity_0')),
      '80',
    );
    await tester.enterText(
      find.byKey(const ValueKey('meal_template_item_calories_0')),
      '300',
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('meal_template_save_button')),
    );
    await tester.pumpAndSettle();

    final created = repository.createdTemplates.single;
    expect(created.aliases, ['my breakfast']);
    expect(created.items.single.quantity, 80);
    expect(created.items.single.calories, 300);
  });

  testWidgets('edits an existing usual meal using current items', (
    tester,
  ) async {
    final existing = _template(
      id: 'template-1',
      title: 'Original meal',
      items: [_publicRice],
      aliases: const ['old alias'],
    );
    final repository = _FakeNutritionRepository(templates: [existing]);
    await _pumpEditor(tester, repository, templateId: 'template-1');

    await tester.enterText(
      find.byKey(const ValueKey('meal_template_title_field')),
      'Updated meal',
    );
    await tester.enterText(
      find.byKey(const ValueKey('meal_template_aliases_field')),
      'updated alias',
    );
    await tester.enterText(
      find.byKey(const ValueKey('meal_template_item_name_0')),
      'Updated rice',
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('meal_template_save_button')),
    );
    await tester.pumpAndSettle();

    expect(repository.updatedTemplates, hasLength(1));
    final updated = repository.updatedTemplates.single;
    expect(updated.id, 'template-1');
    expect(updated.title, 'Updated meal');
    expect(updated.aliases, ['updated alias']);
    expect(updated.items.single.name, 'Updated rice');
    expect(updated.trustedAutoCommitEnabled, isFalse);
  });
}

Future<void> _pumpEditor(
  WidgetTester tester,
  _FakeNutritionRepository repository, {
  String? templateId,
  UsualMealDraft? initialDraft,
  ThemeMode themeMode = ThemeMode.light,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => MealTemplatesViewModel(nutritionRepository: repository),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: themeMode,
        home: Scaffold(
          body: MealTemplateEditorScreen(
            templateId: templateId,
            initialDraft: initialDraft,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder.hitTestable());
}

class _RouterTestApp extends StatelessWidget {
  const _RouterTestApp({required this.repository});

  final _FakeNutritionRepository repository;

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      initialLocation: '/templates',
      routes: [
        GoRoute(
          path: '/templates',
          builder: (context, state) =>
              const Scaffold(body: MealTemplatesScreen()),
        ),
        GoRoute(
          path: '/templates/meals/new',
          builder: (context, state) =>
              const Scaffold(body: MealTemplateEditorScreen()),
        ),
      ],
    );
    return ChangeNotifierProvider(
      create: (_) => MealTemplatesViewModel(nutritionRepository: repository),
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildLightTheme(),
        routerConfig: router,
      ),
    );
  }
}

class _FakeNutritionRepository extends NutritionRepository {
  _FakeNutritionRepository({
    List<MealTemplate> templates = const [],
    List<MealItem> searchItems = const [],
  })  : templates = List.of(templates),
        searchItems = List.of(searchItems),
        super(apiClient: _unusedApiClient());

  List<MealTemplate> templates;
  List<MealItem> searchItems;
  final List<MealTemplate> createdTemplates = [];
  final List<MealTemplate> updatedTemplates = [];

  @override
  Future<List<MealTemplate>> getTemplates() async => templates;

  @override
  Future<List<UsualFood>> getUsualFoods() async => const [];

  @override
  Future<FoodSearchResult> searchFoods(
    String query, {
    int limit = 10,
    String? barcode,
  }) async {
    return FoodSearchResult(items: searchItems.take(limit).toList());
  }

  @override
  Future<MealTemplate> createTemplate({
    required String title,
    required List<MealItem> items,
    required List<String> aliases,
    bool trustedAutoCommitEnabled = false,
  }) async {
    final template = _template(
      id: 'template-${createdTemplates.length + 1}',
      title: title,
      items: items,
      aliases: aliases,
      trustedAutoCommitEnabled: trustedAutoCommitEnabled,
    );
    createdTemplates.add(template);
    templates = [...templates, template];
    return template;
  }

  @override
  Future<MealTemplate> updateTemplate({
    required String templateId,
    required String title,
    required List<MealItem> items,
    required List<String> aliases,
    bool trustedAutoCommitEnabled = false,
  }) async {
    final template = _template(
      id: templateId,
      title: title,
      items: items,
      aliases: aliases,
      trustedAutoCommitEnabled: trustedAutoCommitEnabled,
    );
    updatedTemplates.add(template);
    templates = templates
        .map((item) => item.id == templateId ? template : item)
        .toList(growable: false);
    return template;
  }
}

MealTemplate _template({
  required String id,
  required String title,
  required List<MealItem> items,
  List<String> aliases = const [],
  bool trustedAutoCommitEnabled = false,
}) {
  return MealTemplate(
    id: id,
    title: title,
    trustedAutoCommitEnabled: trustedAutoCommitEnabled,
    nutrition: NutritionSnapshot(
      calories: items.fold(0, (sum, item) => sum + item.calories),
      proteinGrams: items.fold(0.0, (sum, item) => sum + item.proteinGrams),
      carbsGrams: items.fold(0.0, (sum, item) => sum + item.carbsGrams),
      fatGrams: items.fold(0.0, (sum, item) => sum + item.fatGrams),
    ),
    items: items,
    aliases: aliases,
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

const _usualOats = MealItem(
  name: 'My oats',
  quantity: 60,
  unit: 'g',
  calories: 230,
  proteinGrams: 8,
  carbsGrams: 38,
  fatGrams: 4,
  source: 'user_custom',
  externalSource: 'user_custom',
  externalId: 'oats-1',
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
