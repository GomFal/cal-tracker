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
    setUiStateForTest(
      const UsualFoodScanUiState(phase: UsualFoodScanPhase.ready),
    );
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
  setUpAll(() {
    registerFallbackValue(
      const UsualFoodInput(
        name: 'Fallback',
        servingGrams: 100,
        nutrition: NutritionSnapshot(
          calories: 0,
          proteinGrams: 0,
          carbsGrams: 0,
          fatGrams: 0,
        ),
      ),
    );
    registerFallbackValue(<UsualFood>[]);
  });

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

  test('CalTrackerApiClient keeps typed safe SSE errors and trace ids',
      () async {
    final client = CalTrackerApiClient(
      config: const ApiConfig(baseUrl: 'http://localhost'),
      tokenStorage: _MemoryTokenStorage(),
      httpClient: _StreamingClient([
        'data: {"type":"error","error":{"code":"provider_unavailable","message":"The nutrition assistant is temporarily unavailable. Try again shortly.","traceId":"trace-sse"}}\n\n',
      ]),
    );

    final events = await client.streamAgentChat('hello').toList();
    final error = ApiErrorDetails.fromJson(
      events.single['error'] as Map<String, Object?>,
    );

    expect(error.code, 'provider_unavailable');
    expect(error.traceId, 'trace-sse');
    expect(error.message, isNot(contains('http')));
  });

  test(
    'CalTrackerApiClient classifies a prematurely closed SSE stream',
    () async {
      final client = CalTrackerApiClient(
        config: const ApiConfig(baseUrl: 'http://localhost'),
        tokenStorage: _MemoryTokenStorage(),
        httpClient: _StreamingClient([
          'data: {"type":"assistant_delta","delta":"Partial"}\n\n',
        ]),
      );

      await expectLater(
        client.streamAgentChat('hello').toList(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.code,
            'code',
            'internal_error',
          ),
        ),
      );
    },
  );

  test('ApiErrorDetails rejects unknown server categories', () {
    final error = ApiErrorDetails.fromJson({
      'code': 'provider_raw_secret_category',
      'message': 'untrusted server text',
      'traceId': 'trace-unknown',
    });

    expect(error.code, 'internal_error');
    expect(error.traceId, 'trace-unknown');
  });

  test(
    'AgentChatViewModel classifies SSE errors by code, not message',
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
        (_) => Stream.value(
          const AgentChatStreamEvent(
            type: 'error',
            error: ApiErrorDetails(
              code: 'rate_limit_exceeded',
              message: 'Server copy that the UI must not inspect.',
              traceId: 'trace-rate',
            ),
          ),
        ),
      );
      final viewModel = AgentChatViewModel(
        nutritionRepository: repository,
        audioRecorderService: recorder,
      );

      await viewModel.sendText('hello');

      expect(viewModel.errorCode, 'rate_limit_exceeded');
      expect(
        viewModel.errorMessage,
        'Server copy that the UI must not inspect.',
      );
    },
  );

  test('logout reset cancels an active chat recording', () async {
    final repository = MockNutritionRepository();
    final recorder = MockAudioRecorderService();
    when(() => recorder.start()).thenAnswer((_) async {});
    when(() => recorder.cancel()).thenAnswer((_) async {});
    final viewModel = AgentChatViewModel(
      nutritionRepository: repository,
      audioRecorderService: recorder,
    );

    await viewModel.startRecording();
    viewModel.reset();
    await Future<void>.delayed(Duration.zero);

    expect(viewModel.isRecording, isFalse);
    verify(() => recorder.cancel()).called(1);
  });

  for (final testCase in <(Locale, String)>[
    (
      const Locale('en'),
      'Microphone access is off. Enable it in your device settings to record, or log your meal manually.',
    ),
    (
      const Locale('es'),
      'El acceso al micrófono está desactivado. Actívalo en los ajustes del dispositivo para grabar o registra tu comida manualmente.',
    ),
  ]) {
    testWidgets(
      'AgentChatScreen localizes microphone denial recovery in ${testCase.$1.languageCode}',
      (tester) async {
        final repository = MockNutritionRepository();
        final recorder = MockAudioRecorderService();
        when(
          () => recorder.start(),
        ).thenThrow(const RecorderException('permission_denied'));
        final viewModel = AgentChatViewModel(
          nutritionRepository: repository,
          audioRecorderService: recorder,
        );

        await tester.pumpWidget(
          ChangeNotifierProvider<AgentChatViewModel>.value(
            value: viewModel,
            child: MaterialApp(
              locale: testCase.$1,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: buildLightTheme(),
              home: const AgentChatScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('agent_chat_mic_button')));
        await tester.pump();

        expect(viewModel.errorCode, 'microphone_permission_denied');
        expect(viewModel.errorMessage, isNull);
        expect(find.text(testCase.$2), findsOneWidget);
        expect(
          find.byKey(const ValueKey('agent_chat_message_field')),
          findsOneWidget,
        );

        await tester.pump(const Duration(milliseconds: 250));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 250));
        viewModel.dispose();
      },
    );
  }

  test(
    'AgentChatViewModel turns tool events into visible timeline entries',
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
    },
  );

  test('AgentChatViewModel clears active proposal after meal commit', () async {
    final repository = MockNutritionRepository();
    final recorder = MockAudioRecorderService();
    String? commitRequestActiveProposalId;
    const nutrition = NutritionSnapshot(
      calories: 360,
      proteinGrams: 7,
      carbsGrams: 79,
      fatGrams: 1,
    );
    const proposal = MealProposal(
      id: 'proposal_rice',
      title: 'Rice',
      confidence: 0.9,
      requiresConfirmation: true,
      trustedAutoCommitEligible: false,
      nutrition: nutrition,
      items: [],
    );
    final meal = Meal(
      id: 'meal_rice',
      title: 'Rice',
      occurredAt: DateTime.utc(2026, 6, 16, 12),
      nutrition: nutrition,
      items: const [],
    );
    when(
      () => repository.streamAgentChat(
        any(),
        conversationId: any(named: 'conversationId'),
        activeProposalId: any(named: 'activeProposalId'),
      ),
    ).thenAnswer((invocation) {
      final message = invocation.positionalArguments.first as String;
      if (message == 'log rice') {
        return Stream.fromIterable([
          const AgentChatStreamEvent(
            type: 'tool_call_completed',
            toolCall: AgentToolCallFeedback(
              id: 'call_proposal',
              actionId: 'propose_meal_log',
              label: 'Create proposal',
              summary: 'Creating a meal proposal',
            ),
            result: AgentRunResult(
              kind: 'proposal',
              message: 'Meal proposal created.',
              proposal: proposal,
            ),
          ),
          const AgentChatStreamEvent(type: 'done'),
        ]);
      }
      commitRequestActiveProposalId =
          invocation.namedArguments[#activeProposalId] as String?;
      return Stream.fromIterable([
        AgentChatStreamEvent(
          type: 'tool_call_completed',
          toolCall: const AgentToolCallFeedback(
            id: 'call_commit',
            actionId: 'commit_meal',
            label: 'Commit meal',
            summary: 'Logging meal',
          ),
          result: AgentRunResult(
            kind: 'meal_committed',
            message: 'Meal logged.',
            meal: meal,
          ),
        ),
        const AgentChatStreamEvent(type: 'done'),
      ]);
    });
    final viewModel = AgentChatViewModel(
      nutritionRepository: repository,
      audioRecorderService: recorder,
    );

    await viewModel.sendText('log rice');
    expect(viewModel.activeProposalId, 'proposal_rice');

    await viewModel.sendText('yes, log it');
    expect(commitRequestActiveProposalId, 'proposal_rice');
    expect(viewModel.activeProposalId, isNull);
  });

  test(
    'AgentChatViewModel starts blank after stale completed session',
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
      when(
        () => repository.listAgentConversations(),
      ).thenAnswer((_) async => const []);
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
    },
  );

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
    when(
      () => repository.listAgentConversations(),
    ).thenAnswer((_) async => const []);
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

  test(
    'AgentChatViewModel manual new chat omits conversation id on next send',
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
    },
  );

  testWidgets('AgentChatScreen renders a completed tool widget', (
    tester,
  ) async {
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

  testWidgets('AgentChatScreen renders quick reply buttons that send text', (
    tester,
  ) async {
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

  testWidgets('AgentChatScreen scans a label and submits OCR text to agent', (
    tester,
  ) async {
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

    await tester.tap(
      find.byKey(const ValueKey('agent_chat_scan_label_button')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('usual_food_scan_capture_button')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('usual_food_scan_capture_button')),
    );
    await tester.pumpAndSettle();

    expect(submittedText, contains('Nutrition per 100 g'));
    expect(submittedText, contains('Create a usual ingredient draft'));
    expect(find.byType(AgentChatScreen), findsOneWidget);
  });

  testWidgets(
    'AgentChatScreen marks usual food draft saved after editor save',
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
      when(
        () => repository.putCachedUsualFoods(any()),
      ).thenAnswer((_) async {});
      when(() => repository.createUsualFood(any())).thenAnswer((
        invocation,
      ) async {
        final input = invocation.positionalArguments.first as UsualFoodInput;
        return UsualFood(
          id: 'usual_food_rice',
          name: input.name,
          canonicalName: input.canonicalName,
          brand: input.brand,
          barcode: input.barcode,
          servingGrams: input.servingGrams,
          nutrition: input.nutrition,
          aliases: input.aliases,
          nutrients: input.nutrients,
        );
      });
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

      expect(find.text('New saved ingredient'), findsOneWidget);
      expect(find.text('Arroz Hacendado'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('usual_food_save_button')),
        findsOneWidget,
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('usual_food_save_button')),
      );
      await tester.tap(find.byKey(const ValueKey('usual_food_save_button')));
      await tester.pumpAndSettle();

      expect(find.byType(AgentChatScreen), findsOneWidget);
      expect(find.text('Usual ingredient draft'), findsOneWidget);
      expect(
        find.text('Saved Arroz Hacendado to your usual ingredients.'),
        findsWidgets,
      );
      expect(
        find.byKey(const ValueKey('agent_chat_review_usual_food_draft_button')),
        findsNothing,
      );
      verify(() => repository.createUsualFood(any())).called(1);
    },
  );
  testWidgets('chat deletion explains scope and removes the row immediately', (
    tester,
  ) async {
    final repository = MockNutritionRepository();
    final recorder = MockAudioRecorderService();
    const conversationId = '11111111-1111-1111-1111-111111111111';
    when(
      () => repository.listAgentConversations(),
    ).thenAnswer((_) async => [_conversationSummary(conversationId)]);
    when(
      () => repository.deleteAgentConversation(conversationId),
    ).thenAnswer((_) async {});
    final viewModel = AgentChatViewModel(
      nutritionRepository: repository,
      audioRecorderService: recorder,
    );
    await viewModel.refreshConversationHistory();

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
    await tester.tap(
      find.byKey(const ValueKey('agent_chat_history_button')).hitTestable(),
    );
    await tester.pumpAndSettle();
    expect(find.text('Saved chat'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('agent_chat_history_delete_0')).hitTestable(),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'permanently removed from active systems within 24 hours',
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('agent_chat_delete_confirm')).hitTestable(),
    );
    await tester.pump();

    expect(find.text('Saved chat'), findsNothing);
    verify(() => repository.deleteAgentConversation(conversationId)).called(1);
  });

  test('a stale history response cannot repopulate a deleted chat', () async {
    final repository = MockNutritionRepository();
    final recorder = MockAudioRecorderService();
    final storage = _MemoryPreferencesStorage();
    final cache = AgentChatCacheStore(storage: storage)..activateUser('user-a');
    const conversationId = '11111111-1111-1111-1111-111111111111';
    final response = Completer<List<AgentConversationSummary>>();
    when(
      () => repository.listAgentConversations(),
    ).thenAnswer((_) => response.future);
    when(
      () => repository.deleteAgentConversation(conversationId),
    ).thenAnswer((_) async {});
    final viewModel = AgentChatViewModel(
      nutritionRepository: repository,
      audioRecorderService: recorder,
      cacheStore: cache,
    );

    final refresh = viewModel.refreshConversationHistory();
    await Future<void>.delayed(Duration.zero);
    await viewModel.deleteConversation(conversationId);
    response.complete([_conversationSummary(conversationId)]);
    await refresh;

    expect(viewModel.conversations, isEmpty);
    expect(await cache.readConversationSummaries(), isEmpty);
    expect(await cache.isConversationDeleted(conversationId), isTrue);
  });

  test(
    'a failed backend deletion rolls back the tombstone and can be retried',
    () async {
      final repository = MockNutritionRepository();
      final recorder = MockAudioRecorderService();
      final storage = _MemoryPreferencesStorage();
      final cache = AgentChatCacheStore(storage: storage)
        ..activateUser('user-a');
      const conversationId = '11111111-1111-1111-1111-111111111111';
      var attempts = 0;
      when(
        () => repository.listAgentConversations(),
      ).thenAnswer((_) async => [_conversationSummary(conversationId)]);
      when(() => repository.deleteAgentConversation(conversationId)).thenAnswer(
        (_) async {
          attempts++;
          if (attempts == 1) throw Exception('offline');
        },
      );
      final viewModel = AgentChatViewModel(
        nutritionRepository: repository,
        audioRecorderService: recorder,
        cacheStore: cache,
      );
      await viewModel.refreshConversationHistory();

      await viewModel.deleteConversation(conversationId);
      expect(viewModel.errorMessage, isNotNull);
      expect(viewModel.conversations.map((item) => item.id), [conversationId]);
      expect(await cache.isConversationDeleted(conversationId), isFalse);

      await viewModel.deleteConversation(conversationId);
      expect(viewModel.errorMessage, isNull);
      expect(viewModel.conversations, isEmpty);
      expect(await cache.isConversationDeleted(conversationId), isTrue);
      expect(attempts, 2);
    },
  );

  test(
    'deleting an active conversation abandons later stream events',
    () async {
      final repository = MockNutritionRepository();
      final recorder = MockAudioRecorderService();
      final events = StreamController<AgentChatStreamEvent>();
      const conversationId = '11111111-1111-1111-1111-111111111111';
      when(
        () => repository.streamAgentChat(
          any(),
          conversationId: any(named: 'conversationId'),
          activeProposalId: any(named: 'activeProposalId'),
        ),
      ).thenAnswer((_) => events.stream);
      when(
        () => repository.deleteAgentConversation(conversationId),
      ).thenAnswer((_) async {});
      final viewModel = AgentChatViewModel(
        nutritionRepository: repository,
        audioRecorderService: recorder,
      );

      final send = viewModel.sendText('private message');
      events.add(
        const AgentChatStreamEvent(
          type: 'conversation_started',
          conversationId: conversationId,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.isSending, isTrue);
      expect(viewModel.conversationId, conversationId);

      await viewModel.deleteConversation(conversationId);
      events.add(
        const AgentChatStreamEvent(
          type: 'assistant_delta',
          conversationId: conversationId,
          delta: 'must not reappear',
        ),
      );
      events.add(
        const AgentChatStreamEvent(
          type: 'done',
          conversationId: conversationId,
        ),
      );
      await events.close();
      await send;

      expect(viewModel.conversationId, isNull);
      expect(
        viewModel.entries.where((entry) => entry.text.contains('reappear')),
        isEmpty,
      );
    },
  );
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
