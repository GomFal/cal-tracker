import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../data/repositories/nutrition_repository.dart';
import '../../domain/models/auth_models.dart';
import '../../domain/models/macro_distribution.dart';
import '../../domain/models/nutrition_models.dart';

typedef LocalAgentScenarioResultBuilder =
    AgentRunResult Function(LocalFixtureStore store);

class LocalAgentScenario {
  const LocalAgentScenario({
    required this.label,
    required this.transcript,
    required this.resultBuilder,
  });

  final String label;
  final String transcript;
  final LocalAgentScenarioResultBuilder resultBuilder;

  AgentRunResult resolve(LocalFixtureStore store) => resultBuilder(store);
}

class LocalFixtureStore extends ChangeNotifier {
  LocalFixtureStore({
    required AuthUser user,
    required Map<String, DailySummary> dailySummaries,
    required List<MealTemplate> templates,
    required List<UsualFood> usualFoods,
    required List<MealItem> foodCatalog,
    required Map<String, MealProposal> proposals,
    required List<FoodCandidateGroup> candidateGroups,
    required Map<String, LocalAgentScenario> agentScenarios,
    required String selectedScenarioKey,
    DateTime Function()? now,
  }) : _user = user,
       _dailySummaries = Map.of(dailySummaries),
       _templates = List.of(templates),
       _usualFoods = List.of(usualFoods),
       _foodCatalog = List.of(foodCatalog),
       _proposals = Map.of(proposals),
       _candidateGroups = List.of(candidateGroups),
       _agentScenarios = Map.of(agentScenarios),
       _selectedScenarioKey = selectedScenarioKey,
       _now = now ?? DateTime.now;

  factory LocalFixtureStore.seeded({DateTime Function()? now}) {
    final clock = now ?? DateTime.now;
    final today = _dateOnly(clock());
    final yesterday = _dateOnly(clock().subtract(const Duration(days: 1)));
    final tomorrow = _dateOnly(clock().add(const Duration(days: 1)));

    final catalog = _seedFoodCatalog();
    final breakfastItems = [catalog[0], catalog[1]];
    final lunchItems = [catalog[2], catalog[3], catalog[4]];
    final dinnerItems = [catalog[5], catalog[6], catalog[7]];
    final snackItems = [catalog[8]];

    final breakfast = _meal(
      id: 'local-meal-breakfast',
      title: 'Greek yogurt bowl',
      date: today,
      hour: 8,
      mealLabel: MealLabel.breakfast,
      items: breakfastItems,
    );
    final lunch = _meal(
      id: 'local-meal-lunch',
      title: 'Chicken rice plate',
      date: today,
      hour: 13,
      mealLabel: MealLabel.lunch,
      items: lunchItems,
    );
    final yesterdayDinner = _meal(
      id: 'local-meal-yesterday-dinner',
      title: 'Salmon quinoa dinner',
      date: yesterday,
      hour: 20,
      mealLabel: MealLabel.dinner,
      items: dinnerItems,
    );
    final tomorrowSnack = _meal(
      id: 'local-meal-tomorrow-snack',
      title: 'Apple snack',
      date: tomorrow,
      hour: 16,
      mealLabel: MealLabel.snack,
      items: snackItems,
    );

    final proposal = _proposal(
      id: 'local-proposal-chicken-bowl',
      title: 'Chicken rice bowl',
      items: lunchItems,
      confidence: 0.91,
    );
    final candidateGroups = [_seedCandidateGroup(catalog)];
    final summaries = {
      today: _summaryFor(
        date: today,
        meals: [breakfast, lunch],
        waterConsumedLiters: 1.6,
      ),
      yesterday: _summaryFor(
        date: yesterday,
        meals: [yesterdayDinner],
        waterConsumedLiters: 2.1,
      ),
      tomorrow: _summaryFor(
        date: tomorrow,
        meals: [tomorrowSnack],
        waterConsumedLiters: 0,
      ),
    };

    final scenarios = _seedAgentScenarios(
      proposal: proposal,
      candidateGroups: candidateGroups,
    );

    return LocalFixtureStore(
      user: const AuthUser(
        id: 'local-user',
        email: 'local@bettercalories.test',
        displayName: 'Local User',
        trustedModeEnabled: true,
      ),
      dailySummaries: summaries,
      templates: _seedTemplates(catalog),
      usualFoods: const [],
      foodCatalog: catalog,
      proposals: {proposal.id: proposal},
      candidateGroups: candidateGroups,
      agentScenarios: scenarios,
      selectedScenarioKey: 'proposal',
      now: clock,
    );
  }

  final DateTime Function() _now;
  AuthUser _user;
  final Map<String, DailySummary> _dailySummaries;
  List<MealTemplate> _templates;
  List<UsualFood> _usualFoods;
  List<MealItem> _foodCatalog;
  final Map<String, MealProposal> _proposals;
  List<FoodCandidateGroup> _candidateGroups;
  final Map<String, LocalAgentScenario> _agentScenarios;
  String _selectedScenarioKey;
  bool _sessionActive = true;
  bool audioPermissionGranted = true;

  AuthUser get user => _user;
  bool get sessionActive => _sessionActive;
  String get today => _dateOnly(_now());
  String get selectedScenarioKey => _selectedScenarioKey;
  List<MealTemplate> get templates => List.unmodifiable(_templates);
  List<UsualFood> get usualFoods => List.unmodifiable(_usualFoods);
  List<MealItem> get foodCatalog => List.unmodifiable(_foodCatalog);
  List<FoodCandidateGroup> get candidateGroups =>
      List.unmodifiable(_candidateGroups);
  Map<String, LocalAgentScenario> get agentScenarios =>
      Map.unmodifiable(_agentScenarios);
  List<MealProposal> get proposals => List.unmodifiable(_proposals.values);

