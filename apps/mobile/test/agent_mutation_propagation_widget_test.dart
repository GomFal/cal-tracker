import 'dart:async';

import 'package:cal_tracker_mobile/app/theme.dart';
import 'package:cal_tracker_mobile/data/repositories/auth_repository.dart';
import 'package:cal_tracker_mobile/data/repositories/nutrition_repository.dart';
import 'package:cal_tracker_mobile/data/services/app_preferences_storage.dart';
import 'package:cal_tracker_mobile/data/services/audio_recorder_service.dart';
import 'package:cal_tracker_mobile/data/services/nutrition_cache_store.dart';
import 'package:cal_tracker_mobile/domain/models/auth_models.dart';
import 'package:cal_tracker_mobile/domain/models/nutrition_models.dart';
import 'package:cal_tracker_mobile/generated/api/cal_tracker_api.dart';
import 'package:cal_tracker_mobile/l10n/generated/app_localizations.dart';
import 'package:cal_tracker_mobile/ui/features/agent_chat/view_models/agent_chat_view_model.dart';
import 'package:cal_tracker_mobile/ui/features/agent_chat/views/agent_chat_screen.dart';
import 'package:cal_tracker_mobile/ui/features/auth/view_models/auth_view_model.dart';
import 'package:cal_tracker_mobile/ui/features/dashboard/view_models/dashboard_view_model.dart';
import 'package:cal_tracker_mobile/ui/features/dashboard/views/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class _MockApiClient extends Mock implements CalTrackerApiClient {}

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockAudioRecorderService extends Mock implements AudioRecorderService {}

