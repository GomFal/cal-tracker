import 'macro_distribution.dart';

class NutritionSnapshot {
  const NutritionSnapshot({
    required this.calories,
    required this.proteinGrams,
    required this.carbsGrams,
    required this.fatGrams,
  });

  final int calories;
  final double proteinGrams;
  final double carbsGrams;
  final double fatGrams;

  factory NutritionSnapshot.fromJson(Map<String, Object?> json) {
    return NutritionSnapshot(
      calories: (json['calories'] as num).toInt(),
      proteinGrams: (json['proteinGrams'] as num).toDouble(),
      carbsGrams: (json['carbsGrams'] as num).toDouble(),
      fatGrams: (json['fatGrams'] as num).toDouble(),
    );
  }
}

class DailyGoals {
  const DailyGoals({
    required this.date,
    required this.target,
    required this.hydrationGoalGlasses,
    required this.calorieTargetConfigured,
    required this.calorieTargetSource,
    this.macroMode,
    this.macroSource,
    this.macroPreset,
    this.proteinPct,
    this.carbsPct,
    this.fatPct,
    this.macroCalories,
    this.calorieDeltaKcal,
  });

  final String date;
  final NutritionSnapshot target;
  final int hydrationGoalGlasses;
  final bool calorieTargetConfigured;
  final String calorieTargetSource;
  final MacroMode? macroMode;
  final MacroSource? macroSource;
  final MacroPreset? macroPreset;
  final int? proteinPct;
  final int? carbsPct;
  final int? fatPct;
  final int? macroCalories;
  final int? calorieDeltaKcal;

  factory DailyGoals.fromJson(Map<String, Object?> json) {
    return DailyGoals(
      date: json['date'] as String,
      target:
          NutritionSnapshot.fromJson(json['target'] as Map<String, Object?>),
      hydrationGoalGlasses:
          (json['hydrationGoalGlasses'] as num? ?? 12).toInt(),
      calorieTargetConfigured: json['calorieTargetConfigured'] as bool? ?? true,
      calorieTargetSource: json['calorieTargetSource'] as String? ?? 'manual',
      macroMode: MacroMode.fromApi(json['macroMode'] as String?),
      macroSource: MacroSource.fromApi(json['macroSource'] as String?),
      macroPreset: MacroPreset.fromApi(json['macroPreset'] as String?),
      proteinPct: (json['proteinPct'] as num?)?.toInt(),
      carbsPct: (json['carbsPct'] as num?)?.toInt(),
      fatPct: (json['fatPct'] as num?)?.toInt(),
      macroCalories: (json['macroCalories'] as num?)?.toInt(),
      calorieDeltaKcal: (json['calorieDeltaKcal'] as num?)?.toInt(),
    );
  }
}

class CalorieEstimate {
  const CalorieEstimate({
    required this.bmr,
    required this.maintenanceCalories,
    required this.targetCalories,
    required this.recommendedRangeMin,
    required this.recommendedRangeMax,
    required this.activityFactor,
    required this.adjustmentCalories,
    required this.warnings,
    required this.explanation,
  });

  final int bmr;
  final int maintenanceCalories;
  final int targetCalories;
  final int recommendedRangeMin;
  final int recommendedRangeMax;
  final double activityFactor;
  final int adjustmentCalories;
  final List<String> warnings;
  final String explanation;

  factory CalorieEstimate.fromJson(Map<String, Object?> json) {
    final range = json['recommendedRange'] as Map<String, Object?>;
    return CalorieEstimate(
      bmr: (json['bmr'] as num).toInt(),
      maintenanceCalories: (json['maintenanceCalories'] as num).toInt(),
      targetCalories: (json['targetCalories'] as num).toInt(),
      recommendedRangeMin: (range['min'] as num).toInt(),
      recommendedRangeMax: (range['max'] as num).toInt(),
      activityFactor: (json['activityFactor'] as num).toDouble(),
      adjustmentCalories: (json['adjustmentCalories'] as num).toInt(),
      warnings: (json['warnings'] as List<Object?>? ?? const [])
          .map((value) => value.toString())
          .toList(),
      explanation: json['explanation'] as String? ?? '',
    );
  }
}

class MealItem {
  const MealItem({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.calories,
    required this.proteinGrams,
    required this.carbsGrams,
    required this.fatGrams,
    required this.source,
    this.originalText,
    this.canonicalName,
    this.externalSource,
    this.externalId,
    this.sourceUrl,
    this.license,
    this.confidence,
    this.needsReview,
    this.resolvedGrams,
    this.portionDescription,
  });

  final String name;
  final double quantity;
  final String unit;
  final int calories;
  final double proteinGrams;
  final double carbsGrams;
  final double fatGrams;
  final String source;
  final String? originalText;
  final String? canonicalName;
  final String? externalSource;
  final String? externalId;
  final String? sourceUrl;
  final String? license;
  final double? confidence;
  final bool? needsReview;
  final double? resolvedGrams;
  final String? portionDescription;