  void reset() {
    final fresh = LocalFixtureStore.seeded(now: _now);
    _user = fresh._user;
    _dailySummaries
      ..clear()
      ..addAll(fresh._dailySummaries);
    _templates = List.of(fresh._templates);
    _usualFoods = List.of(fresh._usualFoods);
    _foodCatalog = List.of(fresh._foodCatalog);
    _proposals
      ..clear()
      ..addAll(fresh._proposals);
    _candidateGroups = List.of(fresh._candidateGroups);
    _agentScenarios
      ..clear()
      ..addAll(fresh._agentScenarios);
    _selectedScenarioKey = fresh._selectedScenarioKey;
    _sessionActive = fresh._sessionActive;
    audioPermissionGranted = fresh.audioPermissionGranted;
    notifyListeners();
  }

  void setSessionActive(bool active) {
    if (_sessionActive == active) return;
    _sessionActive = active;
    notifyListeners();
  }

  void setUser(AuthUser user) {
    _user = user;
    _sessionActive = true;
    notifyListeners();
  }

  void setTrustedMode(bool enabled) {
    _user = AuthUser(
      id: _user.id,
      email: _user.email,
      displayName: _user.displayName,
      trustedModeEnabled: enabled,
    );
    notifyListeners();
  }

  void selectScenario(String key) {
    if (!_agentScenarios.containsKey(key)) {
      throw ArgumentError.value(key, 'key', 'Unknown local agent scenario');
    }
    if (_selectedScenarioKey == key) return;
    _selectedScenarioKey = key;
    notifyListeners();
  }

  void applyEmptyDayPreset() {
    final current = getDailySummary();
    _dailySummaries[today] = _summaryFor(
      date: today,
      meals: const [],
      target: current.target,
      hydrationGoalLiters: current.hydrationGoalLiters,
      waterConsumedLiters: 0,
      calorieTargetSource: current.calorieTargetSource,
      macroMode: current.macroMode,
      macroSource: current.macroSource,
      macroPreset: current.macroPreset,
      proteinPct: current.proteinPct,
      carbsPct: current.carbsPct,
      fatPct: current.fatPct,
      macroCalories: current.macroCalories,
      calorieDeltaKcal: current.calorieDeltaKcal,
    );
    _sessionActive = true;
    notifyListeners();
  }

  void applyNormalDayPreset() {
    reset();
  }

  void applyOverTargetPreset() {
    final catalog = _foodCatalog;
    final meals = [
      _meal(
        id: 'local-over-breakfast',
        title: 'Large breakfast',
        date: today,
        hour: 8,
        mealLabel: MealLabel.breakfast,
        items: [catalog[0], catalog[1], catalog[9]],
      ),
      _meal(
        id: 'local-over-lunch',
        title: 'Double chicken bowl',
        date: today,
        hour: 13,
        mealLabel: MealLabel.lunch,
        items: [catalog[2], catalog[2], catalog[3], catalog[4]],
      ),
      _meal(
        id: 'local-over-dinner',
        title: 'Salmon quinoa dinner',
        date: today,
        hour: 20,
        mealLabel: MealLabel.dinner,
        items: [catalog[5], catalog[6], catalog[7], catalog[8]],
      ),
    ];
    _dailySummaries[today] = _summaryFor(
      date: today,
      meals: meals,
      target: const NutritionSnapshot(
        calories: 1500,
        proteinGrams: 110,
        carbsGrams: 150,
        fatGrams: 50,
      ),
      waterConsumedLiters: 2.7,
    );
    _sessionActive = true;
    notifyListeners();
  }

  void applyGoalsNotConfiguredPreset() {
    final current = getDailySummary();
    _dailySummaries[today] = _summaryFor(
      date: today,
      meals: current.meals,
      target: const NutritionSnapshot(
        calories: 0,
        proteinGrams: 0,
        carbsGrams: 0,
        fatGrams: 0,
      ),
      hydrationGoalLiters: 0,
      waterConsumedLiters: 0,
      calorieTargetConfigured: false,
      calorieTargetSource: 'unset',
      macroMode: null,
      macroSource: null,
      macroPreset: null,
      proteinPct: null,
      carbsPct: null,
      fatPct: null,
      macroCalories: null,
      calorieDeltaKcal: null,
    );
    _sessionActive = true;
    notifyListeners();
  }

  void applyTemplateHeavyPreset() {
    final catalog = _foodCatalog;
    _templates = [
      ..._seedTemplates(catalog),
      MealTemplate(
        id: 'local-template-oats',
        title: 'Oatmeal snack',
        trustedAutoCommitEnabled: true,
        nutrition: _nutritionFor([catalog[9], catalog[1]]),
        items: [catalog[9], catalog[1]],
        aliases: const ['oats', 'oat bowl'],
      ),
      MealTemplate(
        id: 'local-template-salmon',
        title: 'Salmon dinner',
        trustedAutoCommitEnabled: false,
        nutrition: _nutritionFor([catalog[5], catalog[6], catalog[7]]),
        items: [catalog[5], catalog[6], catalog[7]],
        aliases: const ['salmon dinner', 'fish dinner'],
      ),
      MealTemplate(
        id: 'local-template-apple',
        title: 'Apple snack',
        trustedAutoCommitEnabled: true,
        nutrition: _nutritionFor([catalog[8]]),
        items: [catalog[8]],
        aliases: const ['apple', 'fruit snack'],
      ),
    ];
    _usualFoods = [
      for (var index = 0; index < math.min(catalog.length, 10); index++)
        _usualFoodFromCatalog(index, catalog[index]),
    ];
    _sessionActive = true;
    notifyListeners();
  }

