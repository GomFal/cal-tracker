import 'dart:async';
import 'dart:convert';

import 'package:cal_tracker_mobile/app/theme.dart';
import 'package:cal_tracker_mobile/data/repositories/nutrition_repository.dart';
import 'package:cal_tracker_mobile/data/services/audio_recorder_service.dart';
import 'package:cal_tracker_mobile/data/services/nutrition_cache_store.dart';
import 'package:cal_tracker_mobile/domain/models/nutrition_models.dart';
import 'package:cal_tracker_mobile/generated/api/cal_tracker_api.dart';
import 'package:cal_tracker_mobile/l10n/generated/app_localizations.dart';
import 'package:cal_tracker_mobile/ui/features/agent_chat/view_models/agent_chat_view_model.dart';
import 'package:cal_tracker_mobile/ui/features/agent_chat/views/agent_chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class _Repository extends Mock implements NutritionRepository {}

class _Recorder extends Mock implements AudioRecorderService {}

class _ApiClient extends Mock implements CalTrackerApiClient {}

class _CacheStore extends Mock implements NutritionCacheStore {}

const _nutrition = NutritionSnapshot(
  calories: 100,
  proteinGrams: 2,
  carbsGrams: 20,
  fatGrams: 1,
);

DailySummary _summary({List<Meal> meals = const []}) => DailySummary(
      date: '2026-01-01',
      consumed: const NutritionSnapshot(
        calories: 0,
        proteinGrams: 0,
        carbsGrams: 0,
        fatGrams: 0,
      ),
      target: const NutritionSnapshot(
        calories: 2000,
        proteinGrams: 100,
        carbsGrams: 250,
        fatGrams: 70,
      ),
      remaining: const NutritionSnapshot(
        calories: 2000,
        proteinGrams: 100,
        carbsGrams: 250,
        fatGrams: 70,
      ),
      hydrationGoalLiters: 2,
      waterConsumedLiters: 0,
      calorieTargetConfigured: true,
      calorieTargetSource: 'manual',
      meals: meals,
    );

AgentRunResult _committedResult(Meal meal,
        {String proposalId = 'proposal-id'}) =>
    AgentRunResult(
      kind: 'meal_committed',
      message: 'Meal logged.',
      sourceProposalId: proposalId,
      meal: meal,
    );

Map<String, Object?> _confirmedMutationJson({
  required String mutationId,
  required DailySummary summary,
}) =>
    {
      'version': 1,
      'mutationId': mutationId,
      'committedAt': '2026-01-01T12:00:00.000Z',
      'effects': [
        {
          'domain': 'daily_summary',
          'operation': 'replace',
          'date': summary.date,
          'revision': '2026-01-01T12:00:00.000Z',
          'snapshot': summary.toJson(),
        },
      ],
    };