  factory MealItem.fromJson(Map<String, Object?> json) {
    return MealItem(
      name: json['name'] as String,
      quantity: (json['quantity'] as num).toDouble(),
      unit: json['unit'] as String,
      calories: (json['calories'] as num).toInt(),
      proteinGrams: (json['proteinGrams'] as num).toDouble(),
      carbsGrams: (json['carbsGrams'] as num).toDouble(),
      fatGrams: (json['fatGrams'] as num).toDouble(),
      source: json['source'] as String? ?? 'backend_estimate',
      originalText: json['originalText'] as String?,
      canonicalName: json['canonicalName'] as String?,
      externalSource: json['externalSource'] as String?,
      externalId: json['externalId'] as String?,
      sourceUrl: json['sourceUrl'] as String?,
      license: json['license'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble(),
      needsReview: json['needsReview'] as bool?,
      resolvedGrams: (json['resolvedGrams'] as num?)?.toDouble(),
      portionDescription: json['portionDescription'] as String?,
    );
  }

  Map<String, Object?> toJson() => {
        'name': name,
        'quantity': quantity,
        'unit': unit,
        'calories': calories,
        'proteinGrams': proteinGrams,
        'carbsGrams': carbsGrams,
        'fatGrams': fatGrams,
        'source': source,
        if (originalText != null) 'originalText': originalText,
        if (canonicalName != null) 'canonicalName': canonicalName,
        if (externalSource != null) 'externalSource': externalSource,
        if (externalId != null) 'externalId': externalId,
        if (sourceUrl != null) 'sourceUrl': sourceUrl,
        if (license != null) 'license': license,
        if (confidence != null) 'confidence': confidence,
        if (needsReview != null) 'needsReview': needsReview,
        if (resolvedGrams != null) 'resolvedGrams': resolvedGrams,
        if (portionDescription != null)
          'portionDescription': portionDescription,
      };

  MealItem copyWith({
    String? name,
    double? quantity,
    String? unit,
    int? calories,
    double? proteinGrams,
    double? carbsGrams,
    double? fatGrams,
    String? source,
    String? originalText,
    String? canonicalName,
    String? externalSource,
    String? externalId,
    String? sourceUrl,
    String? license,
    double? confidence,
    bool? needsReview,
    double? resolvedGrams,
    String? portionDescription,
  }) {
    return MealItem(
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      calories: calories ?? this.calories,
      proteinGrams: proteinGrams ?? this.proteinGrams,
      carbsGrams: carbsGrams ?? this.carbsGrams,
      fatGrams: fatGrams ?? this.fatGrams,
      source: source ?? this.source,
      originalText: originalText ?? this.originalText,
      canonicalName: canonicalName ?? this.canonicalName,
      externalSource: externalSource ?? this.externalSource,
      externalId: externalId ?? this.externalId,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      license: license ?? this.license,
      confidence: confidence ?? this.confidence,
      needsReview: needsReview ?? this.needsReview,
      resolvedGrams: resolvedGrams ?? this.resolvedGrams,
      portionDescription: portionDescription ?? this.portionDescription,
    );
  }
}

class FoodPortionChoice {
  const FoodPortionChoice({
    required this.label,
    required this.quantity,
    required this.unit,
    this.gramWeight,
    this.totalGrams,
    this.kind,
    this.portionDescriptor,
    this.canonicalFoodName,
    this.sourceDescription,
    this.externalSource,
    this.externalFoodId,
    this.actionText,
  });

  final String label;
  final double quantity;
  final String unit;
  final double? gramWeight;
  final double? totalGrams;
  final String? kind;
  final String? portionDescriptor;
  final String? canonicalFoodName;
  final String? sourceDescription;
  final String? externalSource;
  final String? externalFoodId;
  final String? actionText;

  factory FoodPortionChoice.fromJson(Map<String, Object?> json) {
    return FoodPortionChoice(
      label: json['label'] as String,
      quantity: (json['quantity'] as num).toDouble(),
      unit: json['unit'] as String,
      gramWeight: (json['gramWeight'] as num?)?.toDouble(),
      totalGrams: (json['totalGrams'] as num?)?.toDouble(),
      kind: json['kind'] as String?,
      portionDescriptor: json['portionDescriptor'] as String?,
      canonicalFoodName: json['canonicalFoodName'] as String?,
      sourceDescription: json['sourceDescription'] as String?,
      externalSource: json['externalSource'] as String?,
      externalFoodId: json['externalFoodId'] as String?,
      actionText: json['actionText'] as String?,
    );
  }
}

class FoodMention {
  const FoodMention({
    required this.originalText,
    String? canonicalName,
    this.canonicalEnglishName,
    this.language,
    required this.quantity,
    required this.unit,
    required this.confidence,
    required this.marketProduct,
    this.rawUnitText,
    this.unitKind,
    this.portionDescriptorRaw,
    this.portionDescriptor,
    this.brand,
    this.barcode,
  }) : canonicalName = canonicalName ?? canonicalEnglishName ?? originalText;

