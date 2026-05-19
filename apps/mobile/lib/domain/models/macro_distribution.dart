const proteinKcalPerGram = 4;
const carbsKcalPerGram = 4;
const fatKcalPerGram = 9;

enum MacroMode {
  percentage('percentage'),
  grams('grams');

  const MacroMode(this.apiValue);

  final String apiValue;

  static MacroMode? fromApi(String? value) {
    for (final mode in values) {
      if (mode.apiValue == value) return mode;
    }
    return null;
  }
}

enum MacroSource {
  preset('preset'),
  custom('custom');

  const MacroSource(this.apiValue);

  final String apiValue;

  static MacroSource? fromApi(String? value) {
    for (final source in values) {
      if (source.apiValue == value) return source;
    }
    return null;
  }
}

enum MacroPreset {
  balanced('balanced', 'Balanced', 30, 40, 30),
  highProtein('high_protein', 'High protein', 35, 35, 30),
  lowerCarb('lower_carb', 'Lower carb', 35, 25, 40);

  const MacroPreset(
    this.apiValue,
    this.label,
    this.proteinPct,
    this.carbsPct,
    this.fatPct,
  );

  final String apiValue;
  final String label;
  final int proteinPct;
  final int carbsPct;
  final int fatPct;

  MacroPercentages get percentages => MacroPercentages(
        proteinPct: proteinPct,
        carbsPct: carbsPct,
        fatPct: fatPct,
      );

  static MacroPreset? fromApi(String? value) {
    for (final preset in values) {
      if (preset.apiValue == value) return preset;
    }
    return null;
  }
}

enum MacroCalorieWarningLevel {
  none,
  soft,
  clear,
}

class MacroPercentages {
  const MacroPercentages({
    required this.proteinPct,
    required this.carbsPct,
    required this.fatPct,
  });

  final int proteinPct;
  final int carbsPct;
  final int fatPct;

  int get total => proteinPct + carbsPct + fatPct;
}

class MacroGrams {
  const MacroGrams({
    required this.proteinGrams,
    required this.carbsGrams,
    required this.fatGrams,
  });

  final double proteinGrams;
  final double carbsGrams;
  final double fatGrams;
}

class MacroDistributionConfig {
  const MacroDistributionConfig({
    required this.mode,
    required this.source,
    this.preset,
    this.percentages,
    this.grams,
  });

  factory MacroDistributionConfig.preset(MacroPreset preset) {
    return MacroDistributionConfig(
      mode: MacroMode.percentage,
      source: MacroSource.preset,
      preset: preset,
      percentages: preset.percentages,
    );
  }

  factory MacroDistributionConfig.percentage({
    required int proteinPct,
    required int carbsPct,
    required int fatPct,
  }) {
    return MacroDistributionConfig(
      mode: MacroMode.percentage,
      source: MacroSource.custom,
      percentages: MacroPercentages(
        proteinPct: proteinPct,
        carbsPct: carbsPct,
        fatPct: fatPct,
      ),
    );
  }

  factory MacroDistributionConfig.grams({
    required double proteinGrams,
    required double carbsGrams,
    required double fatGrams,
  }) {
    return MacroDistributionConfig(
      mode: MacroMode.grams,
      source: MacroSource.custom,
      grams: MacroGrams(
        proteinGrams: proteinGrams,
        carbsGrams: carbsGrams,
        fatGrams: fatGrams,
      ),
    );
  }

  final MacroMode mode;
  final MacroSource source;
  final MacroPreset? preset;
  final MacroPercentages? percentages;
  final MacroGrams? grams;

  Map<String, Object?> toApiJson({int? calories}) {
    final fields = <String, Object?>{
      'macroMode': mode.apiValue,
      'macroSource': source.apiValue,
      'macroPreset': preset?.apiValue,
    };
    final percentages = this.percentages;
    if (percentages != null) {
      fields.addAll({
        'proteinPct': percentages.proteinPct,
        'carbsPct': percentages.carbsPct,
        'fatPct': percentages.fatPct,
      });
      if (calories != null) {
        final grams = gramsFromPercentages(calories, percentages);
        fields.addAll(_calculatedFields(calories, grams));
      }
    }
    final grams = this.grams;
    if (grams != null) {
      fields.addAll({
        'proteinGrams': grams.proteinGrams,
        'carbsGrams': grams.carbsGrams,
        'fatGrams': grams.fatGrams,
      });
      if (calories != null) {
        fields.addAll(_calculatedFields(calories, grams));
      }
    }
    return fields;
  }
}

MacroGrams gramsFromPercentages(
  int calories,
  MacroPercentages percentages,
) {
  return MacroGrams(
    proteinGrams:
        ((calories * percentages.proteinPct / 100) / proteinKcalPerGram)
            .roundToDouble(),
    carbsGrams: ((calories * percentages.carbsPct / 100) / carbsKcalPerGram)
        .roundToDouble(),
    fatGrams: ((calories * percentages.fatPct / 100) / fatKcalPerGram)
        .roundToDouble(),
  );
}

int macroCaloriesFromGrams(MacroGrams grams) {
  return (grams.proteinGrams * proteinKcalPerGram +
          grams.carbsGrams * carbsKcalPerGram +
          grams.fatGrams * fatKcalPerGram)
      .round();
}

int calorieDeltaKcal(int calories, MacroGrams grams) {
  return macroCaloriesFromGrams(grams) - calories;
}

MacroCalorieWarningLevel macroWarningLevel(int calorieDeltaKcal) {
  final absoluteDelta = calorieDeltaKcal.abs();
  if (absoluteDelta <= 25) return MacroCalorieWarningLevel.none;
  if (absoluteDelta <= 75) return MacroCalorieWarningLevel.soft;
  return MacroCalorieWarningLevel.clear;
}

MacroPercentages percentagesFromGrams(int calories, MacroGrams grams) {
  if (calories <= 0) {
    return const MacroPercentages(proteinPct: 0, carbsPct: 0, fatPct: 0);
  }
  final proteinPct =
      ((grams.proteinGrams * proteinKcalPerGram) / calories * 100).round();
  final carbsPct =
      ((grams.carbsGrams * carbsKcalPerGram) / calories * 100).round();
  final fatPct = (100 - proteinPct - carbsPct).clamp(0, 100).toInt();
  return MacroPercentages(
    proteinPct: proteinPct.clamp(0, 100).toInt(),
    carbsPct: carbsPct.clamp(0, 100).toInt(),
    fatPct: fatPct,
  );
}

Map<String, Object?> _calculatedFields(int calories, MacroGrams grams) {
  final macroCalories = macroCaloriesFromGrams(grams);
  return {
    'macroCalories': macroCalories,
    'calorieDeltaKcal': macroCalories - calories,
  };
}
