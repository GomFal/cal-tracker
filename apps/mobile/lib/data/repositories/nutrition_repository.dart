import 'dart:io';

import '../../domain/models/macro_distribution.dart';
import '../../domain/models/nutrition_models.dart';
import '../../generated/api/cal_tracker_api.dart';

class AgentRunResult {
  const AgentRunResult({
    required this.kind,
    required this.message,
    this.proposal,
    this.meal,
    this.summary,
    this.remaining,
    this.meals,
    this.items,
    this.templates,
    this.template,
    this.resolvedItems,
    this.deleted,
    this.actionId,
    this.input,
    this.clarificationOptions,
    this.candidateGroups,
  });

  final String kind;
  final String message;
  final MealProposal? proposal;
  final Meal? meal;
  final DailySummary? summary;
  final NutritionSnapshot? remaining;
  final List<Meal>? meals;
  final List<MealItem>? items;
  final List<MealTemplate>? templates;
  final MealTemplate? template;
  final List<MealItem>? resolvedItems;
  final bool? deleted;
  final String? actionId;
  final dynamic input;
  final List<FoodCandidateGroup>? clarificationOptions;
  final List<FoodCandidateGroup>? candidateGroups;
}

class VoiceMealRunResult {
  const VoiceMealRunResult({
    required this.transcript,
    required this.provider,
    required this.model,
    required this.traceId,
    required this.result,
  });

  final String transcript;
  final String provider;
  final String model;
  final String traceId;
  final AgentRunResult result;
}

class FoodSearchResult {
  const FoodSearchResult({
    required this.items,
    this.candidateGroups,
  });

  final List<MealItem> items;
  final List<FoodCandidateGroup>? candidateGroups;
}

class NutritionRepository {
  NutritionRepository({required CalTrackerApiClient apiClient})
      : _apiClient = apiClient;

  final CalTrackerApiClient _apiClient;

  Future<AgentRunResult> logText(
    String text, {
    String? activeProposalId,
  }) async {
    final json = activeProposalId == null
        ? await _apiClient.runAgent(text)
        : await _apiClient.runAgent(text, activeProposalId: activeProposalId);
    return _parseAgentRunResult(json);
  }

  Future<VoiceMealRunResult> logAudio(
    File audioFile, {
    String? activeProposalId,
  }) async {
    final json = activeProposalId == null
        ? await _apiClient.runVoiceMeal(audioFile, source: 'flutter')
        : await _apiClient.runVoiceMeal(
            audioFile,
            source: 'flutter',
            activeProposalId: activeProposalId,
          );
    return VoiceMealRunResult(
      transcript: json['transcript'] as String,
      provider: json['provider'] as String,
      model: json['model'] as String,
      traceId: json['traceId'] as String,
      result: _parseAgentRunResult(json['result'] as Map<String, Object?>),
    );
  }

  Future<FoodSearchResult> searchFoods(
    String query, {
    int limit = 10,
    String? barcode,
  }) async {
    final json = await _apiClient.searchFoods(
      query: query,
      barcode: barcode,
      limit: limit,
    );
    return FoodSearchResult(
      items: (json['items'] as List<Object?>? ?? const [])
          .cast<Map<String, Object?>>()
          .map(MealItem.fromJson)
          .toList(),
      candidateGroups: _parseCandidateGroups(json['candidateGroups']),
    );
  }

  AgentRunResult _parseAgentRunResult(Map<String, Object?> json) {
    final kind = json['kind'] as String;
    return AgentRunResult(
      kind: kind,
      message: json['message'] as String,
      proposal: json['proposal'] == null
          ? null
          : MealProposal.fromJson(json['proposal'] as Map<String, Object?>),
      meal: json['meal'] == null
          ? null
          : Meal.fromJson(json['meal'] as Map<String, Object?>),
      summary: json['summary'] == null
          ? null
          : DailySummary.fromJson(json['summary'] as Map<String, Object?>),
      remaining: json['remaining'] == null
          ? null
          : NutritionSnapshot.fromJson(
              json['remaining'] as Map<String, Object?>,
            ),
      meals: json['meals'] == null
          ? null
          : (json['meals'] as List<Object?>)
              .cast<Map<String, Object?>>()
              .map(Meal.fromJson)
              .toList(),
      items: json['items'] == null
          ? null
          : (json['items'] as List<Object?>)
              .cast<Map<String, Object?>>()
              .map(MealItem.fromJson)
              .toList(),
      templates: json['templates'] == null
          ? null
          : (json['templates'] as List<Object?>)
              .cast<Map<String, Object?>>()
              .map(MealTemplate.fromJson)
              .toList(),
      template: json['template'] == null
          ? null
          : MealTemplate.fromJson(json['template'] as Map<String, Object?>),
      resolvedItems: json['resolvedItems'] == null
          ? null
          : (json['resolvedItems'] as List<Object?>)
              .cast<Map<String, Object?>>()
              .map(MealItem.fromJson)
              .toList(),
      deleted: json['deleted'] as bool?,
      actionId: json['actionId'] as String?,
      input: json['input'],
      clarificationOptions: _parseCandidateGroups(json['options']),
      candidateGroups: _parseCandidateGroups(json['candidateGroups']) ??
          _parseCandidateGroups(json['options']),
    );
  }

  Future<Meal> commitProposal(String proposalId, {MealLabel? mealLabel}) async {
    final json = await _apiClient.commitProposal(
      proposalId,
      mealLabel: mealLabel,
    );
    final output = json['output'] as Map<String, Object?>;
    return Meal.fromJson(output['meal'] as Map<String, Object?>);
  }