void main() {
  testWidgets(
    'a committed chat tool updates the preserved Dashboard without a refresh',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final chatMeal = _meal('chat-meal', 'Chat meal');
      final updatedSummary = _summary(
        harness.date,
        meals: [chatMeal],
        calories: chatMeal.nutrition.calories,
      );
      when(
        () => harness.apiClient.getDailySummary(date: any(named: 'date')),
      ).thenAnswer((_) async => {
            'output': {'summary': harness.initial.toJson()}
          });
      when(
        () => harness.apiClient.streamAgentChat(
          any(),
          conversationId: any(named: 'conversationId'),
          activeProposalId: any(named: 'activeProposalId'),
        ),
      ).thenAnswer(
        (_) => Stream.fromIterable([
          const {
            'type': 'conversation_started',
            'conversationId': '00000000-0000-4000-8000-000000000001',
          },
          const {
            'type': 'tool_call_started',
            'conversationId': '00000000-0000-4000-8000-000000000001',
            'toolCall': {
              'id': 'chat-commit',
              'actionId': 'commit_meal',
              'label': 'Commit meal',
              'summary': 'Saving meal',
            },
          },
          {
            'type': 'tool_call_completed',
            'conversationId': '00000000-0000-4000-8000-000000000001',
            'toolCall': const {
              'id': 'chat-commit',
              'actionId': 'commit_meal',
              'label': 'Commit meal',
              'summary': 'Saving meal',
            },
            'result': {
              'kind': 'meal_committed',
              'message': 'Meal logged.',
              'meal': chatMeal.toJson(),
              'confirmedMutation': _mutationJson(
                id: '00000000-0000-4000-8000-000000000002',
                summary: updatedSummary,
              ),
            },
          },
          const {
            'type': 'done',
            'conversationId': '00000000-0000-4000-8000-000000000001',
          },
        ]),
      );

      await harness.pumpDashboard(tester);
      final dashboard = harness.dashboard;
      final navigator = harness.navigator.currentState!;
      navigator.push(MaterialPageRoute<void>(
        builder: (_) => const AgentChatScreen(),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('agent_chat_message_field')),
        'log this meal',
      );
      await tester.tap(
        find.byKey(const ValueKey('agent_chat_send_button')).hitTestable(),
      );
      await tester.pumpAndSettle();
      expect(find.text('Commit meal'), findsOneWidget);

      navigator.pop();
      await tester.pumpAndSettle();

      expect(identical(harness.dashboard, dashboard), isTrue);
      expect(find.byKey(const ValueKey('dashboard_meal_row_chat-meal')),
          findsOneWidget);
      expect(find.text('Chat meal'), findsOneWidget);
      verify(
        () => harness.apiClient.getDailySummary(date: any(named: 'date')),
      ).called(1);
    },
  );

  testWidgets(
    'a direct commit result updates Dashboard through the same repository bus',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final directMeal = _meal('direct-meal', 'Direct meal');
      final updatedSummary = _summary(
        harness.date,
        meals: [directMeal],
        calories: directMeal.nutrition.calories,
      );
      when(
        () => harness.apiClient.getDailySummary(date: any(named: 'date')),
      ).thenAnswer((_) async => {
            'output': {'summary': harness.initial.toJson()}
          });
      when(
        () => harness.apiClient.commitAgentChatProposal(
          conversationId: 'conversation-1',
          proposalId: 'proposal-1',
          sourceToolCallId: 'proposal-call-1',
          clientMutationId: '00000000-0000-4000-8000-000000000003',
        ),
      ).thenAnswer(
        (_) async => {
          'actionId': 'commit_meal',
          'clientMutationId': '00000000-0000-4000-8000-000000000003',
          'reused': false,
          'result': {
            'kind': 'meal_committed',
            'sourceProposalId': 'proposal-1',
            'meal': directMeal.toJson(),
            'message': 'Meal logged.',
            'confirmedMutation': _mutationJson(
              id: '00000000-0000-4000-8000-000000000003',
              summary: updatedSummary,
            ),
          },
          'conversationMessage': {
            'id': 'commit-message-1',
            'conversationId': 'conversation-1',
            'role': 'tool',
            'content': '{}',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        },
      );

      await harness.pumpDashboard(tester);
      await harness.repository.commitAgentChatProposal(
        conversationId: 'conversation-1',
        proposalId: 'proposal-1',
        sourceToolCallId: 'proposal-call-1',
        clientMutationId: '00000000-0000-4000-8000-000000000003',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('dashboard_meal_row_direct-meal')),
          findsOneWidget);
      expect(find.text('Direct meal'), findsOneWidget);
      verify(
        () => harness.apiClient.getDailySummary(date: any(named: 'date')),
      ).called(1);
    },
  );

  testWidgets(
    'a granular meal correction updates the preserved Dashboard immediately',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final original = _meal(
        '00000000-0000-4000-8000-000000000010',
        'Original meal',
      );
      final corrected = _meal(
        '00000000-0000-4000-8000-000000000010',
        'Corrected meal',
      );
      final initial = _summary(
        harness.date,
        meals: [original],
        calories: original.nutrition.calories,
      );
      await harness.repository.putCachedDailySummary(initial);
      when(
        () => harness.apiClient.getDailySummary(date: any(named: 'date')),
      ).thenAnswer((_) async => {
            'output': {'summary': initial.toJson()}
          });
      when(
        () => harness.apiClient.commitAgentChatMealCorrection(
          conversationId: 'conversation-1',
          mealId: original.id,
          sourceToolCallId: 'correction-call-1',
          clientMutationId: '00000000-0000-4000-8000-000000000004',
        ),
      ).thenAnswer(
        (_) async => {
          'actionId': 'correct_meal',
          'clientMutationId': '00000000-0000-4000-8000-000000000004',
          'reused': false,
          'result': {
            'kind': 'meal_corrected',
            'meal': corrected.toJson(),
            'message': 'Meal corrected.',
            'confirmedMutation': _mealMutationJson(
              id: '00000000-0000-4000-8000-000000000004',
              date: harness.date,
              meal: corrected,
            ),
          },
          'conversationMessage': {
            'id': 'correction-message-1',
            'conversationId': 'conversation-1',
            'role': 'tool',
            'content': '{}',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        },
      );

      await harness.pumpDashboard(tester);
      await harness.repository.commitAgentChatMealCorrection(
        conversationId: 'conversation-1',
        mealId: original.id,
        sourceToolCallId: 'correction-call-1',
        clientMutationId: '00000000-0000-4000-8000-000000000004',
      );
      await tester.pumpAndSettle();

      expect(find.text('Corrected meal'), findsOneWidget);
      expect(find.text('Original meal'), findsNothing);
      verify(
        () => harness.apiClient.getDailySummary(date: any(named: 'date')),
      ).called(1);
    },
  );
}