  final String originalText;
  final String canonicalName;
  final String? canonicalEnglishName;
  final String? language;
  final double quantity;
  final String unit;
  final double confidence;
  final bool marketProduct;
  final String? rawUnitText;
  final String? unitKind;
  final String? portionDescriptorRaw;
  final String? portionDescriptor;
  final String? brand;
  final String? barcode;

  factory FoodMention.fromJson(Map<String, Object?> json) {
    final originalText = json['originalText'] as String;
    final canonicalName = json['canonicalName'] as String?;
    final canonicalEnglishName = json['canonicalEnglishName'] as String?;
    return FoodMention(
      originalText: originalText,
      canonicalName: canonicalName ?? canonicalEnglishName ?? originalText,
      canonicalEnglishName: canonicalEnglishName,
      language: json['language'] as String?,
      quantity: (json['quantity'] as num).toDouble(),
      unit: json['unit'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      marketProduct: json['marketProduct'] as bool? ?? false,
      rawUnitText: json['rawUnitText'] as String?,
      unitKind: json['unitKind'] as String?,
      portionDescriptorRaw: json['portionDescriptorRaw'] as String?,
      portionDescriptor: json['portionDescriptor'] as String?,
      brand: json['brand'] as String?,
      barcode: json['barcode'] as String?,
    );
  }
}

class FoodCandidateGroup {
  const FoodCandidateGroup({
    required this.mention,
    required this.candidates,
    this.reason,
    this.portionOptions,
  });

  final FoodMention mention;
  final List<MealItem> candidates;
  final String? reason;
  final List<FoodPortionChoice>? portionOptions;

  factory FoodCandidateGroup.fromJson(Map<String, Object?> json) {
    return FoodCandidateGroup(
      mention: FoodMention.fromJson(json['mention'] as Map<String, Object?>),
      candidates: (json['candidates'] as List<Object?>? ?? const [])
          .cast<Map<String, Object?>>()
          .map(MealItem.fromJson)
          .toList(),
      reason: json['reason'] as String?,
      portionOptions: json['portionOptions'] == null
          ? null
          : (json['portionOptions'] as List<Object?>)
              .cast<Map<String, Object?>>()
              .map(FoodPortionChoice.fromJson)
              .toList(),
    );
  }
}

class MealProposal {
  const MealProposal({
    required this.id,
    required this.title,
    required this.confidence,
    required this.requiresConfirmation,
    required this.trustedAutoCommitEligible,
    required this.nutrition,
    required this.items,
  });

  final String id;
  final String title;
  final double confidence;
  final bool requiresConfirmation;
  final bool trustedAutoCommitEligible;
  final NutritionSnapshot nutrition;
  final List<MealItem> items;

  factory MealProposal.fromJson(Map<String, Object?> json) {
    return MealProposal(
      id: json['id'] as String,
      title: json['title'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      requiresConfirmation: json['requiresConfirmation'] as bool,
      trustedAutoCommitEligible: json['trustedAutoCommitEligible'] as bool,
      nutrition:
          NutritionSnapshot.fromJson(json['nutrition'] as Map<String, Object?>),
      items: (json['items'] as List<Object?>)
          .cast<Map<String, Object?>>()
          .map(MealItem.fromJson)
          .toList(),
    );
  }
}

class MealLabel {
  const MealLabel({
    required this.type,
    required this.label,
  });

  final String type;
  final String label;

  static const breakfast = MealLabel(type: 'breakfast', label: 'Breakfast');
  static const lunch = MealLabel(type: 'lunch', label: 'Lunch');
  static const dinner = MealLabel(type: 'dinner', label: 'Dinner');
  static const snack = MealLabel(type: 'snack', label: 'Snack');
  static const preWorkout =
      MealLabel(type: 'pre_workout', label: 'Pre-workout');
  static const postWorkout =
      MealLabel(type: 'post_workout', label: 'Post-workout');

  factory MealLabel.other(String label) {
    return MealLabel(type: 'other', label: label.trim());
  }

  factory MealLabel.fromJson(Map<String, Object?> json) {
    return MealLabel(
      type: json['type'] as String,
      label: json['label'] as String,
    );
  }

  Map<String, Object?> toJson() => {
        'type': type,
        'label': label,
      };

  @override
  bool operator ==(Object other) {
    return other is MealLabel && other.type == type && other.label == label;
  }