  UsualFood _usualFoodFromCatalog(int index, MealItem item) {
    return UsualFood(
      id: 'local-usual-food-fixture-${index + 1}',
      name: item.name,
      canonicalName: item.canonicalName,
      servingGrams: item.resolvedGrams ?? item.quantity,
      nutrition: NutritionSnapshot(
        calories: item.calories,
        proteinGrams: item.proteinGrams,
        carbsGrams: item.carbsGrams,
        fatGrams: item.fatGrams,
      ),
      aliases: item.originalText == null || item.originalText == item.name
          ? const []
          : [item.originalText!],
      nutrients: {
        'servingDescription':
            '${_formatFixtureQuantity(item.quantity)} '
            '${item.unit}',
      },
      createdAt: _now(),
      updatedAt: _now(),
    );
  }

  void addSampleMeal() {
    final summary = getDailySummary();
    final meal = _meal(
      id: 'local-sample-meal-${DateTime.now().microsecondsSinceEpoch}',
      title: 'Sample local meal',
      date: today,
      hour: _now().hour,
      mealLabel: MealLabel.snack,
      items: [_foodCatalog[8], _foodCatalog[9]],
    );
    _dailySummaries[today] = _summaryFor(
      date: today,
      meals: [...summary.meals, meal],
      target: summary.target,
      hydrationGoalLiters: summary.hydrationGoalLiters,
      waterConsumedLiters: summary.waterConsumedLiters,
      calorieTargetConfigured: summary.calorieTargetConfigured,
      calorieTargetSource: summary.calorieTargetSource,
      macroMode: summary.macroMode,
      macroSource: summary.macroSource,
      macroPreset: summary.macroPreset,
      proteinPct: summary.proteinPct,
      carbsPct: summary.carbsPct,
      fatPct: summary.fatPct,
      macroCalories: summary.macroCalories,
      calorieDeltaKcal: summary.calorieDeltaKcal,
    );
    _sessionActive = true;
    notifyListeners();
  }

  void clearTodayMeals() {
    final summary = getDailySummary();
    _dailySummaries[today] = _summaryFor(
      date: today,
      meals: const [],
      target: summary.target,
      hydrationGoalLiters: summary.hydrationGoalLiters,
      waterConsumedLiters: summary.waterConsumedLiters,
      calorieTargetConfigured: summary.calorieTargetConfigured,
      calorieTargetSource: summary.calorieTargetSource,
      macroMode: summary.macroMode,
      macroSource: summary.macroSource,
      macroPreset: summary.macroPreset,
      proteinPct: summary.proteinPct,
      carbsPct: summary.carbsPct,
      fatPct: summary.fatPct,
      macroCalories: summary.macroCalories,
      calorieDeltaKcal: summary.calorieDeltaKcal,
    );
    _sessionActive = true;
    notifyListeners();
  }

  LocalAgentScenario scenarioForInput(String input) {
    return _agentScenarios[input] ??
        _agentScenarios[_selectedScenarioKey] ??
        _agentScenarios.values.first;
  }

  DailySummary getDailySummary({String? date}) {
    final key = date ?? today;
    return _dailySummaries[key] ?? _emptySummary(key);
  }

  List<Meal> getMealHistory() {
    final meals = _dailySummaries.values.expand((summary) => summary.meals);
    final sorted = meals.toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return sorted;
  }

  DailyGoals updateDailyGoals({
    String? date,
    int? calories,
    double? hydrationGoalLiters,
    String? calorieTargetSource,
    MacroDistributionConfig? macroConfig,
    int? macroCalorieTarget,
  }) {
    final key = date ?? today;
    final current = getDailySummary(date: key);
    final targetCalories = calories ?? current.target.calories;
    final target = _targetFromConfig(
      calories: targetCalories,
      fallback: current.target,
      macroConfig: macroConfig,
    );
    final macroFields = _macroFields(
      macroConfig: macroConfig,
      calories: macroCalorieTarget ?? targetCalories,
      fallback: current,
    );
    _dailySummaries[key] = _summaryFor(
      date: key,
      meals: current.meals,
      target: target,
      hydrationGoalLiters: hydrationGoalLiters ?? current.hydrationGoalLiters,
      waterConsumedLiters: current.waterConsumedLiters,
      calorieTargetSource: calorieTargetSource ?? current.calorieTargetSource,
      macroMode: macroFields.mode,
      macroSource: macroFields.source,
      macroPreset: macroFields.preset,
      proteinPct: macroFields.proteinPct,
      carbsPct: macroFields.carbsPct,
      fatPct: macroFields.fatPct,
      macroCalories: macroFields.macroCalories,
      calorieDeltaKcal: macroFields.calorieDeltaKcal,
    );
    notifyListeners();
    return DailyGoals(
      date: key,
      target: target,
      hydrationGoalLiters: hydrationGoalLiters ?? current.hydrationGoalLiters,
      calorieTargetConfigured: true,
      calorieTargetSource: calorieTargetSource ?? current.calorieTargetSource,
      macroMode: macroFields.mode,
      macroSource: macroFields.source,
      macroPreset: macroFields.preset,
      proteinPct: macroFields.proteinPct,
      carbsPct: macroFields.carbsPct,
      fatPct: macroFields.fatPct,
      macroCalories: macroFields.macroCalories,
      calorieDeltaKcal: macroFields.calorieDeltaKcal,
    );
  }