void main() {
  setUpAll(() {
    registerFallbackValue(_summary());
  });

  const action = AgentChatProposalAction(
    type: AgentChatProposalActionType.commit,
    conversationId: 'conversation-id',
    entryId: 'entry-id',
    sourceToolCallId: 'tool-call-id',
    proposalId: 'proposal-id',
  );

  test('direct save is deduplicated and never streams an agent message',
      () async {
    final repository = _Repository();
    final recorder = _Recorder();
    final meal = Meal(
      id: 'meal-id',
      title: 'Bread',
      occurredAt: DateTime.utc(2026, 1, 1),
      nutrition: _nutrition,
      items: const [],
    );
    when(() => repository.commitAgentChatProposal(
          conversationId: action.conversationId,
          proposalId: action.proposalId,
          sourceToolCallId: action.sourceToolCallId,
          clientMutationId: any(named: 'clientMutationId'),
        )).thenAnswer((_) async => AgentChatProposalCommitResult(
          clientMutationId: '11111111-1111-4111-8111-111111111111',
          reused: false,
          result: _committedResult(meal),
          conversationMessage: AgentConversationMessage(
            id: 'message-id',
            conversationId: action.conversationId,
            role: 'tool',
            content: '{}',
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        ));
    final viewModel = AgentChatViewModel(
      nutritionRepository: repository,
      audioRecorderService: recorder,
    );

    await Future.wait([
      viewModel.commitProposalAction(action),
      viewModel.commitProposalAction(action),
    ]);

    expect(
      viewModel.proposalActionState(action.proposalId),
      AgentChatProposalActionState.succeeded,
    );
    verify(() => repository.commitAgentChatProposal(
          conversationId: action.conversationId,
          proposalId: action.proposalId,
          sourceToolCallId: action.sourceToolCallId,
          clientMutationId: any(named: 'clientMutationId'),
        )).called(1);
    verifyNever(() => repository.streamAgentChat(
          any(),
          conversationId: any(named: 'conversationId'),
          activeProposalId: any(named: 'activeProposalId'),
        ));
  });

  testWidgets(
      'proposal actions save directly and correction only focuses input',
      (tester) async {
    final repository = _Repository();
    final meal = Meal(
      id: 'meal-id',
      title: 'Bread',
      occurredAt: DateTime.utc(2026, 1, 1),
      nutrition: _nutrition,
      items: const [],
    );
    const proposal = MealProposal(
      id: 'proposal-id',
      title: 'Bread',
      confidence: 1,
      requiresConfirmation: true,
      trustedAutoCommitEligible: false,
      nutrition: _nutrition,
      items: [],
    );
    const toolCall = AgentToolCallFeedback(
      id: 'tool-call-id',
      actionId: 'propose_meal_log',
      label: 'Create proposal',
      summary: 'Creating a meal proposal',
    );
    when(() => repository.listAgentConversations())
        .thenAnswer((_) async => const []);
    when(() => repository.streamAgentChat(
          'log bread',
          conversationId: null,
          activeProposalId: null,
        )).thenAnswer(
      (_) => Stream.fromIterable([
        const AgentChatStreamEvent(
          type: 'conversation_started',
          conversationId: 'conversation-id',
        ),
        const AgentChatStreamEvent(
          type: 'tool_call_completed',
          conversationId: 'conversation-id',
          toolCall: toolCall,
          result: AgentRunResult(
            kind: 'proposal',
            message: 'Review this meal.',
            proposal: proposal,
          ),
        ),
        const AgentChatStreamEvent(
          type: 'done',
          conversationId: 'conversation-id',
        ),
      ]),
    );
    when(() => repository.commitAgentChatProposal(
          conversationId: 'conversation-id',
          proposalId: proposal.id,
          sourceToolCallId: toolCall.id,
          clientMutationId: any(named: 'clientMutationId'),
        )).thenAnswer(
      (_) async => AgentChatProposalCommitResult(
        clientMutationId: '11111111-1111-4111-8111-111111111111',
        reused: false,
        result: _committedResult(meal),
        conversationMessage: AgentConversationMessage(
          id: 'message-id',
          conversationId: 'conversation-id',
          role: 'tool',
          content: '{}',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      ),
    );
    final viewModel = AgentChatViewModel(
      nutritionRepository: repository,
      audioRecorderService: _Recorder(),
    );
    await viewModel.sendText('log bread');
    clearInteractions(repository);

    await tester.pumpWidget(
      ChangeNotifierProvider<AgentChatViewModel>.value(
        value: viewModel,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildLightTheme(),
          home: const AgentChatScreen(),
        ),
      ),
    );
    await tester.pump();

    final save = find.byKey(
      const ValueKey('agent_chat_proposal_save_button_proposal-id'),
    );
    final correct = find.byKey(
      const ValueKey('agent_chat_proposal_correct_button_proposal-id'),
    );
    await tester.ensureVisible(correct);
    await tester.tap(correct.hitTestable());
    await tester.pump();
    expect(
      find.text('Tell us what to change in this meal proposal'),
      findsOneWidget,
    );
    verifyNever(() => repository.commitAgentChatProposal(
          conversationId: any(named: 'conversationId'),
          proposalId: any(named: 'proposalId'),
          sourceToolCallId: any(named: 'sourceToolCallId'),
          clientMutationId: any(named: 'clientMutationId'),
        ));
    verifyNever(() => repository.streamAgentChat(
          any(),
          conversationId: any(named: 'conversationId'),
          activeProposalId: any(named: 'activeProposalId'),
        ));

    await tester.ensureVisible(save);
    await tester.tap(save.hitTestable());
    await tester.pumpAndSettle();

    verify(() => repository.commitAgentChatProposal(
          conversationId: 'conversation-id',
          proposalId: proposal.id,
          sourceToolCallId: toolCall.id,
          clientMutationId: any(named: 'clientMutationId'),
        )).called(1);
    verifyNever(() => repository.streamAgentChat(
          any(),
          conversationId: any(named: 'conversationId'),
          activeProposalId: any(named: 'activeProposalId'),
        ));
    expect(find.text('Meal saved.'), findsOneWidget);
  });

  test('retry keeps its client mutation id after a failed direct save',
      () async {
    final repository = _Repository();
    final mutationIds = <String>[];
    var attempts = 0;
    final meal = Meal(
      id: 'meal-id',
      title: 'Bread',
      occurredAt: DateTime.utc(2026, 1, 1),
      nutrition: _nutrition,
      items: const [],
    );
    when(() => repository.commitAgentChatProposal(
          conversationId: action.conversationId,
          proposalId: action.proposalId,
          sourceToolCallId: action.sourceToolCallId,
          clientMutationId: any(named: 'clientMutationId'),
        )).thenAnswer((invocation) async {
      mutationIds.add(
        invocation.namedArguments[#clientMutationId] as String,
      );
      if (attempts++ == 0) throw Exception('offline');
      return AgentChatProposalCommitResult(
        clientMutationId: mutationIds.first,
        reused: false,
        result: _committedResult(meal),
        conversationMessage: AgentConversationMessage(
          id: 'message-id',
          conversationId: action.conversationId,
          role: 'tool',
          content: '{}',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );
    });
    final viewModel = AgentChatViewModel(
      nutritionRepository: repository,
      audioRecorderService: _Recorder(),
    );

    await viewModel.commitProposalAction(action);
    expect(
      viewModel.proposalActionState(action.proposalId),
      AgentChatProposalActionState.failed,
    );
    await viewModel.commitProposalAction(action);

    expect(
      viewModel.proposalActionState(action.proposalId),
      AgentChatProposalActionState.succeeded,
    );
    expect(mutationIds.toSet(), hasLength(1));
  });

  test('repository writes the authoritative direct-commit meal through cache',
      () async {
    final apiClient = _ApiClient();
    final cacheStore = _CacheStore();
    final meal = Meal(
      id: 'meal-id',
      title: 'Bread',
      occurredAt: DateTime.utc(2026, 1, 1),
      nutrition: _nutrition,
      items: const [],
    );
    final conversationMessage = AgentConversationMessage(
      id: 'message-id',
      conversationId: action.conversationId,
      role: 'tool',
      content: '{}',
      createdAt: DateTime.utc(2026, 1, 1),
    );
    when(() => cacheStore.readDailySummary('2026-01-01')).thenAnswer(
      (_) async => CachedNutritionValue(
        value: _summary(),
        cachedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    when(() => cacheStore.writeDailySummary(any())).thenAnswer((_) async {});
    final authoritativeSummary = _summary(meals: [meal]);
    when(() => apiClient.commitAgentChatProposal(
          conversationId: action.conversationId,
          proposalId: action.proposalId,
          sourceToolCallId: action.sourceToolCallId,
          clientMutationId: '11111111-1111-4111-8111-111111111111',
        )).thenAnswer(
      (_) async => {
        'actionId': 'commit_meal',
        'clientMutationId': '11111111-1111-4111-8111-111111111111',
        'reused': false,
        'result': {
          'kind': 'meal_committed',
          'sourceProposalId': action.proposalId,
          'meal': meal.toJson(),
          'message': 'Meal logged.',
          'confirmedMutation': _confirmedMutationJson(
            mutationId: '11111111-1111-4111-8111-111111111111',
            summary: authoritativeSummary,
          ),
        },
        'conversationMessage': conversationMessage.toJson(),
      },
    );
    final repository = NutritionRepository(
      apiClient: apiClient,
      cacheStore: cacheStore,
    )..activateCacheForUser('user-a');
    final changes = <Object>[];
    final subscription = repository.dataChanges.listen(changes.add);
    addTearDown(() async {
      await subscription.cancel();
      await repository.dispose();
    });

    final result = await repository.commitAgentChatProposal(
      conversationId: action.conversationId,
      proposalId: action.proposalId,
      sourceToolCallId: action.sourceToolCallId,
      clientMutationId: '11111111-1111-4111-8111-111111111111',
    );
    final retry = await repository.commitAgentChatProposal(
      conversationId: action.conversationId,
      proposalId: action.proposalId,
      sourceToolCallId: action.sourceToolCallId,
      clientMutationId: '11111111-1111-4111-8111-111111111111',
    );
    await Future<void>.delayed(Duration.zero);

    expect(result.meal.id, meal.id);
    expect(retry.result.confirmedMutation?.mutationId,
        result.result.confirmedMutation?.mutationId);
    expect(changes, hasLength(1));
    final written = verify(
      () => cacheStore.writeDailySummary(captureAny()),
    ).captured.single as DailySummary;
    expect(written.meals.map((item) => item.id), [meal.id]);
    verify(() => apiClient.commitAgentChatProposal(
          conversationId: action.conversationId,
          proposalId: action.proposalId,
          sourceToolCallId: action.sourceToolCallId,
          clientMutationId: '11111111-1111-4111-8111-111111111111',
        )).called(2);
  });

  test('repository failure leaves cached summaries untouched and retryable',
      () async {
    final apiClient = _ApiClient();
    final cacheStore = _CacheStore();
    final meal = Meal(
      id: 'meal-id',
      title: 'Bread',
      occurredAt: DateTime.utc(2026, 1, 1),
      nutrition: _nutrition,
      items: const [],
    );
    var attempts = 0;
    when(() => cacheStore.readDailySummary('2026-01-01'))
        .thenAnswer((_) async => null);
    when(() => cacheStore.writeDailySummary(any())).thenAnswer((_) async {});
    final authoritativeSummary = _summary(meals: [meal]);
    when(() => apiClient.commitAgentChatProposal(
          conversationId: action.conversationId,
          proposalId: action.proposalId,
          sourceToolCallId: action.sourceToolCallId,
          clientMutationId: '11111111-1111-4111-8111-111111111111',
        )).thenAnswer((_) async {
      if (attempts++ == 0) throw Exception('offline');
      return {
        'actionId': 'commit_meal',
        'clientMutationId': '11111111-1111-4111-8111-111111111111',
        'reused': true,
        'result': {
          'kind': 'meal_committed',
          'sourceProposalId': action.proposalId,
          'meal': meal.toJson(),
          'message': 'Meal logged.',
          'confirmedMutation': _confirmedMutationJson(
            mutationId: '11111111-1111-4111-8111-111111111111',
            summary: authoritativeSummary,
          ),
        },
        'conversationMessage': AgentConversationMessage(
          id: 'message-id',
          conversationId: action.conversationId,
          role: 'tool',
          content: '{}',
          createdAt: DateTime.utc(2026, 1, 1),
        ).toJson(),
      };
    });
    final repository = NutritionRepository(
      apiClient: apiClient,
      cacheStore: cacheStore,
    )..activateCacheForUser('user-a');

    await expectLater(
      repository.commitAgentChatProposal(
        conversationId: action.conversationId,
        proposalId: action.proposalId,
        sourceToolCallId: action.sourceToolCallId,
        clientMutationId: '11111111-1111-4111-8111-111111111111',
      ),
      throwsException,
    );
    verifyNever(() => cacheStore.writeDailySummary(any()));
    final retry = await repository.commitAgentChatProposal(
      conversationId: action.conversationId,
      proposalId: action.proposalId,
      sourceToolCallId: action.sourceToolCallId,
      clientMutationId: '11111111-1111-4111-8111-111111111111',
    );

    expect(retry.meal.id, meal.id);
    verify(() => apiClient.commitAgentChatProposal(
          conversationId: action.conversationId,
          proposalId: action.proposalId,
          sourceToolCallId: action.sourceToolCallId,
          clientMutationId: '11111111-1111-4111-8111-111111111111',
        )).called(2);
    final written = verify(
      () => cacheStore.writeDailySummary(captureAny()),
    ).captured.single as DailySummary;
    expect(written.meals.map((item) => item.id), [meal.id]);
  });

  test('late direct-commit response is ignored after an account switch',
      () async {
    final apiClient = _ApiClient();
    final cacheStore = _CacheStore();
    final response = Completer<Map<String, Object?>>();
    final meal = Meal(
      id: 'late-meal',
      title: 'Bread',
      occurredAt: DateTime.utc(2026, 1, 1),
      nutrition: _nutrition,
      items: const [],
    );
    when(() => cacheStore.writeDailySummary(any())).thenAnswer((_) async {});
    when(() => apiClient.commitAgentChatProposal(
          conversationId: action.conversationId,
          proposalId: action.proposalId,
          sourceToolCallId: action.sourceToolCallId,
          clientMutationId: '11111111-1111-4111-8111-111111111111',
        )).thenAnswer((_) => response.future);
    final repository = NutritionRepository(
      apiClient: apiClient,
      cacheStore: cacheStore,
    )..activateCacheForUser('user-a');
    final changes = <Object>[];
    final subscription = repository.dataChanges.listen(changes.add);
    addTearDown(() async {
      await subscription.cancel();
      await repository.dispose();
    });

    final pending = repository.commitAgentChatProposal(
      conversationId: action.conversationId,
      proposalId: action.proposalId,
      sourceToolCallId: action.sourceToolCallId,
      clientMutationId: '11111111-1111-4111-8111-111111111111',
    );
    repository.activateCacheForUser('user-b');
    response.complete({
      'actionId': 'commit_meal',
      'clientMutationId': '11111111-1111-4111-8111-111111111111',
      'reused': false,
      'result': {
        'kind': 'meal_committed',
        'sourceProposalId': action.proposalId,
        'meal': meal.toJson(),
        'message': 'Meal logged.',
        'confirmedMutation': _confirmedMutationJson(
          mutationId: '11111111-1111-4111-8111-111111111111',
          summary: _summary(meals: [meal]),
        ),
      },
      'conversationMessage': AgentConversationMessage(
        id: 'late-message',
        conversationId: action.conversationId,
        role: 'tool',
        content: '{}',
        createdAt: DateTime.utc(2026, 1, 1),
      ).toJson(),
    });

    await expectLater(pending, throwsA(isA<StaleNutritionResponseException>()));
    verifyNever(() => cacheStore.writeDailySummary(any()));
    expect(changes, isEmpty);
  });

  test('rehydration marks a committed proposal as saved and inactive',
      () async {
    final repository = _Repository();
    final recorder = _Recorder();
    final createdAt = DateTime.utc(2026, 1, 1);
    final detail = AgentConversationDetail(
      conversation: AgentConversationSummary(
        id: action.conversationId,
        title: 'Bread',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
      messages: [
        AgentConversationMessage(
          id: 'proposal-message',
          conversationId: action.conversationId,
          role: 'tool',
          content: jsonEncode({
            'actionId': 'propose_meal_log',
            'result': {
              'kind': 'proposal',
              'message': 'Review this meal.',
              'proposal': {
                'id': action.proposalId,
                'title': 'Bread',
                'confidence': 1.0,
                'requiresConfirmation': true,
                'trustedAutoCommitEligible': false,
                'nutrition': {
                  'calories': 100,
                  'proteinGrams': 2.0,
                  'carbsGrams': 20.0,
                  'fatGrams': 1.0,
                },
                'items': <Object?>[],
              },
            },
          }),
          toolCallId: action.sourceToolCallId,
          createdAt: createdAt,
        ),
        AgentConversationMessage(
          id: 'commit-message',
          conversationId: action.conversationId,
          role: 'tool',
          content: jsonEncode({
            'actionId': 'commit_meal',
            'result': {
              'kind': 'meal_committed',
              'message': 'Meal logged.',
              'sourceProposalId': action.proposalId,
            },
          }),
          createdAt: createdAt.add(const Duration(seconds: 1)),
        ),
      ],
    );
    when(() => repository.getAgentConversation(action.conversationId))
        .thenAnswer((_) async => detail);
    final viewModel = AgentChatViewModel(
      nutritionRepository: repository,
      audioRecorderService: recorder,
    );

    await viewModel.loadConversation(action.conversationId);

    expect(viewModel.isProposalCommitted(action.proposalId), isTrue);
    expect(
      viewModel.proposalActionState(action.proposalId),
      AgentChatProposalActionState.succeeded,
    );
    expect(viewModel.activeProposalId, isNull);
  });

  test('correct only selects the structured proposal target', () {
    final repository = _Repository();
    final viewModel = AgentChatViewModel(
      nutritionRepository: repository,
      audioRecorderService: _Recorder(),
    );
    viewModel.beginProposalCorrection(const AgentChatProposalAction(
      type: AgentChatProposalActionType.correct,
      conversationId: 'conversation-id',
      entryId: 'entry-id',
      sourceToolCallId: 'tool-call-id',
      proposalId: 'proposal-id',
    ));
    expect(viewModel.activeProposalId, 'proposal-id');
    verifyNever(() => repository.streamAgentChat(
          any(),
          conversationId: any(named: 'conversationId'),
          activeProposalId: any(named: 'activeProposalId'),
        ));
  });
}
