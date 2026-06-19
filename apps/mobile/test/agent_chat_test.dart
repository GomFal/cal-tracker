import 'dart:async';
import 'dart:convert';

import 'package:cal_tracker_mobile/app/theme.dart';
import 'package:cal_tracker_mobile/data/repositories/nutrition_repository.dart';
import 'package:cal_tracker_mobile/data/services/agent_chat_cache_store.dart';
import 'package:cal_tracker_mobile/data/services/agent_chat_session_store.dart';
import 'package:cal_tracker_mobile/data/services/app_preferences_storage.dart';
import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:cal_tracker_mobile/data/services/audio_recorder_service.dart';
import 'package:cal_tracker_mobile/data/services/secure_token_storage.dart';
import 'package:cal_tracker_mobile/domain/models/nutrition_models.dart';
import 'package:cal_tracker_mobile/generated/api/cal_tracker_api.dart';
import 'package:cal_tracker_mobile/l10n/generated/app_localizations.dart';
import 'package:cal_tracker_mobile/ui/features/agent_chat/view_models/agent_chat_view_model.dart';
import 'package:cal_tracker_mobile/ui/features/agent_chat/views/agent_chat_screen.dart';
import 'package:cal_tracker_mobile/ui/features/meal_templates/view_models/meal_templates_view_model.dart';
import 'package:cal_tracker_mobile/ui/features/meal_templates/view_models/usual_food_scan_view_model.dart';
import 'package:cal_tracker_mobile/ui/features/meal_templates/views/usual_food_scan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockNutritionRepository extends Mock implements NutritionRepository {}

class MockAudioRecorderService extends Mock implements AudioRecorderService {}

class _FakeAgentOcrScanViewModel extends UsualFoodScanViewModel {
  _FakeAgentOcrScanViewModel(this.context)
      : super(
          nutritionRepository: MockNutritionRepository(),
          initializeCamera: () async {},
          takePicture: () async => '/tmp/label.jpg',
          pausePreview: () async {},
          resumePreview: () async {},
          recognizeText: (_) async => '',
          deleteCapturedFile: (_) async {},
          draftFromRecognizedText: false,
        );

  final BuildContext context;

  @override
  Future<void> init() async {
    setUiStateForTest(const UsualFoodScanUiState(
      phase: UsualFoodScanPhase.ready,
    ));
  }

  @override
  Future<void> capture() async {
    Navigator.of(context).pop('Nutrition per 100 g\n360 kcal\nProtein 7 g');
  }
}

class _StreamingClient extends http.BaseClient {
  _StreamingClient(this.chunks);

  final List<String> chunks;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.fromIterable(chunks.map(utf8.encode)),
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  }
}