  @override
  int get hashCode => Object.hash(type, label);
}

class Meal {
  const Meal({
    required this.id,
    required this.title,
    required this.occurredAt,
    required this.nutrition,
    required this.items,
    this.mealLabel,
  });

  final String id;
  final String title;
  final DateTime occurredAt;
  final MealLabel? mealLabel;
  final NutritionSnapshot nutrition;
  final List<MealItem> items;

  factory Meal.fromJson(Map<String, Object?> json) {
    return Meal(
      id: json['id'] as String,
      title: json['title'] as String,
      occurredAt: DateTime.parse(json['occurredAt'] as String),
      mealLabel: json['mealLabel'] == null
          ? null
          : MealLabel.fromJson(json['mealLabel'] as Map<String, Object?>),
      nutrition:
          NutritionSnapshot.fromJson(json['nutrition'] as Map<String, Object?>),
      items: (json['items'] as List<Object?>)
          .cast<Map<String, Object?>>()
          .map(MealItem.fromJson)
          .toList(),
    );
  }
}

class DailySummary {
  const DailySummary({
    required this.date,
    required this.consumed,
    required this.target,
    required this.remaining,
    required this.hydrationGoalGlasses,
    required this.calorieTargetConfigured,
    required this.calorieTargetSource,
    this.macroMode,
    this.macroSource,
    this.macroPreset,
    this.proteinPct,
    this.carbsPct,
    this.fatPct,
    this.macroCalories,
    this.calorieDeltaKcal,
    required this.meals,
  });

  final String date;
  final NutritionSnapshot consumed;
  final NutritionSnapshot target;
  final NutritionSnapshot remaining;
  final int hydrationGoalGlasses;
  final bool calorieTargetConfigured;
  final String calorieTargetSource;
  final MacroMode? macroMode;
  final MacroSource? macroSource;
  final MacroPreset? macroPreset;
  final int? proteinPct;
  final int? carbsPct;
  final int? fatPct;
  final int? macroCalories;
  final int? calorieDeltaKcal;
  final List<Meal> meals;

  factory DailySummary.fromJson(Map<String, Object?> json) {
    return DailySummary(
      date: json['date'] as String,
      consumed:
          NutritionSnapshot.fromJson(json['consumed'] as Map<String, Object?>),
      target:
          NutritionSnapshot.fromJson(json['target'] as Map<String, Object?>),
      remaining:
          NutritionSnapshot.fromJson(json['remaining'] as Map<String, Object?>),
      hydrationGoalGlasses:
          (json['hydrationGoalGlasses'] as num? ?? 12).toInt(),
      calorieTargetConfigured: json['calorieTargetConfigured'] as bool? ?? true,
      calorieTargetSource: json['calorieTargetSource'] as String? ?? 'manual',
      macroMode: MacroMode.fromApi(json['macroMode'] as String?),
      macroSource: MacroSource.fromApi(json['macroSource'] as String?),
      macroPreset: MacroPreset.fromApi(json['macroPreset'] as String?),
      proteinPct: (json['proteinPct'] as num?)?.toInt(),
      carbsPct: (json['carbsPct'] as num?)?.toInt(),
      fatPct: (json['fatPct'] as num?)?.toInt(),
      macroCalories: (json['macroCalories'] as num?)?.toInt(),
      calorieDeltaKcal: (json['calorieDeltaKcal'] as num?)?.toInt(),
      meals: (json['meals'] as List<Object?>)
          .cast<Map<String, Object?>>()
          .map(Meal.fromJson)
          .toList(),
    );
  }
}

class MealTemplate {
  const MealTemplate({
    required this.id,
    required this.title,
    required this.trustedAutoCommitEnabled,
    required this.nutrition,
    required this.items,
    required this.aliases,
  });

  final String id;
  final String title;
  final bool trustedAutoCommitEnabled;
  final NutritionSnapshot nutrition;
  final List<MealItem> items;
  final List<String> aliases;

  factory MealTemplate.fromJson(Map<String, Object?> json) {
    return MealTemplate(
      id: json['id'] as String,
      title: json['title'] as String,
      trustedAutoCommitEnabled: json['trustedAutoCommitEnabled'] as bool,
      nutrition:
          NutritionSnapshot.fromJson(json['nutrition'] as Map<String, Object?>),
      items: (json['items'] as List<Object?>)
          .cast<Map<String, Object?>>()
          .map(MealItem.fromJson)
          .toList(),
      aliases: (json['aliases'] as List<Object?>? ?? const []).cast<String>(),
    );
  }

  Map<String, Object?> toUpdateJson() => {
        'title': title,
        'trustedAutoCommitEnabled': trustedAutoCommitEnabled,
        'items': items.map((item) => item.toJson()).toList(),
        'aliases': aliases,
      };
}