class _Harness {
  _Harness()
      : apiClient = _MockApiClient(),
        navigator = GlobalKey<NavigatorState>(),
        date = _dateOnly(DateTime.now()),
        initial = _summary(_dateOnly(DateTime.now())) {
    // The real repository is deliberately used; only its API transport is
    // fake so this regression covers cache write-through and its typed bus.
    repository = NutritionRepository(
      apiClient: apiClient,
      cacheStore: NutritionCacheStore(storage: _MemoryStorage()),
    )..activateCacheForUser(_user.id);
    dashboard = DashboardViewModel(
      nutritionRepository: repository,
    );
    chat = AgentChatViewModel(
      nutritionRepository: repository,
      audioRecorderService: _MockAudioRecorderService(),
    );
  }

  final _MockApiClient apiClient;
  final GlobalKey<NavigatorState> navigator;
  final String date;
  final DailySummary initial;
  late final NutritionRepository repository;
  late final DashboardViewModel dashboard;
  late final AgentChatViewModel chat;

  Future<void> pumpDashboard(WidgetTester tester) async {
    await repository.putCachedDailySummary(initial);
    final auth = AuthViewModel(authRepository: _MockAuthRepository())
      ..setUser(_user);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewModel>.value(value: auth),
          ChangeNotifierProvider<DashboardViewModel>.value(value: dashboard),
          ChangeNotifierProvider<AgentChatViewModel>.value(value: chat),
        ],
        child: MaterialApp(
          navigatorKey: navigator,
          theme: buildLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const DashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose() async {
    dashboard.dispose();
    chat.dispose();
    await repository.dispose();
  }
}

class _MemoryStorage implements AppPreferencesStorage {
  final values = <String, String>{};

  @override
  Future<String?> readString(String key) async => values[key];

  @override
  Future<void> writeString(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<Set<String>> readKeys() async => values.keys.toSet();

  @override
  Future<void> removeWhere(bool Function(String key) test) async {
    values.removeWhere((key, value) => test(key));
  }
}

const _user = AuthUser(
  id: 'user-a',
  email: 'user@example.com',
  displayName: 'User',
  trustedModeEnabled: false,
);

Map<String, Object?> _mutationJson({
  required String id,
  required DailySummary summary,
}) =>
    {
      'version': 1,
      'mutationId': id,
      'committedAt': DateTime.now().toUtc().toIso8601String(),
      'effects': [
        {
          'domain': 'daily_summary',
          'operation': 'replace',
          'date': summary.date,
          'revision': 'server-revision',
          'snapshot': summary.toJson(),
        },
      ],
    };

Map<String, Object?> _mealMutationJson({
  required String id,
  required String date,
  required Meal meal,
}) =>
    {
      'version': 1,
      'mutationId': id,
      'committedAt': DateTime.now().toUtc().toIso8601String(),
      'effects': [
        {
          'domain': 'meals',
          'operation': 'upsert',
          'date': date,
          'entityId': meal.id,
          'revision': 'server-revision',
          'snapshot': meal.toJson(),
        },
      ],
    };

DailySummary _summary(
  String date, {
  List<Meal> meals = const [],
  int calories = 0,
}) {
  const target = NutritionSnapshot(
    calories: 2000,
    proteinGrams: 100,
    carbsGrams: 200,
    fatGrams: 60,
  );
  final consumed = NutritionSnapshot(
    calories: calories,
    proteinGrams: 20,
    carbsGrams: 30,
    fatGrams: 10,
  );
  return DailySummary(
    date: date,
    consumed: consumed,
    target: target,
    remaining: NutritionSnapshot(
      calories: target.calories - calories,
      proteinGrams: target.proteinGrams - consumed.proteinGrams,
      carbsGrams: target.carbsGrams - consumed.carbsGrams,
      fatGrams: target.fatGrams - consumed.fatGrams,
    ),
    hydrationGoalLiters: 2,
    waterConsumedLiters: 0,
    calorieTargetConfigured: true,
    calorieTargetSource: 'manual',
    meals: meals,
  );
}

Meal _meal(String id, String title) => Meal(
      id: id,
      title: title,
      occurredAt: DateTime.now(),
      nutrition: const NutritionSnapshot(
        calories: 450,
        proteinGrams: 20,
        carbsGrams: 30,
        fatGrams: 10,
      ),
      items: const [],
    );

String _dateOnly(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