void main() {
  test('CalTrackerApiClient parses split agent chat SSE events', () async {
    final client = CalTrackerApiClient(
      config: const ApiConfig(baseUrl: 'http://localhost'),
      tokenStorage: _MemoryTokenStorage(),
      httpClient: _StreamingClient([
        'data: {"type":"conversation_started","conversationId":"11111111-1111-1111-1111-111111111111"}\n\n',
        'data: {"type":"assistant_delta","delta":"Meal ',
        'logged"}\n\n',
        'data: {"type":"done","conversationId":"11111111-1111-1111-1111-111111111111"}\n\n',
      ]),
    );

    final events = await client.streamAgentChat('hello').toList();

    expect(events, hasLength(3));
    expect(events[0]['type'], 'conversation_started');
    expect(events[1]['delta'], 'Meal logged');
    expect(events[2]['type'], 'done');
  });

  test('AgentChatViewModel turns tool events into visible timeline entries',
      () async {
    final repository = MockNutritionRepository();
    final recorder = MockAudioRecorderService();
    final summary = _summary();
    when(
      () => repository.streamAgentChat(
        any(),
        conversationId: any(named: 'conversationId'),
        activeProposalId: any(named: 'activeProposalId'),
      ),
    ).thenAnswer(
      (_) => Stream.fromIterable([
        const AgentChatStreamEvent(
          type: 'conversation_started',
          conversationId: '11111111-1111-1111-1111-111111111111',
        ),
        const AgentChatStreamEvent(
          type: 'tool_call_started',
          conversationId: '11111111-1111-1111-1111-111111111111',
          toolCall: AgentToolCallFeedback(
            id: 'call_summary',
            actionId: 'get_daily_summary',
            label: 'Get Daily Summary',
            summary: 'Reading daily summary',
          ),
        ),
        AgentChatStreamEvent(
          type: 'tool_call_completed',
          conversationId: '11111111-1111-1111-1111-111111111111',
          toolCall: const AgentToolCallFeedback(
            id: 'call_summary',
            actionId: 'get_daily_summary',
            label: 'Get Daily Summary',
            summary: 'Reading daily summary',
          ),
          result: AgentRunResult(
            kind: 'summary',
            message: 'Here is your daily summary.',
            summary: summary,
          ),
        ),
        const AgentChatStreamEvent(
          type: 'assistant_delta',
          conversationId: '11111111-1111-1111-1111-111111111111',
          delta: 'You ate breakfast.',
        ),
        const AgentChatStreamEvent(
          type: 'done',
          conversationId: '11111111-1111-1111-1111-111111111111',
        ),
      ]),
    );

    final viewModel = AgentChatViewModel(
      nutritionRepository: repository,
      audioRecorderService: recorder,
    );

    await viewModel.sendText('what did I eat today?');

    expect(viewModel.conversationId, '11111111-1111-1111-1111-111111111111');
    expect(viewModel.entries.map((entry) => entry.kind), [
      AgentChatEntryKind.user,
      AgentChatEntryKind.tool,
      AgentChatEntryKind.assistant,
    ]);
    final toolEntry = viewModel.entries[1];
    expect(toolEntry.toolStatus, AgentChatToolStatus.completed);
    expect(toolEntry.result?.summary?.consumed.calories, 420);
    expect(viewModel.entries[2].text, 'You ate breakfast.');
  });

  test('AgentChatViewModel starts blank after stale completed session',
      () async {
    final repository = MockNutritionRepository();
    final recorder = MockAudioRecorderService();
    final storage = _MemoryPreferencesStorage();
    final sessionStore = AgentChatSessionStore(storage: storage);
    final cacheStore = AgentChatCacheStore(storage: storage);
    sessionStore.activateUser('user-a');
    cacheStore.activateUser('user-a');
    await sessionStore.writeActiveSession(
      AgentChatSession(
        conversationId: '11111111-1111-1111-1111-111111111111',
        lastInteractionAt: DateTime.utc(2026, 6, 19, 12),
        lastCompletedAt: DateTime.utc(2026, 6, 19, 12),
        unfinished: false,
      ),
    );
    when(() => repository.listAgentConversations())
        .thenAnswer((_) async => const []);
    final viewModel = AgentChatViewModel(
      nutritionRepository: repository,
      audioRecorderService: recorder,
      sessionStore: sessionStore,
      cacheStore: cacheStore,
      now: () => DateTime.utc(2026, 6, 19, 12, 3),
    )..conversationId = '11111111-1111-1111-1111-111111111111';

    await viewModel.prepareForEntry();

    expect(viewModel.conversationId, isNull);
    expect(viewModel.entries, isEmpty);
    expect(await sessionStore.readActiveSession(), isNull);
    verifyNever(() => repository.getAgentConversation(any()));
  });

  test('AgentChatViewModel resumes stale unfinished session', () async {
    final repository = MockNutritionRepository();
    final recorder = MockAudioRecorderService();
    final storage = _MemoryPreferencesStorage();
    final sessionStore = AgentChatSessionStore(storage: storage);
    final cacheStore = AgentChatCacheStore(storage: storage);
    sessionStore.activateUser('user-a');
    cacheStore.activateUser('user-a');
    const conversationId = '11111111-1111-1111-1111-111111111111';
    await sessionStore.writeActiveSession(
      AgentChatSession(
        conversationId: conversationId,
        lastInteractionAt: DateTime.utc(2026, 6, 19, 12),
        unfinished: true,
      ),
    );
    when(() => repository.listAgentConversations())
        .thenAnswer((_) async => const []);
    when(() => repository.getAgentConversation(conversationId)).thenAnswer(
      (_) async => AgentConversationDetail(
        conversation: _conversationSummary(conversationId),
        messages: [
          AgentConversationMessage(
            id: 'message-1',
            conversationId: conversationId,
            role: 'user',
            content: 'finish this meal',
            createdAt: DateTime.utc(2026, 6, 19, 12),
          ),
        ],
      ),
    );
    final viewModel = AgentChatViewModel(
      nutritionRepository: repository,
      audioRecorderService: recorder,
      sessionStore: sessionStore,
      cacheStore: cacheStore,
      now: () => DateTime.utc(2026, 6, 19, 12, 10),
    );

    await viewModel.prepareForEntry();

    expect(viewModel.conversationId, conversationId);
    expect(viewModel.entries.single.text, 'finish this meal');
  });

  test('AgentChatViewModel manual new chat omits conversation id on next send',
      () async {
    final repository = MockNutritionRepository();
    final recorder = MockAudioRecorderService();
    when(
      () => repository.streamAgentChat(
        any(),
        conversationId: any(named: 'conversationId'),
        activeProposalId: any(named: 'activeProposalId'),
      ),
    ).thenAnswer(
      (_) => Stream.fromIterable([
        const AgentChatStreamEvent(
          type: 'conversation_started',
          conversationId: '22222222-2222-2222-2222-222222222222',
        ),
        const AgentChatStreamEvent(
          type: 'done',
          conversationId: '22222222-2222-2222-2222-222222222222',
        ),
      ]),
    );
    final viewModel = AgentChatViewModel(
      nutritionRepository: repository,
      audioRecorderService: recorder,
    )..conversationId = '11111111-1111-1111-1111-111111111111';

    await viewModel.startNewConversation();
    await viewModel.sendText('fresh start');

    verify(
      () => repository.streamAgentChat(
        'fresh start',
        conversationId: null,
        activeProposalId: any(named: 'activeProposalId'),
      ),
    ).called(1);
    expect(viewModel.conversationId, '22222222-2222-2222-2222-222222222222');
  });

  testWidgets('AgentChatScreen renders a completed tool widget',
      (tester) async {
    final repository = MockNutritionRepository();
    final recorder = MockAudioRecorderService();
    when(
      () => repository.streamAgentChat(
        any(),
        conversationId: any(named: 'conversationId'),
        activeProposalId: any(named: 'activeProposalId'),
      ),
    ).thenAnswer(
      (_) => Stream.fromIterable([
        const AgentChatStreamEvent(
          type: 'conversation_started',
          conversationId: '11111111-1111-1111-1111-111111111111',
        ),
        const AgentChatStreamEvent(
          type: 'tool_call_started',
          conversationId: '11111111-1111-1111-1111-111111111111',
          toolCall: AgentToolCallFeedback(
            id: 'call_remaining',
            actionId: 'get_remaining_targets',
            label: 'Get Remaining Targets',
            summary: 'Checking remaining targets',
          ),
        ),
        const AgentChatStreamEvent(
          type: 'tool_call_completed',
          conversationId: '11111111-1111-1111-1111-111111111111',
          toolCall: AgentToolCallFeedback(
            id: 'call_remaining',
            actionId: 'get_remaining_targets',
            label: 'Get Remaining Targets',
            summary: 'Checking remaining targets',
          ),
          result: AgentRunResult(
            kind: 'remaining_targets',
            message: 'Here are your remaining targets.',
            remaining: NutritionSnapshot(
              calories: 780,
              proteinGrams: 40,
              carbsGrams: 80,
              fatGrams: 20,
            ),
          ),
        ),
        const AgentChatStreamEvent(
          type: 'done',
          conversationId: '11111111-1111-1111-1111-111111111111',
        ),
      ]),
    );
    final viewModel = AgentChatViewModel(
      nutritionRepository: repository,
      audioRecorderService: recorder,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildLightTheme(),
          home: const AgentChatScreen(),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent_chat_message_field')),
      'how many calories left?',
    );
    await tester.tap(find.byKey(const ValueKey('agent_chat_send_button')));
    await tester.pumpAndSettle();

    expect(find.text('Get Remaining Targets'), findsOneWidget);
    expect(find.textContaining('780'), findsOneWidget);
  });

  testWidgets('AgentChatScreen renders quick reply buttons that send text',
      (tester) async {
    final repository = MockNutritionRepository();
    final recorder = MockAudioRecorderService();
    when(
      () => repository.streamAgentChat(
        any(),
        conversationId: any(named: 'conversationId'),
        activeProposalId: any(named: 'activeProposalId'),
      ),
    ).thenAnswer((invocation) {
      final message = invocation.positionalArguments.first as String;
      if (message == 'Sí, guárdala así') {
        return Stream.fromIterable([
          const AgentChatStreamEvent(
            type: 'assistant_delta',
            conversationId: '11111111-1111-1111-1111-111111111111',
            delta: 'Perfecto, la guardo así.',
          ),
          const AgentChatStreamEvent(
            type: 'done',
            conversationId: '11111111-1111-1111-1111-111111111111',
          ),
        ]);
      }
      return Stream.fromIterable([
        const AgentChatStreamEvent(
          type: 'conversation_started',
          conversationId: '11111111-1111-1111-1111-111111111111',
        ),
        const AgentChatStreamEvent(
          type: 'assistant_delta',
          conversationId: '11111111-1111-1111-1111-111111111111',
          delta: '¿La guardo así?',
        ),
        const AgentChatStreamEvent(
          type: 'assistant_suggestions',
          conversationId: '11111111-1111-1111-1111-111111111111',
          suggestions: [
            AgentChatSuggestion(label: 'Sí', value: 'Sí, guárdala así'),
            AgentChatSuggestion(label: 'No', value: 'No, quiero editarla'),
          ],
        ),
        const AgentChatStreamEvent(
          type: 'done',
          conversationId: '11111111-1111-1111-1111-111111111111',
        ),
      ]);
    });
    final viewModel = AgentChatViewModel(
      nutritionRepository: repository,
      audioRecorderService: recorder,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildLightTheme(),
          home: const AgentChatScreen(),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent_chat_message_field')),
      'save it?',
    );
    await tester.tap(find.byKey(const ValueKey('agent_chat_send_button')));
    await tester.pumpAndSettle();

    expect(find.text('Sí'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('agent_chat_suggestion_0')));
    await tester.pumpAndSettle();

    verify(
      () => repository.streamAgentChat(
        'Sí, guárdala así',
        conversationId: '11111111-1111-1111-1111-111111111111',
        activeProposalId: any(named: 'activeProposalId'),
      ),
    ).called(1);
    expect(find.textContaining('Perfecto'), findsOneWidget);
  });

  testWidgets('AgentChatScreen scans a label and submits OCR text to agent',
      (tester) async {
    final repository = MockNutritionRepository();
    final recorder = MockAudioRecorderService();
    String? submittedText;
    when(
      () => repository.streamAgentChat(
        any(),
        conversationId: any(named: 'conversationId'),
        activeProposalId: any(named: 'activeProposalId'),
      ),
    ).thenAnswer((invocation) {
      submittedText = invocation.positionalArguments.first as String;
      return Stream.fromIterable([
        const AgentChatStreamEvent(
          type: 'conversation_started',
          conversationId: '11111111-1111-1111-1111-111111111111',
        ),
        const AgentChatStreamEvent(
          type: 'done',
          conversationId: '11111111-1111-1111-1111-111111111111',
        ),
      ]);
    });
    final viewModel = AgentChatViewModel(
      nutritionRepository: repository,
      audioRecorderService: recorder,
    );
    testViewModelFactory = (context) => _FakeAgentOcrScanViewModel(context);
    addTearDown(() => testViewModelFactory = null);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildLightTheme(),
          home: const AgentChatScreen(),
        ),
      ),
    );

    await tester
        .tap(find.byKey(const ValueKey('agent_chat_scan_label_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('usual_food_scan_capture_button')),
        findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('usual_food_scan_capture_button')));
    await tester.pumpAndSettle();

    expect(submittedText, contains('Nutrition per 100 g'));
    expect(submittedText, contains('Create a usual ingredient draft'));
    expect(find.byType(AgentChatScreen), findsOneWidget);
  });

  testWidgets('AgentChatScreen opens usual food draft editor and pops back',
      (tester) async {
    final repository = MockNutritionRepository();
    final recorder = MockAudioRecorderService();
    const draft = UsualFoodDraft(
      name: 'Arroz Hacendado',
      servingGrams: 100,
      calories: 360,
      proteinGrams: 7,
      carbsGrams: 79,
      fatGrams: 1,
    );
    when(
      () => repository.streamAgentChat(
        any(),
        conversationId: any(named: 'conversationId'),
        activeProposalId: any(named: 'activeProposalId'),
      ),
    ).thenAnswer(
      (_) => Stream.fromIterable([
        const AgentChatStreamEvent(
          type: 'conversation_started',
          conversationId: '11111111-1111-1111-1111-111111111111',
        ),
        const AgentChatStreamEvent(
          type: 'tool_call_started',
          conversationId: '11111111-1111-1111-1111-111111111111',
          toolCall: AgentToolCallFeedback(
            id: 'call_draft',
            actionId: 'draft_usual_food',
            label: 'Draft Usual Ingredient',
            summary: 'Preparing a reviewed usual ingredient draft',
          ),
        ),
        const AgentChatStreamEvent(
          type: 'tool_call_completed',
          conversationId: '11111111-1111-1111-1111-111111111111',
          toolCall: AgentToolCallFeedback(
            id: 'call_draft',
            actionId: 'draft_usual_food',
            label: 'Draft Usual Ingredient',
            summary: 'Preparing a reviewed usual ingredient draft',
          ),
          result: AgentRunResult(
            kind: 'usual_food_draft',
            message: 'Review this ingredient before saving.',
            usualFoodDraft: draft,
          ),
        ),
        const AgentChatStreamEvent(
          type: 'done',
          conversationId: '11111111-1111-1111-1111-111111111111',
        ),
      ]),
    );
    when(() => repository.cachedTemplates()).thenAnswer((_) async => null);
    when(() => repository.cachedUsualFoods()).thenAnswer((_) async => null);
    when(
      () => repository.refreshTemplates(force: any(named: 'force')),
    ).thenAnswer((_) async => const <MealTemplate>[]);
    when(
      () => repository.refreshUsualFoods(force: any(named: 'force')),
    ).thenAnswer((_) async => const <UsualFood>[]);
    final viewModel = AgentChatViewModel(
      nutritionRepository: repository,
      audioRecorderService: recorder,
    );
    final templatesViewModel = MealTemplatesViewModel(
      nutritionRepository: repository,
    );
    final router = GoRouter(
      initialLocation: '/agent',
      routes: [
        GoRoute(
          path: '/agent',
          builder: (context, state) => const AgentChatScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: viewModel),
          ChangeNotifierProvider.value(value: templatesViewModel),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildLightTheme(),
          routerConfig: router,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent_chat_message_field')),
      'save rice as a usual ingredient',
    );
    await tester.tap(find.byKey(const ValueKey('agent_chat_send_button')));
    await tester.pumpAndSettle();

    expect(find.text('Usual ingredient draft'), findsOneWidget);
    expect(find.text('Arroz Hacendado'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('agent_chat_review_usual_food_draft_button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('New usual ingredient'), findsOneWidget);
    expect(find.text('Arroz Hacendado'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('usual_food_save_button')), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.byType(AgentChatScreen), findsOneWidget);
    expect(find.text('Usual ingredient draft'), findsOneWidget);
  });
}

DailySummary _summary() {
  return const DailySummary(
    date: '2026-06-16',
    consumed: NutritionSnapshot(
      calories: 420,
      proteinGrams: 25,
      carbsGrams: 40,
      fatGrams: 12,
    ),
    target: NutritionSnapshot(
      calories: 2200,
      proteinGrams: 120,
      carbsGrams: 250,
      fatGrams: 70,
    ),
    remaining: NutritionSnapshot(
      calories: 1780,
      proteinGrams: 95,
      carbsGrams: 210,
      fatGrams: 58,
    ),
    hydrationGoalLiters: 2,
    waterConsumedLiters: 0.5,
    calorieTargetConfigured: true,
    calorieTargetSource: 'manual',
    meals: [],
  );
}

AgentConversationSummary _conversationSummary(String id) {
  return AgentConversationSummary(
    id: id,
    title: 'Saved chat',
    createdAt: DateTime.utc(2026, 6, 19, 12),
    updatedAt: DateTime.utc(2026, 6, 19, 12, 1),
  );
}

class _MemoryTokenStorage implements TokenStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<StoredTokens?> read() async => null;

  @override
  Future<void> write(StoredTokens tokens) async {}
}

class _MemoryPreferencesStorage implements AppPreferencesStorage {
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