  DailySummary updateHydration({
    String? date,
    required double waterConsumedLiters,
  }) {
    final key = date ?? today;
    final current = getDailySummary(date: key);
    final updated = _copySummary(
      current,
      waterConsumedLiters: waterConsumedLiters,
    );
    _dailySummaries[key] = updated;
    notifyListeners();
    return updated;
  }

  Meal correctMealItems(String mealId, List<MealItem> items) {
    for (final entry in _dailySummaries.entries) {
      final index = entry.value.meals.indexWhere((meal) => meal.id == mealId);
      if (index == -1) continue;
      final current = entry.value.meals[index];
      final updated = Meal(
        id: current.id,
        title: current.title,
        occurredAt: current.occurredAt,
        mealLabel: current.mealLabel,
        nutrition: _nutritionFor(items),
        items: List.of(items),
      );
      final meals = List<Meal>.of(entry.value.meals)..[index] = updated;
      _dailySummaries[entry.key] = _summaryFor(
        date: entry.value.date,
        meals: meals,
        target: entry.value.target,
        hydrationGoalLiters: entry.value.hydrationGoalLiters,
        waterConsumedLiters: entry.value.waterConsumedLiters,
        calorieTargetSource: entry.value.calorieTargetSource,
        macroMode: entry.value.macroMode,
        macroSource: entry.value.macroSource,
        macroPreset: entry.value.macroPreset,
        proteinPct: entry.value.proteinPct,
        carbsPct: entry.value.carbsPct,
        fatPct: entry.value.fatPct,
        macroCalories: entry.value.macroCalories,
        calorieDeltaKcal: entry.value.calorieDeltaKcal,
      );
      notifyListeners();
      return updated;
    }
    throw StateError('Unknown local meal: $mealId');
  }

  bool deleteMeal(String mealId) {
    for (final entry in _dailySummaries.entries) {
      final meals = entry.value.meals
          .where((meal) => meal.id != mealId)
          .toList(growable: false);
      if (meals.length == entry.value.meals.length) continue;
      _dailySummaries[entry.key] = _summaryFor(
        date: entry.value.date,
        meals: meals,
        target: entry.value.target,
        hydrationGoalLiters: entry.value.hydrationGoalLiters,
        waterConsumedLiters: entry.value.waterConsumedLiters,
        calorieTargetSource: entry.value.calorieTargetSource,
        macroMode: entry.value.macroMode,
        macroSource: entry.value.macroSource,
        macroPreset: entry.value.macroPreset,
        proteinPct: entry.value.proteinPct,
        carbsPct: entry.value.carbsPct,
        fatPct: entry.value.fatPct,
        macroCalories: entry.value.macroCalories,
        calorieDeltaKcal: entry.value.calorieDeltaKcal,
      );
      notifyListeners();
      return true;
    }
    return false;
  }

  Meal commitProposal(String proposalId, {MealLabel? mealLabel}) {
    final proposal = _proposals[proposalId];
    if (proposal == null) {
      throw StateError('Unknown local proposal: $proposalId');
    }
    final date = today;
    final meal = Meal(
      id: 'local-meal-${DateTime.now().microsecondsSinceEpoch}',
      title: proposal.title,
      occurredAt: _now(),
      mealLabel: mealLabel,
      nutrition: proposal.nutrition,
      items: proposal.items,
    );
    final summary = getDailySummary(date: date);
    _dailySummaries[date] = _summaryFor(
      date: date,
      meals: [...summary.meals, meal],
      target: summary.target,
      hydrationGoalLiters: summary.hydrationGoalLiters,
      waterConsumedLiters: summary.waterConsumedLiters,
      calorieTargetSource: summary.calorieTargetSource,
      macroMode: summary.macroMode,
      macroSource: summary.macroSource,
      macroPreset: summary.macroPreset,
      proteinPct: summary.proteinPct,
      carbsPct: summary.carbsPct,
      fatPct: summary.fatPct,
      macroCalories: summary.macroCalories,
      calorieDeltaKcal: summary.calorieDeltaKcal,
    );
    notifyListeners();
    return meal;
  }

  MealProposal updateProposalItems(String proposalId, List<MealItem> items) {
    final current = _proposals[proposalId];
    if (current == null) {
      throw StateError('Unknown local proposal: $proposalId');
    }
    final updated = MealProposal(
      id: current.id,
      title: current.title,
      confidence: current.confidence,
      requiresConfirmation: current.requiresConfirmation,
      trustedAutoCommitEligible: current.trustedAutoCommitEligible,
      nutrition: _nutritionFor(items),
      items: List.of(items),
    );
    _proposals[proposalId] = updated;
    notifyListeners();
    return updated;
  }

  MealProposal createProposalFromItems({
    required String phrase,
    required List<MealItem> items,
    String? title,
  }) {
    final proposal = _proposal(
      id: 'local-proposal-${_proposals.length + 1}',
      title: title ?? (phrase.trim().isEmpty ? 'Manual meal' : phrase.trim()),
      items: items,
      confidence: 1,
    );
    _proposals[proposal.id] = proposal;
    notifyListeners();
    return proposal;
  }

  MealTemplate setTemplateTrustedMode(MealTemplate template, bool enabled) {
    final updated = MealTemplate(
      id: template.id,
      title: template.title,
      trustedAutoCommitEnabled: enabled,
      nutrition: template.nutrition,
      items: template.items,
      aliases: template.aliases,
    );
    _templates = _templates
        .map((item) => item.id == updated.id ? updated : item)
        .toList();
    notifyListeners();
    return updated;
  }

