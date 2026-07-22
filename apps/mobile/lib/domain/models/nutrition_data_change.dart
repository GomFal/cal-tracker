import 'nutrition_models.dart';

enum NutritionDataDomain {
  dailySummary,
  dailyGoals,
  mealTemplates,
  usualFoods,
}

enum NutritionDataOperation { replace, upsert, delete, invalidate }

/// A backend-derived effect. Unknown versions, domains, operations and invalid
/// keys are intentionally discarded by [ConfirmedNutritionMutation.tryParse].
class NutritionDataEffect {
  const NutritionDataEffect({
    required this.domain,
    required this.operation,
    this.date,
    this.entityId,
    this.revision,
    this.snapshot,
  });

  final NutritionDataDomain domain;
  final NutritionDataOperation operation;
  final String? date;
  final String? entityId;
  final String? revision;
  final Map<String, Object?>? snapshot;

  DailySummary? get dailySummary {
    final value = snapshot;
    if (value == null) return null;
    try {
      return DailySummary.fromJson(value);
    } on Object {
      return null;
    }
  }

  DailyGoals? get dailyGoals {
    final value = snapshot;
    if (value == null) return null;
    try {
      return DailyGoals.fromJson(value);
    } on Object {
      return null;
    }
  }

  MealTemplate? get mealTemplate {
    final value = snapshot;
    if (value == null) return null;
    try {
      return MealTemplate.fromJson(value);
    } on Object {
      return null;
    }
  }

  UsualFood? get usualFood {
    final value = snapshot;
    if (value == null) return null;
    try {
      return UsualFood.fromJson(value);
    } on Object {
      return null;
    }
  }
}

class ConfirmedNutritionMutation {
  const ConfirmedNutritionMutation({
    required this.version,
    required this.mutationId,
    required this.committedAt,
    required this.effects,
  });

  final int version;
  final String mutationId;
  final DateTime committedAt;
  final List<NutritionDataEffect> effects;

  static ConfirmedNutritionMutation? tryParse(Object? value) {
    try {
      if (value is! Map) return null;
      final json = _objectMap(value);
      if (json['version'] != 1) return null;
      final mutationId = json['mutationId'];
      final committedAt = json['committedAt'];
      if (mutationId is! String ||
          !_uuidPattern.hasMatch(mutationId) ||
          committedAt is! String) {
        return null;
      }
      final parsedCommittedAt = DateTime.tryParse(committedAt);
      if (parsedCommittedAt == null) return null;
      final rawEffects = json['effects'];
      if (rawEffects is! List) return null;
      final effects = rawEffects
          .map(_parseEffect)
          .whereType<NutritionDataEffect>()
          .toList(growable: false);
      if (effects.isEmpty) return null;
      return ConfirmedNutritionMutation(
        version: 1,
        mutationId: mutationId,
        committedAt: parsedCommittedAt,
        effects: effects,
      );
    } on Object {
      return null;
    }
  }

  Map<String, Object?> toJson() => {
        'version': version,
        'mutationId': mutationId,
        'committedAt': committedAt.toUtc().toIso8601String(),
        'effects': effects
            .map(
              (effect) => {
                'domain': effect.domain.name,
                'operation': effect.operation.name,
                if (effect.date != null) 'date': effect.date,
                if (effect.entityId != null) 'entityId': effect.entityId,
                if (effect.revision != null) 'revision': effect.revision,
                if (effect.snapshot != null) 'snapshot': effect.snapshot,
              },
            )
            .toList(growable: false),
      };
}

/// Locally scoped repository event. The scope is never accepted from an agent
/// payload; it is captured from the active authenticated cache owner.
class NutritionDataChange {
  const NutritionDataChange({
    required this.userId,
    required this.mutation,
  });

  final String userId;
  final ConfirmedNutritionMutation mutation;
  List<NutritionDataEffect> get effects => mutation.effects;
}

NutritionDataEffect? _parseEffect(Object? value) {
  if (value is! Map) return null;
  final json = _objectMap(value);
  final domain = switch (json['domain']) {
    'daily_summary' => NutritionDataDomain.dailySummary,
    'daily_goals' => NutritionDataDomain.dailyGoals,
    'meal_templates' => NutritionDataDomain.mealTemplates,
    'usual_foods' => NutritionDataDomain.usualFoods,
    _ => null,
  };
  final operation = switch (json['operation']) {
    'replace' => NutritionDataOperation.replace,
    'upsert' => NutritionDataOperation.upsert,
    'delete' => NutritionDataOperation.delete,
    'invalidate' => NutritionDataOperation.invalidate,
    _ => null,
  };
  if (domain == null || operation == null) return null;
  final date = json['date'];
  final entityId = json['entityId'];
  final snapshot = json['snapshot'];
  if (date != null && (date is! String || !_datePattern.hasMatch(date))) {
    return null;
  }
  if (entityId != null &&
      (entityId is! String || !_uuidPattern.hasMatch(entityId))) {
    return null;
  }
  if (json['revision'] != null && json['revision'] is! String) return null;
  if (snapshot != null && snapshot is! Map) return null;
  if (domain == NutritionDataDomain.dailySummary && date is! String) {
    return null;
  }
  if ((domain == NutritionDataDomain.mealTemplates ||
          domain == NutritionDataDomain.usualFoods) &&
      operation != NutritionDataOperation.invalidate &&
      entityId is! String) {
    return null;
  }
  return NutritionDataEffect(
    domain: domain,
    operation: operation,
    date: date as String?,
    entityId: entityId as String?,
    revision: json['revision'] as String?,
    snapshot: snapshot == null ? null : _objectMap(snapshot),
  );
}

final _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

Map<String, Object?> _objectMap(Object value) =>
    Map<String, Object?>.from(value as Map);