  Future<Meal> correctMealItems(String mealId, List<MealItem> items) async {
    final json = await _apiClient.correctMeal(
      mealId,
      items.map((item) => item.toJson()).toList(),
    );
    final output = json['output'] as Map<String, Object?>;
    return Meal.fromJson(output['meal'] as Map<String, Object?>);
  }

  Future<MealProposal> updateProposalItems(
    String proposalId,
    List<MealItem> items,
  ) async {
    final json = await _apiClient.correctProposal(
      proposalId: proposalId,
      items: items.map((item) => item.toJson()).toList(),
    );
    final output = json['output'] as Map<String, Object?>;
    return MealProposal.fromJson(output['proposal'] as Map<String, Object?>);
  }

  Future<MealProposal> createProposalFromItems({
    required String phrase,
    required List<MealItem> items,
    String? title,
  }) async {
    final json =
        await _apiClient.executeAction('create_meal_proposal_from_items', {
      'phrase': phrase,
      if (title != null) 'title': title,
      'items': items.map((item) => item.toJson()).toList(),
    });
    final output = json['output'] as Map<String, Object?>;
    return MealProposal.fromJson(output['proposal'] as Map<String, Object?>);
  }

  Future<bool> deleteMeal(String mealId, {bool confirmed = false}) async {
    final json = await _apiClient.deleteMeal(mealId, confirmed: confirmed);
    final output = json['output'] as Map<String, Object?>;
    return output['deleted'] as bool? ?? false;
  }

  Future<DailySummary> getDailySummary({String? date}) async {
    final json = await _apiClient.getDailySummary(
      date: date ?? DateTime.now().toIso8601String().substring(0, 10),
    );
    final output = json['output'] as Map<String, Object?>;
    return DailySummary.fromJson(output['summary'] as Map<String, Object?>);
  }

  Future<DailyGoals> updateDailyGoals({
    String? date,
    int? calories,
    double? hydrationGoalLiters,
    String? calorieTargetSource,
    MacroDistributionConfig? macroConfig,
    int? macroCalorieTarget,
  }) async {
    final macroTargetCalories = macroCalorieTarget ?? calories;
    if (macroConfig != null &&
        (macroTargetCalories == null ||
            !isValidMacroConfig(macroConfig, calories: macroTargetCalories))) {
      throw ArgumentError('Invalid macro configuration');
    }
    final json = await _apiClient.updateDailyGoals(
      date: date ?? DateTime.now().toIso8601String().substring(0, 10),
      calories: calories,
      hydrationGoalLiters: hydrationGoalLiters,
      calorieTargetSource: calorieTargetSource,
      macroFields: macroConfig?.toApiJson(calories: macroTargetCalories),
    );
    return DailyGoals.fromJson(json['goals'] as Map<String, Object?>);
  }

  Future<DailySummary> updateDailyHydration({
    String? date,
    required double waterConsumedLiters,
  }) async {
    final json = await _apiClient.updateDailyHydration(
      date: date ?? DateTime.now().toIso8601String().substring(0, 10),
      waterConsumedLiters: waterConsumedLiters,
    );
    return DailySummary.fromJson(json['summary'] as Map<String, Object?>);
  }

  Future<CalorieEstimate> estimateCalories({
    required int age,
    required String sex,
    required double heightCm,
    required double weightKg,
    required String activityLevel,
    required String goal,
    String? pace,
  }) async {
    final json = await _apiClient.estimateCalories({
      'age': age,
      'sex': sex,
      'heightCm': heightCm,
      'weightKg': weightKg,
      'activityLevel': activityLevel,
      'goal': goal,
      if (pace != null) 'pace': pace,
    });
    return CalorieEstimate.fromJson(json);
  }

  Future<List<Meal>> getMealHistory() async {
    final json = await _apiClient.getMealHistory();
    final output = json['output'] as Map<String, Object?>;
    return (output['meals'] as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(Meal.fromJson)
        .toList();
  }

  Future<List<MealTemplate>> getTemplates() async {
    final json = await _apiClient.getTemplates();
    final output = json['output'] as Map<String, Object?>;
    return (output['templates'] as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(MealTemplate.fromJson)
        .toList();
  }

  Future<MealTemplate> setTemplateTrustedMode(
    MealTemplate template,
    bool enabled,
  ) async {
    final body = template.toUpdateJson()
      ..['trustedAutoCommitEnabled'] = enabled;
    final json = await _apiClient.updateTemplate(template.id, body);
    final output = json['output'] as Map<String, Object?>;
    return MealTemplate.fromJson(output['template'] as Map<String, Object?>);
  }

  Future<MealTemplate> createTemplate({
    required String title,
    required List<MealItem> items,
    required List<String> aliases,
  }) async {
    final json = await _apiClient.createTemplate({
      'title': title,
      'trustedAutoCommitEnabled': false,
      'items': items.map((item) => item.toJson()).toList(),
      'aliases': aliases,
    });
    final output = json['output'] as Map<String, Object?>;
    return MealTemplate.fromJson(output['template'] as Map<String, Object?>);
  }

  Future<bool> deleteTemplate(String templateId) async {
    final json = await _apiClient.deleteTemplate(templateId);
    final output = json['output'] as Map<String, Object?>;
    return output['deleted'] as bool? ?? false;
  }

  Future<String> transcribeAudio(File audioFile) async {
    final json = await _apiClient.transcribeAudio(audioFile, source: 'flutter');
    return json['transcript'] as String;
  }
}

List<FoodCandidateGroup>? _parseCandidateGroups(Object? value) {
  if (value is! List<Object?>) return null;
  final groups = <FoodCandidateGroup>[];
  for (final item in value) {
    if (item is Map<String, Object?> &&
        item['mention'] is Map<String, Object?>) {
      groups.add(FoodCandidateGroup.fromJson(item));
    }
  }
  return groups.isEmpty ? null : groups;
}