  MealTemplate createTemplate({
    required String title,
    required List<MealItem> items,
    required List<String> aliases,
    bool trustedAutoCommitEnabled = false,
  }) {
    final template = MealTemplate(
      id: 'local-template-${_templates.length + 1}',
      title: title,
      trustedAutoCommitEnabled: trustedAutoCommitEnabled,
      nutrition: _nutritionFor(items),
      items: List.of(items),
      aliases: List.of(aliases),
    );
    _templates = [..._templates, template];
    notifyListeners();
    return template;
  }

  MealTemplate updateTemplate({
    required String templateId,
    required String title,
    required List<MealItem> items,
    required List<String> aliases,
    bool trustedAutoCommitEnabled = false,
  }) {
    _templates.firstWhere(
      (template) => template.id == templateId,
      orElse: () => throw StateError('Unknown local template: $templateId'),
    );
    final updated = MealTemplate(
      id: templateId,
      title: title,
      trustedAutoCommitEnabled: trustedAutoCommitEnabled,
      nutrition: _nutritionFor(items),
      items: List.of(items),
      aliases: List.of(aliases),
    );
    _templates = _templates
        .map((template) => template.id == templateId ? updated : template)
        .toList(growable: false);
    notifyListeners();
    return updated;
  }

  bool deleteTemplate(String templateId) {
    final next = _templates
        .where((template) => template.id != templateId)
        .toList(growable: false);
    if (next.length == _templates.length) return false;
    _templates = next;
    notifyListeners();
    return true;
  }

  UsualMealDraft draftUsualMeal(String text) {
    final phrase = text.trim();
    final words = phrase.isEmpty
        ? const <String>[]
        : phrase.split(RegExp(r'\s+'));
    final title = words.isEmpty
        ? 'Local drafted meal'
        : words.first[0].toUpperCase() + words.first.substring(1);
    final items = _foodCatalog.take(2).toList(growable: false);
    return UsualMealDraft(
      title: title,
      aliases: words.length > 1 ? words.sublist(1) : const [],
      items: items,
    );
  }

  UsualFood createUsualFood(UsualFoodInput input) {
    final food = UsualFood(
      id: 'local-usual-food-${_usualFoods.length + 1}',
      name: input.name,
      canonicalName: input.canonicalName,
      brand: input.brand,
      barcode: input.barcode,
      servingGrams: input.servingGrams,
      nutrition: input.nutrition,
      aliases: List.of(input.aliases),
      nutrients: Map.of(input.nutrients),
      createdAt: _now(),
      updatedAt: _now(),
    );
    _usualFoods = [..._usualFoods, food];
    notifyListeners();
    return food;
  }

  UsualFood updateUsualFood(String foodId, UsualFoodInput input) {
    final updated = UsualFood(
      id: foodId,
      name: input.name,
      canonicalName: input.canonicalName,
      brand: input.brand,
      barcode: input.barcode,
      servingGrams: input.servingGrams,
      nutrition: input.nutrition,
      aliases: List.of(input.aliases),
      nutrients: Map.of(input.nutrients),
      updatedAt: _now(),
    );
    _usualFoods = _usualFoods
        .map((food) => food.id == foodId ? updated : food)
        .toList(growable: false);
    notifyListeners();
    return updated;
  }

  bool deleteUsualFood(String foodId) {
    final next = _usualFoods
        .where((food) => food.id != foodId)
        .toList(growable: false);
    if (next.length == _usualFoods.length) return false;
    _usualFoods = next;
    notifyListeners();
    return true;
  }

  List<MealItem> searchFoods({
    required String query,
    String? barcode,
    int limit = 10,
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    final usualMatches = _usualFoods
        .where((food) {
          if (barcode != null && barcode.isNotEmpty) {
            return food.barcode == barcode;
          }
          if (normalizedQuery.isEmpty) return true;
          return food.name.toLowerCase().contains(normalizedQuery) ||
              (food.canonicalName ?? '').toLowerCase().contains(
                normalizedQuery,
              ) ||
              (food.brand ?? '').toLowerCase().contains(normalizedQuery) ||
              food.aliases.any(
                (alias) => alias.toLowerCase().contains(normalizedQuery),
              );
        })
        .map((food) {
          return MealItem(
            name: food.name,
            quantity: food.servingGrams,
            unit: 'g',
            calories: food.nutrition.calories,
            proteinGrams: food.nutrition.proteinGrams,
            carbsGrams: food.nutrition.carbsGrams,
            fatGrams: food.nutrition.fatGrams,
            source: 'user_custom',
            canonicalName: food.canonicalName,
            externalSource: 'user_custom',
            externalId: food.id,
          );
        });
    final matches = _foodCatalog.where((item) {
      if (barcode != null && barcode.isNotEmpty) {
        return item.externalId == barcode || item.originalText == barcode;
      }
      if (normalizedQuery.isEmpty) return true;
      return item.name.toLowerCase().contains(normalizedQuery) ||
          (item.canonicalName ?? '').toLowerCase().contains(normalizedQuery);
    });
    return [...usualMatches, ...matches].take(limit).toList(growable: false);
  }

  DailySummary _emptySummary(String date) {
    return _summaryFor(date: date, meals: const []);
  }
}

class _MacroFields {
  const _MacroFields({
    this.mode,
    this.source,
    this.preset,
    this.proteinPct,
    this.carbsPct,
    this.fatPct,
    this.macroCalories,
    this.calorieDeltaKcal,
  });

