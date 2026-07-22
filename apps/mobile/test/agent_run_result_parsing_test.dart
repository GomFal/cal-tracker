import 'package:cal_tracker_mobile/data/repositories/nutrition_repository.dart';
import 'package:cal_tracker_mobile/domain/models/nutrition_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('agentRunResultFromJson history-capable results', () {
    test('parses meal_details with complete meal items', () {
      final result = agentRunResultFromJson({
        'kind': 'meal_details',
        'message': 'Here are the meal ingredients and nutrition.',
        'meal': _mealJson(),
      });

      expect(result.kind, 'meal_details');
      expect(result.message, 'Here are the meal ingredients and nutrition.');
      expect(result.meal?.id, '11111111-1111-4111-8111-111111111111');
      expect(result.meal?.title, 'Detailed breakfast');
      expect(result.meal?.occurredAt, DateTime.utc(2026, 7, 22, 8, 30));
      expect(result.meal?.mealLabel?.type, 'breakfast');
      expect(result.meal?.nutrition.toJson(), _nutritionJson());
      _expectCompleteItem(result.meal!.items.single);
    });

    test('parses template_details with aliases, nutrition, and complete items',
        () {
      final result = agentRunResultFromJson({
        'kind': 'template_details',
        'message': 'Here are the usual meal ingredients and nutrition.',
        'template': {
          'id': '22222222-2222-4222-8222-222222222222',
          'title': 'Usual breakfast',
          'trustedAutoCommitEnabled': true,
          'nutrition': _nutritionJson(),
          'items': [_completeItemJson()],
          'aliases': ['weekday breakfast', 'desayuno habitual'],
        },
      });

      expect(result.kind, 'template_details');
      expect(result.template?.id, '22222222-2222-4222-8222-222222222222');
      expect(result.template?.title, 'Usual breakfast');
      expect(result.template?.trustedAutoCommitEnabled, isTrue);
      expect(
        result.template?.aliases,
        ['weekday breakfast', 'desayuno habitual'],
      );
      expect(result.template?.nutrition.toJson(), _nutritionJson());
      _expectCompleteItem(result.template!.items.single);
    });

    test('parses meal_correction_preview and requires confirmation', () {
      final result = agentRunResultFromJson({
        'kind': 'meal_correction_preview',
        'message': 'Review this meal correction before confirming.',
        'meal': _mealJson(title: 'Corrected breakfast'),
        'requiresConfirmation': true,
      });

      expect(result.kind, 'meal_correction_preview');
      expect(result.requiresConfirmation, isTrue);
      expect(result.meal?.title, 'Corrected breakfast');
      expect(result.meal?.nutrition.toJson(), _nutritionJson());
      _expectCompleteItem(result.meal!.items.single);
    });

    test('parses hydration_updated summary with exact 0.001 L precision', () {
      final result = agentRunResultFromJson({
        'kind': 'hydration_updated',
        'message': 'Hydration updated.',
        'summary': {
          'date': '2026-07-22',
          'consumed': {
            'calories': 620,
            'proteinGrams': 41.2,
            'carbsGrams': 72.4,
            'fatGrams': 18.6,
          },
          'target': {
            'calories': 2100,
            'proteinGrams': 150,
            'carbsGrams': 230,
            'fatGrams': 70,
          },
          'remaining': {
            'calories': 1480,
            'proteinGrams': 108.8,
            'carbsGrams': 157.6,
            'fatGrams': 51.4,
          },
          'hydrationGoalLiters': 2,
          'waterConsumedLiters': 0.001,
          'calorieTargetConfigured': true,
          'calorieTargetSource': 'manual',
          'meals': <Object?>[],
        },
      });

      expect(result.kind, 'hydration_updated');
      expect(result.summary?.date, '2026-07-22');
      expect(result.summary?.consumed.toJson(), {
        'calories': 620,
        'proteinGrams': 41.2,
        'carbsGrams': 72.4,
        'fatGrams': 18.6,
      });
      expect(result.summary?.target.toJson(), {
        'calories': 2100,
        'proteinGrams': 150.0,
        'carbsGrams': 230.0,
        'fatGrams': 70.0,
      });
      expect(result.summary?.remaining.toJson(), {
        'calories': 1480,
        'proteinGrams': 108.8,
        'carbsGrams': 157.6,
        'fatGrams': 51.4,
      });
      expect(result.summary?.hydrationGoalLiters, 2.0);
      expect(result.summary?.waterConsumedLiters, 0.001);
      expect(result.summary?.meals, isEmpty);
    });
  });
}

Map<String, Object?> _mealJson({String title = 'Detailed breakfast'}) => {
      'id': '11111111-1111-4111-8111-111111111111',
      'title': title,
      'occurredAt': '2026-07-22T08:30:00.000Z',
      'mealLabel': {'type': 'breakfast', 'label': 'Breakfast'},
      'nutrition': _nutritionJson(),
      'items': [_completeItemJson()],
    };

Map<String, Object?> _nutritionJson() => {
      'calories': 410,
      'proteinGrams': 24.5,
      'carbsGrams': 52.25,
      'fatGrams': 11.75,
    };

Map<String, Object?> _completeItemJson() => {
      'id': '33333333-3333-4333-8333-333333333333',
      'name': 'Greek yogurt with oats',
      'quantity': 275,
      'unit': 'g',
      'calories': 410,
      'proteinGrams': 24.5,
      'carbsGrams': 52.25,
      'fatGrams': 11.75,
      'source': 'database',
      'originalText': 'yogur griego con avena',
      'canonicalName': 'greek yogurt with oats',
      'language': 'es',
      'externalSource': 'usda',
      'externalId': 'food-333',
      'sourceUrl': 'https://example.com/foods/333',
      'license': 'CC0',
      'confidence': 0.987,
      'needsReview': false,
      'resolvedGrams': 275,
      'portionDescription': 'one bowl',
      'displayDetails': ['275 g serving', 'USDA reference'],
    };

void _expectCompleteItem(MealItem item) {
  expect(item.toJson(), {
    'name': 'Greek yogurt with oats',
    'quantity': 275.0,
    'unit': 'g',
    'calories': 410,
    'proteinGrams': 24.5,
    'carbsGrams': 52.25,
    'fatGrams': 11.75,
    'source': 'database',
    'originalText': 'yogur griego con avena',
    'canonicalName': 'greek yogurt with oats',
    'language': 'es',
    'externalSource': 'usda',
    'externalId': 'food-333',
    'sourceUrl': 'https://example.com/foods/333',
    'license': 'CC0',
    'confidence': 0.987,
    'needsReview': false,
    'resolvedGrams': 275.0,
    'portionDescription': 'one bowl',
    'displayDetails': ['275 g serving', 'USDA reference'],
  });
}
