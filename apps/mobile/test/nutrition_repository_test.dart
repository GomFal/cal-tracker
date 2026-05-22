import 'dart:io';

import 'package:cal_tracker_mobile/data/repositories/nutrition_repository.dart';
import 'package:cal_tracker_mobile/domain/models/macro_distribution.dart';
import 'package:cal_tracker_mobile/generated/api/cal_tracker_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockCalTrackerApiClient extends Mock implements CalTrackerApiClient {}

class FakeFile extends Fake implements File {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeFile());
  });

  group('NutritionRepository', () {
    test('parses all 10 food candidates from agent options', () async {
      final apiClient = MockCalTrackerApiClient();
      final repository = NutritionRepository(apiClient: apiClient);
      when(() => apiClient.runAgent('100 gramos de queso')).thenAnswer(
        (_) async => {
          'kind': 'clarification_required',
          'message': 'Choose a food match.',
          'options': [
            {
              'mention': {
                'originalText': 'queso',
                'canonicalName': 'queso',
                'canonicalEnglishName': 'cheese',
                'language': 'es',
                'quantity': 100,
                'unit': 'g',
                'confidence': 0.92,
                'marketProduct': false,
              },
              'candidates': [
                for (var index = 0; index < 10; index++)
                  {
                    'name': 'Cheese candidate ${index + 1}',
                    'quantity': 100,
                    'unit': 'g',
                    'calories': 100 + index,
                    'proteinGrams': 7,
                    'carbsGrams': 1,
                    'fatGrams': 8,
                    'source': 'open_food_facts',
                    'externalSource': 'Open Food Facts',
                    'externalId': 'cheese_${index + 1}',
                    'confidence': 0.9 - (index * 0.02),
                  },
              ],
            },
          ],
        },
      );

      final result = await repository.logText('100 gramos de queso');

      expect(result.candidateGroups, hasLength(1));
      expect(result.candidateGroups!.single.mention.canonicalName, 'queso');
      expect(
        result.candidateGroups!.single.mention.canonicalEnglishName,
        'cheese',
      );
      expect(result.candidateGroups!.single.candidates, hasLength(10));
      expect(
        result.candidateGroups!.single.candidates[9].name,
        'Cheese candidate 10',
      );
    });

    test('parses voice meal run transcript and agent result', () async {
      final apiClient = MockCalTrackerApiClient();
      final repository = NutritionRepository(apiClient: apiClient);
      when(() => apiClient.runVoiceMeal(any(), source: 'flutter')).thenAnswer(
        (_) async => {
          'transcript': '100 grams bread',
          'provider': 'test',
          'model': 'test-model',
          'traceId': 'trace-1',
          'result': {
            'kind': 'proposal',
            'message': 'Meal proposal created.',
            'proposal': {
              'id': 'proposal-1',
              'title': 'Bread',
              'confidence': 0.8,
              'requiresConfirmation': true,
              'trustedAutoCommitEligible': false,
              'nutrition': {
                'calories': 265,
                'proteinGrams': 9,
                'carbsGrams': 49,
                'fatGrams': 3.2,
              },
              'items': [],
            },
          },
        },
      );

      final result = await repository.logAudio(File('/tmp/test.m4a'));

      expect(result.transcript, '100 grams bread');
      expect(result.provider, 'test');
      expect(result.model, 'test-model');
      expect(result.traceId, 'trace-1');
      expect(result.result.kind, 'proposal');
      expect(result.result.proposal?.title, 'Bread');
    });

    test('passes active proposal id to agent and voice meal runs', () async {
      final apiClient = MockCalTrackerApiClient();
      final repository = NutritionRepository(apiClient: apiClient);
      when(
        () => apiClient.runAgent(
          'make the butter 40 grams',
          activeProposalId: 'proposal-1',
        ),
      ).thenAnswer(
        (_) async => {
          'kind': 'proposal',
          'message': 'Meal proposal updated.',
          'proposal': {
            'id': 'proposal-1',
            'title': 'Bread and butter',
            'confidence': 0.8,
            'requiresConfirmation': true,
            'trustedAutoCommitEligible': false,
            'nutrition': {
              'calories': 552,
              'proteinGrams': 9.4,
              'carbsGrams': 49,
              'fatGrams': 35.6,
            },
            'items': [],
          },
        },
      );
      when(
        () => apiClient.runVoiceMeal(
          any(),
          source: 'flutter',
          activeProposalId: 'proposal-1',
        ),
      ).thenAnswer(
        (_) async => {
          'transcript': 'make the butter 40 grams',
          'provider': 'test',
          'model': 'test-model',
          'traceId': 'trace-2',
          'result': {
            'kind': 'proposal',
            'message': 'Meal proposal updated.',
            'proposal': {
              'id': 'proposal-1',
              'title': 'Bread and butter',
              'confidence': 0.8,
              'requiresConfirmation': true,
              'trustedAutoCommitEligible': false,
              'nutrition': {
                'calories': 552,
                'proteinGrams': 9.4,
                'carbsGrams': 49,
                'fatGrams': 35.6,
              },
              'items': [],
            },
          },
        },
      );

      final textResult = await repository.logText(
        'make the butter 40 grams',
        activeProposalId: 'proposal-1',
      );
      final voiceResult = await repository.logAudio(
        File('/tmp/test.m4a'),
        activeProposalId: 'proposal-1',
      );

      expect(textResult.proposal?.id, 'proposal-1');
      expect(voiceResult.result.proposal?.id, 'proposal-1');
      verify(
        () => apiClient.runAgent(
          'make the butter 40 grams',
          activeProposalId: 'proposal-1',
        ),
      ).called(1);
      verify(
        () => apiClient.runVoiceMeal(
          any(),
          source: 'flutter',
          activeProposalId: 'proposal-1',
        ),
      ).called(1);
    });

    test('sends macro preset fields when updating daily goals', () async {
      final apiClient = MockCalTrackerApiClient();
      final repository = NutritionRepository(apiClient: apiClient);
      Map<String, Object?>? capturedMacroFields;
      when(
        () => apiClient.updateDailyGoals(
          date: any(named: 'date'),
          calories: any(named: 'calories'),
          hydrationGoalLiters: any(named: 'hydrationGoalLiters'),
          calorieTargetSource: any(named: 'calorieTargetSource'),
          macroFields: any(named: 'macroFields'),
        ),
      ).thenAnswer((invocation) async {
        capturedMacroFields =
            invocation.namedArguments[#macroFields] as Map<String, Object?>?;
        return {
          'goals': {
            'date': '2026-05-18',
            'target': {
              'calories': 2000,
              'proteinGrams': 175,
              'carbsGrams': 175,
              'fatGrams': 67,
            },
            'hydrationGoalLiters': 2.5,
            'calorieTargetConfigured': true,
            'calorieTargetSource': 'calculator',
            'macroMode': 'percentage',
            'macroSource': 'preset',
            'macroPreset': 'high_protein',
            'proteinPct': 35,
            'carbsPct': 35,
            'fatPct': 30,
          },
        };
      });

      final goals = await repository.updateDailyGoals(
        date: '2026-05-18',
        calories: 2000,
        calorieTargetSource: 'calculator',
        macroConfig: MacroDistributionConfig.preset(MacroPreset.highProtein),
        macroCalorieTarget: 2000,
      );

      expect(capturedMacroFields, containsPair('macroMode', 'percentage'));
      expect(capturedMacroFields, containsPair('macroSource', 'preset'));
      expect(capturedMacroFields, containsPair('macroPreset', 'high_protein'));
      expect(capturedMacroFields, containsPair('proteinPct', 35));
      expect(capturedMacroFields, containsPair('macroCalories', 2003));
      expect(goals.macroPreset, MacroPreset.highProtein);
    });

    test('rejects invalid gram macros before calling the API', () async {
      final apiClient = MockCalTrackerApiClient();
      final repository = NutritionRepository(apiClient: apiClient);

      await expectLater(
        repository.updateDailyGoals(
          date: '2026-05-18',
          calories: 2000,
          macroConfig: MacroDistributionConfig.grams(
            proteinGrams: 300,
            carbsGrams: 200,
            fatGrams: 67,
          ),
          macroCalorieTarget: 2000,
        ),
        throwsArgumentError,
      );

      verifyNever(
        () => apiClient.updateDailyGoals(
          date: any(named: 'date'),
          calories: any(named: 'calories'),
          hydrationGoalLiters: any(named: 'hydrationGoalLiters'),
          calorieTargetSource: any(named: 'calorieTargetSource'),
          macroFields: any(named: 'macroFields'),
        ),
      );
    });

    test('updates daily hydration and parses the returned summary', () async {
      final apiClient = MockCalTrackerApiClient();
      final repository = NutritionRepository(apiClient: apiClient);
      when(
        () => apiClient.updateDailyHydration(
          date: '2026-05-18',
          waterConsumedLiters: 1.25,
        ),
      ).thenAnswer(
        (_) async => {
          'summary': {
            'date': '2026-05-18',
            'consumed': {
              'calories': 0,
              'proteinGrams': 0,
              'carbsGrams': 0,
              'fatGrams': 0,
            },
            'target': {
              'calories': 2000,
              'proteinGrams': 0,
              'carbsGrams': 0,
              'fatGrams': 0,
            },
            'remaining': {
              'calories': 2000,
              'proteinGrams': 0,
              'carbsGrams': 0,
              'fatGrams': 0,
            },
            'hydrationGoalLiters': 2.5,
            'waterConsumedLiters': 1.25,
            'calorieTargetConfigured': true,
            'calorieTargetSource': 'manual',
            'meals': [],
          },
        },
      );

      final summary = await repository.updateDailyHydration(
        date: '2026-05-18',
        waterConsumedLiters: 1.25,
      );

      expect(summary.hydrationGoalLiters, 2.5);
      expect(summary.waterConsumedLiters, 1.25);
    });
  });
}