  final MacroMode? mode;
  final MacroSource? source;
  final MacroPreset? preset;
  final int? proteinPct;
  final int? carbsPct;
  final int? fatPct;
  final int? macroCalories;
  final int? calorieDeltaKcal;
}

List<MealItem> _seedFoodCatalog() {
  return const [
    MealItem(
      name: 'Greek yogurt',
      canonicalName: 'Greek yogurt, plain',
      quantity: 200,
      unit: 'g',
      calories: 146,
      proteinGrams: 20,
      carbsGrams: 7.2,
      fatGrams: 4,
      source: 'local_fixture',
      externalSource: 'local',
      externalId: 'food-greek-yogurt',
      confidence: 0.98,
      resolvedGrams: 200,
    ),
    MealItem(
      name: 'Blueberries',
      canonicalName: 'Blueberries, raw',
      quantity: 80,
      unit: 'g',
      calories: 46,
      proteinGrams: 0.6,
      carbsGrams: 11.6,
      fatGrams: 0.2,
      source: 'local_fixture',
      externalSource: 'local',
      externalId: 'food-blueberries',
      confidence: 0.97,
      resolvedGrams: 80,
    ),
    MealItem(
      name: 'Chicken breast',
      canonicalName: 'Chicken breast, cooked',
      quantity: 150,
      unit: 'g',
      calories: 248,
      proteinGrams: 46.5,
      carbsGrams: 0,
      fatGrams: 5.4,
      source: 'local_fixture',
      externalSource: 'local',
      externalId: 'food-chicken-breast',
      confidence: 0.96,
      resolvedGrams: 150,
    ),
    MealItem(
      name: 'Cooked rice',
      canonicalName: 'White rice, cooked',
      quantity: 160,
      unit: 'g',
      calories: 208,
      proteinGrams: 4.3,
      carbsGrams: 44.8,
      fatGrams: 0.5,
      source: 'local_fixture',
      externalSource: 'local',
      externalId: 'food-cooked-rice',
      confidence: 0.95,
      resolvedGrams: 160,
    ),
    MealItem(
      name: 'Avocado',
      canonicalName: 'Avocado, raw',
      quantity: 70,
      unit: 'g',
      calories: 112,
      proteinGrams: 1.4,
      carbsGrams: 6,
      fatGrams: 10.3,
      source: 'local_fixture',
      externalSource: 'local',
      externalId: 'food-avocado',
      confidence: 0.94,
      resolvedGrams: 70,
    ),
    MealItem(
      name: 'Salmon',
      canonicalName: 'Atlantic salmon, cooked',
      quantity: 170,
      unit: 'g',
      calories: 350,
      proteinGrams: 37.4,
      carbsGrams: 0,
      fatGrams: 21,
      source: 'local_fixture',
      externalSource: 'local',
      externalId: 'food-salmon',
      confidence: 0.95,
      resolvedGrams: 170,
    ),
    MealItem(
      name: 'Quinoa',
      canonicalName: 'Quinoa, cooked',
      quantity: 150,
      unit: 'g',
      calories: 180,
      proteinGrams: 6.6,
      carbsGrams: 32,
      fatGrams: 2.9,
      source: 'local_fixture',
      externalSource: 'local',
      externalId: 'food-quinoa',
      confidence: 0.93,
      resolvedGrams: 150,
    ),
    MealItem(
      name: 'Green salad',
      canonicalName: 'Mixed greens',
      quantity: 120,
      unit: 'g',
      calories: 36,
      proteinGrams: 2,
      carbsGrams: 6,
      fatGrams: 0.4,
      source: 'local_fixture',
      externalSource: 'local',
      externalId: 'food-green-salad',
      confidence: 0.9,
      resolvedGrams: 120,
    ),
    MealItem(
      name: 'Apple',
      canonicalName: 'Apple, raw',
      quantity: 1,
      unit: 'medium',
      calories: 95,
      proteinGrams: 0.5,
      carbsGrams: 25,
      fatGrams: 0.3,
      source: 'local_fixture',
      externalSource: 'local',
      externalId: 'food-apple',
      confidence: 0.95,
    ),
    MealItem(
      name: 'Oatmeal',
      canonicalName: 'Oats, cooked',
      quantity: 1,
      unit: 'bowl',
      calories: 154,
      proteinGrams: 6,
      carbsGrams: 27,
      fatGrams: 3.2,
      source: 'local_fixture',
      externalSource: 'local',
      externalId: 'food-oatmeal',
      confidence: 0.92,
    ),
  ];
}

List<MealTemplate> _seedTemplates(List<MealItem> catalog) {
  return [
    MealTemplate(
      id: 'local-template-breakfast',
      title: 'Yogurt breakfast',
      trustedAutoCommitEnabled: true,
      nutrition: _nutritionFor([catalog[0], catalog[1]]),
      items: [catalog[0], catalog[1]],
      aliases: const ['usual breakfast', 'yogurt bowl'],
    ),
    MealTemplate(
      id: 'local-template-lunch',
      title: 'Chicken rice lunch',
      trustedAutoCommitEnabled: false,
      nutrition: _nutritionFor([catalog[2], catalog[3], catalog[4]]),
      items: [catalog[2], catalog[3], catalog[4]],
      aliases: const ['chicken bowl', 'work lunch'],
    ),
  ];
}

Map<String, LocalAgentScenario> _seedAgentScenarios({
  required MealProposal proposal,
  required List<FoodCandidateGroup> candidateGroups,
}) {
  return {
    'proposal': LocalAgentScenario(
      label: 'proposal',
      transcript: 'local proposal',
      resultBuilder: (store) => AgentRunResult(
        kind: 'proposal',
        message: 'Review this local meal proposal.',
        proposal: store._proposals[proposal.id] ?? proposal,
        candidateGroups: store.candidateGroups,
      ),
    ),
    'auto_committed': LocalAgentScenario(
      label: 'auto_committed',
      transcript: 'local auto commit',
      resultBuilder: (store) {
        final meal = Meal(
          id: 'local-auto-committed-meal',
          title: 'Auto-committed local meal',
          occurredAt: store._now(),
          mealLabel: MealLabel.lunch,
          nutrition: proposal.nutrition,
          items: proposal.items,
        );
        return AgentRunResult(
          kind: 'meal_committed',
          message: 'Local meal auto-committed.',
          meal: meal,
          summary: store.getDailySummary(),
        );
      },
    ),
    'clarification': LocalAgentScenario(
      label: 'clarification',
      transcript: 'local clarification',
      resultBuilder: (store) => AgentRunResult(
        kind: 'clarification_required',
        message: 'Choose the matching local food candidate.',
        clarificationOptions: store.candidateGroups,
        candidateGroups: store.candidateGroups,
      ),
    ),
    'summary': LocalAgentScenario(
      label: 'summary',
      transcript: 'local summary',
      resultBuilder: (store) => AgentRunResult(
        kind: 'summary',
        message: 'Here is the local daily summary.',
        summary: store.getDailySummary(),
      ),
    ),
    'history': LocalAgentScenario(
      label: 'history',
      transcript: 'local history',
      resultBuilder: (store) => AgentRunResult(
        kind: 'history',
        message: 'Recent local meals.',
        meals: store.getMealHistory(),
      ),
    ),
    'templates': LocalAgentScenario(
      label: 'templates',
      transcript: 'local templates',
      resultBuilder: (store) => AgentRunResult(
        kind: 'templates',
        message: 'Local meal templates.',
        templates: store.templates,
      ),
    ),
    'search': LocalAgentScenario(
      label: 'search',
      transcript: 'local search',
      resultBuilder: (store) => AgentRunResult(
        kind: 'nutrition_search',
        message: 'Local food catalog matches.',
        items: store.foodCatalog.take(5).toList(growable: false),
        candidateGroups: store.candidateGroups,
      ),
    ),
  };
}

FoodCandidateGroup _seedCandidateGroup(List<MealItem> catalog) {
  return FoodCandidateGroup(
    mention: const FoodMention(
      originalText: 'rice',
      canonicalName: 'rice',
      canonicalEnglishName: 'rice',
      language: 'en',
      quantity: 1,
      unit: 'serving',
      confidence: 0.77,
    ),
    candidates: [
      catalog[3],
      catalog[6],
      const MealItem(
        name: 'Brown rice',
        canonicalName: 'Brown rice, cooked',
        quantity: 160,
        unit: 'g',
        calories: 178,
        proteinGrams: 4,
        carbsGrams: 37,
        fatGrams: 1.4,
        source: 'local_fixture',
        externalSource: 'local',
        externalId: 'food-brown-rice',
        confidence: 0.86,
        resolvedGrams: 160,
      ),
    ],
    reason: 'Multiple fixture foods can satisfy this mention.',
    portionOptions: const [
      FoodPortionChoice(
        label: '1 cup cooked',
        quantity: 1,
        unit: 'cup',
        totalGrams: 160,
        kind: 'serving',
      ),
      FoodPortionChoice(
        label: '100 g',
        quantity: 100,
        unit: 'g',
        totalGrams: 100,
        kind: 'weight',
      ),
    ],
  );
}

Meal _meal({
  required String id,
  required String title,
  required String date,
  required int hour,
  required MealLabel mealLabel,
  required List<MealItem> items,
}) {
  return Meal(
    id: id,
    title: title,
    occurredAt: DateTime.parse(
      '${date}T${hour.toString().padLeft(2, '0')}:00:00',
    ),
    mealLabel: mealLabel,
    nutrition: _nutritionFor(items),
    items: items,
  );
}

MealProposal _proposal({
  required String id,
  required String title,
  required List<MealItem> items,
  required double confidence,
}) {
  return MealProposal(
    id: id,
    title: title,
    confidence: confidence,
    requiresConfirmation: true,
    trustedAutoCommitEligible: true,
    nutrition: _nutritionFor(items),
    items: List.of(items),
  );
}

DailySummary _summaryFor({
  required String date,
  required List<Meal> meals,
  NutritionSnapshot target = _defaultTarget,
  double hydrationGoalLiters = 2.5,
  double waterConsumedLiters = 0,
  bool calorieTargetConfigured = true,
  String calorieTargetSource = 'manual',
  MacroMode? macroMode = MacroMode.percentage,
  MacroSource? macroSource = MacroSource.preset,
  MacroPreset? macroPreset = MacroPreset.balanced,
  int? proteinPct = 30,
  int? carbsPct = 40,
  int? fatPct = 30,
  int? macroCalories = 2200,
  int? calorieDeltaKcal = 0,
}) {
  final consumed = _nutritionForMeals(meals);
  return DailySummary(
    date: date,
    consumed: consumed,
    target: target,
    remaining: _remaining(target, consumed),
    hydrationGoalLiters: hydrationGoalLiters,
    waterConsumedLiters: waterConsumedLiters,
    calorieTargetConfigured: calorieTargetConfigured,
    calorieTargetSource: calorieTargetSource,
    macroMode: macroMode,
    macroSource: macroSource,
    macroPreset: macroPreset,
    proteinPct: proteinPct,
    carbsPct: carbsPct,
    fatPct: fatPct,
    macroCalories: macroCalories,
    calorieDeltaKcal: calorieDeltaKcal,
    meals: List.of(meals),
  );
}

DailySummary _copySummary(DailySummary summary, {double? waterConsumedLiters}) {
  return DailySummary(
    date: summary.date,
    consumed: summary.consumed,
    target: summary.target,
    remaining: summary.remaining,
    hydrationGoalLiters: summary.hydrationGoalLiters,
    waterConsumedLiters: waterConsumedLiters ?? summary.waterConsumedLiters,
    calorieTargetConfigured: summary.calorieTargetConfigured,
    calorieTargetSource: summary.calorieTargetSource,
    macroMode: summary.macroMode,
    macroSource: summary.macroSource,
    macroPreset: summary.macroPreset,
    proteinPct: summary.proteinPct,
    carbsPct: summary.carbsPct,
    fatPct: summary.fatPct,
    macroCalories: summary.macroCalories,
    calorieDeltaKcal: summary.calorieDeltaKcal,
    meals: summary.meals,
  );
}

NutritionSnapshot _nutritionForMeals(List<Meal> meals) {
  return NutritionSnapshot(
    calories: meals.fold(0, (sum, meal) => sum + meal.nutrition.calories),
    proteinGrams: meals.fold(
      0,
      (sum, meal) => sum + meal.nutrition.proteinGrams,
    ),
    carbsGrams: meals.fold(0, (sum, meal) => sum + meal.nutrition.carbsGrams),
    fatGrams: meals.fold(0, (sum, meal) => sum + meal.nutrition.fatGrams),
  );
}

NutritionSnapshot _nutritionFor(Iterable<MealItem> items) {
  return NutritionSnapshot(
    calories: items.fold(0, (sum, item) => sum + item.calories),
    proteinGrams: items.fold(0, (sum, item) => sum + item.proteinGrams),
    carbsGrams: items.fold(0, (sum, item) => sum + item.carbsGrams),
    fatGrams: items.fold(0, (sum, item) => sum + item.fatGrams),
  );
}

NutritionSnapshot _remaining(NutritionSnapshot target, NutritionSnapshot used) {
  return NutritionSnapshot(
    calories: target.calories - used.calories,
    proteinGrams: target.proteinGrams - used.proteinGrams,
    carbsGrams: target.carbsGrams - used.carbsGrams,
    fatGrams: target.fatGrams - used.fatGrams,
  );
}

NutritionSnapshot _targetFromConfig({
  required int calories,
  required NutritionSnapshot fallback,
  MacroDistributionConfig? macroConfig,
}) {
  final grams = switch (macroConfig?.mode) {
    MacroMode.percentage => gramsFromPercentages(
      calories,
      macroConfig!.percentages ?? MacroPreset.balanced.percentages,
    ),
    MacroMode.grams =>
      macroConfig!.grams ??
          MacroGrams(
            proteinGrams: fallback.proteinGrams,
            carbsGrams: fallback.carbsGrams,
            fatGrams: fallback.fatGrams,
          ),
    null => MacroGrams(
      proteinGrams: fallback.proteinGrams,
      carbsGrams: fallback.carbsGrams,
      fatGrams: fallback.fatGrams,
    ),
  };
  return NutritionSnapshot(
    calories: calories,
    proteinGrams: grams.proteinGrams,
    carbsGrams: grams.carbsGrams,
    fatGrams: grams.fatGrams,
  );
}

_MacroFields _macroFields({
  MacroDistributionConfig? macroConfig,
  required int calories,
  required DailySummary fallback,
}) {
  if (macroConfig == null) {
    return _MacroFields(
      mode: fallback.macroMode,
      source: fallback.macroSource,
      preset: fallback.macroPreset,
      proteinPct: fallback.proteinPct,
      carbsPct: fallback.carbsPct,
      fatPct: fallback.fatPct,
      macroCalories: fallback.macroCalories,
      calorieDeltaKcal: fallback.calorieDeltaKcal,
    );
  }
  final percentages = macroConfig.percentages;
  final grams =
      macroConfig.grams ??
      (percentages == null
          ? null
          : gramsFromPercentages(calories, percentages));
  return _MacroFields(
    mode: macroConfig.mode,
    source: macroConfig.source,
    preset: macroConfig.preset,
    proteinPct: percentages?.proteinPct,
    carbsPct: percentages?.carbsPct,
    fatPct: percentages?.fatPct,
    macroCalories: grams == null ? calories : macroCaloriesFromGrams(grams),
    calorieDeltaKcal: grams == null
        ? 0
        : macroCaloriesFromGrams(grams) - calories,
  );
}

String _dateOnly(DateTime value) {
  return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

String _formatFixtureQuantity(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

const _defaultTarget = NutritionSnapshot(
  calories: 2200,
  proteinGrams: 165,
  carbsGrams: 220,
  fatGrams: 73,
);

int localCalorieEstimate({
  required int age,
  required String sex,
  required double heightCm,
  required double weightKg,
  required String activityLevel,
  required String goal,
}) {
  final sexOffset = sex.toLowerCase() == 'female' ? -161 : 5;
  final bmr = (10 * weightKg + 6.25 * heightCm - 5 * age + sexOffset).round();
  final factor = switch (activityLevel) {
    'sedentary' => 1.2,
    'light' => 1.375,
    'moderate' => 1.55,
    'active' => 1.725,
    'very_active' => 1.9,
    _ => 1.45,
  };
  final maintenance = (bmr * factor).round();
  final adjustment = switch (goal) {
    'lose' => -400,
    'gain' => 300,
    _ => 0,
  };
  return math.max(1200, maintenance + adjustment);
}
