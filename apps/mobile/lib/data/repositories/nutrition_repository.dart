import 'dart:async';
import 'dart:collection';
import 'dart:io';

import '../../domain/models/macro_distribution.dart';
import '../../domain/models/nutrition_data_change.dart';
import '../../domain/models/nutrition_models.dart';
import '../../domain/models/nutrition_summary_updates.dart';
import '../../generated/api/cal_tracker_api.dart';
import '../services/backend_health_monitor.dart';
import '../services/client_telemetry_service.dart';
import '../services/nutrition_cache_store.dart';

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
    this.usualFoods,
    this.resolvedItems,
    this.deleted,
    this.actionId,
    this.input,
    this.clarificationOptions,
    this.candidateGroups,
    this.usualFoodDraft,
    this.usualMealDraft,
    this.sourceProposalId,
    this.confirmedMutation,
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
  final List<UsualFood>? usualFoods;
  final List<MealItem>? resolvedItems;
  final bool? deleted;
  final String? actionId;
  final dynamic input;
  final List<FoodCandidateGroup>? clarificationOptions;
  final List<FoodCandidateGroup>? candidateGroups;
  final UsualFoodDraft? usualFoodDraft;
  final UsualMealDraft? usualMealDraft;
  final String? sourceProposalId;
  final ConfirmedNutritionMutation? confirmedMutation;
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

class AgentChatSuggestion {
  const AgentChatSuggestion({required this.label, required this.value});

  final String label;
  final String value;

  factory AgentChatSuggestion.fromJson(Map<String, Object?> json) {
    final label = (json['label'] as String? ?? '').trim();
    final value = (json['value'] as String? ?? label).trim();
    return AgentChatSuggestion(label: label, value: value);
  }
}

class AgentToolCallFeedback {
  const AgentToolCallFeedback({
    required this.id,
    required this.actionId,
    required this.label,
    required this.summary,
    this.input,
  });

  final String id;
  final String actionId;
  final String label;
  final String summary;
  final dynamic input;

  factory AgentToolCallFeedback.fromJson(Map<String, Object?> json) {
    return AgentToolCallFeedback(
      id: json['id'] as String? ?? '',
      actionId: json['actionId'] as String? ?? '',
      label: json['label'] as String? ?? json['actionId'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      input: json['input'],
    );
  }
}

class AgentToolExecutionSnapshot {
  const AgentToolExecutionSnapshot({
    required this.schemaVersion,
    required this.conversationId,
    required this.turnId,
    required this.assistantMessageId,
    required this.toolCallId,
    required this.iteration,
    required this.toolCallIndex,
    required this.toolCall,
    required this.status,
    required this.startedAt,
    this.completedAt,
    this.result,
    this.resultJson,
    this.widget,
    this.error,
  });

  final int schemaVersion;
  final String conversationId;
  final String turnId;
  final String assistantMessageId;
  final String toolCallId;
  final int iteration;
  final int toolCallIndex;
  final AgentToolCallFeedback toolCall;
  final String status;
  final DateTime startedAt;
  final DateTime? completedAt;
  final AgentRunResult? result;
  final Map<String, Object?>? resultJson;
  final Object? widget;
  final ApiErrorDetails? error;

  static AgentToolExecutionSnapshot? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final json = value.map(
      (key, nested) => MapEntry(key.toString(), nested),
    );
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion is! num ||
        json['conversationId'] is! String ||
        json['turnId'] is! String ||
        json['assistantMessageId'] is! String ||
        json['toolCallId'] is! String ||
        json['iteration'] is! num ||
        json['toolCallIndex'] is! num ||
        json['toolCall'] is! Map ||
        json['startedAt'] is! String) {
      return null;
    }
    final startedAt = DateTime.tryParse(json['startedAt'] as String);
    if (startedAt == null) return null;
    const supportedStatuses = {'started', 'completed', 'failed', 'interrupted'};
    final rawStatus = json['status'];
    // A newer server schema remains a visible generic card rather than taking
    // down the entire cached conversation. Its unknown result is intentionally
    // not interpreted by this client.
    final status = rawStatus is String && supportedStatuses.contains(rawStatus)
        ? rawStatus
        : 'interrupted';
    final resultValue = json['result'];
    final resultJson = resultValue is Map
        ? resultValue.map((key, nested) => MapEntry(key.toString(), nested))
        : null;
    AgentRunResult? result;
    if (schemaVersion == 1 && resultJson != null) {
      try {
        result = agentRunResultFromJson(resultJson);
      } on Object {
        // Keep the card and raw result for a future compatible client.
      }
    }
    ApiErrorDetails? error;
    final errorValue = json['error'];
    if (errorValue is Map) {
      try {
        error = ApiErrorDetails.fromJson(
          errorValue.map((key, nested) => MapEntry(key.toString(), nested)),
        );
      } on Object {
        // A malformed error must not hide a valid persisted execution.
      }
    }
    return AgentToolExecutionSnapshot(
      schemaVersion: schemaVersion.toInt(),
      conversationId: json['conversationId'] as String,
      turnId: json['turnId'] as String,
      assistantMessageId: json['assistantMessageId'] as String,
      toolCallId: json['toolCallId'] as String,
      iteration: (json['iteration'] as num).toInt(),
      toolCallIndex: (json['toolCallIndex'] as num).toInt(),
      toolCall: AgentToolCallFeedback.fromJson(
        (json['toolCall'] as Map).map(
          (key, nested) => MapEntry(key.toString(), nested),
        ),
      ),
      status: status,
      startedAt: startedAt,
      completedAt: json['completedAt'] is String
          ? DateTime.tryParse(json['completedAt'] as String)
          : null,
      result: result,
      resultJson: resultJson,
      widget: json['widget'],
      error: error,
    );
  }

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'conversationId': conversationId,
        'turnId': turnId,
        'assistantMessageId': assistantMessageId,
        'toolCallId': toolCallId,
        'iteration': iteration,
        'toolCallIndex': toolCallIndex,
        'toolCall': {
          'id': toolCall.id,
          'actionId': toolCall.actionId,
          'label': toolCall.label,
          'summary': toolCall.summary,
          'input': toolCall.input,
        },
        'status': status,
        'startedAt': startedAt.toUtc().toIso8601String(),
        if (completedAt != null)
          'completedAt': completedAt!.toUtc().toIso8601String(),
        if (resultJson != null) 'result': resultJson,
        if (widget != null) 'widget': widget,
        if (error != null)
          'error': {'code': error!.code, 'message': error!.message},
      };
}

class AgentChatStreamEvent {
  const AgentChatStreamEvent({
    required this.type,
    this.conversationId,
    this.message,
    this.delta,
    this.transcript,
    this.error,
    this.toolCall,
    this.result,
    this.widget,
    this.execution,
    this.suggestions = const [],
  });

  final String type;
  final String? conversationId;
  final String? message;
  final String? delta;
  final String? transcript;
  final ApiErrorDetails? error;
  final AgentToolCallFeedback? toolCall;
  final AgentRunResult? result;
  final Object? widget;
  final AgentToolExecutionSnapshot? execution;
  final List<AgentChatSuggestion> suggestions;
}

class AgentConversationSummary {
  const AgentConversationSummary({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.hiddenFromUserAt,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? hiddenFromUserAt;

  factory AgentConversationSummary.fromJson(Map<String, Object?> json) {
    return AgentConversationSummary(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Nutrition chat',
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      hiddenFromUserAt: json['hiddenFromUserAt'] is String
          ? DateTime.parse(json['hiddenFromUserAt'] as String)
          : null,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        if (hiddenFromUserAt != null)
          'hiddenFromUserAt': hiddenFromUserAt!.toUtc().toIso8601String(),
      };
}

class AgentConversationMessage {
  const AgentConversationMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.toolCalls,
    this.toolCallId,
    this.traceId,
    this.turnId,
    this.inputMode,
    this.source,
    this.activeProposalId,
    this.metadata,
  });

  final String id;
  final String conversationId;
  final String role;
  final String content;
  final DateTime createdAt;
  final Object? toolCalls;
  final String? toolCallId;
  final String? traceId;
  final String? turnId;
  final String? inputMode;
  final String? source;
  final String? activeProposalId;
  final Object? metadata;

  factory AgentConversationMessage.fromJson(Map<String, Object?> json) {
    final message = tryFromJson(json);
    if (message == null) throw const FormatException('Invalid chat message');
    return message;
  }

  static AgentConversationMessage? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final json = value.map((key, nested) => MapEntry(key.toString(), nested));
    final id = json['id'];
    final conversationId = json['conversationId'];
    final role = json['role'];
    final createdAtRaw = json['createdAt'];
    if (id is! String ||
        conversationId is! String ||
        role is! String ||
        createdAtRaw is! String) {
      return null;
    }
    final createdAt = DateTime.tryParse(createdAtRaw);
    if (createdAt == null) return null;
    return AgentConversationMessage(
      id: id,
      conversationId: conversationId,
      role: role,
      content: json['content'] as String? ?? '',
      createdAt: createdAt,
      toolCalls: json['toolCalls'],
      toolCallId: json['toolCallId'] as String?,
      traceId: json['traceId'] as String?,
      turnId: json['turnId'] as String?,
      inputMode: json['inputMode'] as String?,
      source: json['source'] as String?,
      activeProposalId: json['activeProposalId'] as String?,
      metadata: json['metadata'],
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'conversationId': conversationId,
        'role': role,
        'content': content,
        'createdAt': createdAt.toUtc().toIso8601String(),
        if (toolCalls != null) 'toolCalls': toolCalls,
        if (toolCallId != null) 'toolCallId': toolCallId,
        if (traceId != null) 'traceId': traceId,
        if (turnId != null) 'turnId': turnId,
        if (inputMode != null) 'inputMode': inputMode,
        if (source != null) 'source': source,
        if (activeProposalId != null) 'activeProposalId': activeProposalId,
        if (metadata != null) 'metadata': metadata,
      };
}

class AgentConversationDetail {
  const AgentConversationDetail({
    required this.conversation,
    required this.messages,
    this.toolExecutions = const [],
  });

  final AgentConversationSummary conversation;
  final List<AgentConversationMessage> messages;
  final List<AgentToolExecutionSnapshot> toolExecutions;

  Map<String, Object?> toJson() => {
        'conversation': conversation.toJson(),
        'messages': messages.map((message) => message.toJson()).toList(),
        'toolExecutions':
            toolExecutions.map((execution) => execution.toJson()).toList(),
      };
}

class FoodSearchResult {
  const FoodSearchResult({required this.items, this.candidateGroups});

  final List<MealItem> items;
  final List<FoodCandidateGroup>? candidateGroups;
}

class AgentChatProposalCommitResult {
  const AgentChatProposalCommitResult({
    required this.clientMutationId,
    required this.reused,
    required this.result,
    required this.conversationMessage,
  });

  final String clientMutationId;
  final bool reused;
  final AgentRunResult result;
  final AgentConversationMessage conversationMessage;

  String get sourceProposalId => result.sourceProposalId!;
  Meal get meal => result.meal!;
}

/// The response belongs to an authenticated cache owner that is no longer
/// active. Callers must silently discard it rather than mutating current UI.
class StaleNutritionResponseException implements Exception {
  const StaleNutritionResponseException();
}

class NutritionRepository {
  NutritionRepository({
    required CalTrackerApiClient apiClient,
    NutritionCacheStore? cacheStore,
    BackendHealthMonitor? healthMonitor,
    ClientTelemetryService? telemetryService,
    Duration backgroundRefreshCooldown = const Duration(seconds: 15),
    DateTime Function()? now,
  })  : _apiClient = apiClient,
        _cacheStore = cacheStore,
        _healthMonitor = healthMonitor ?? BackendHealthMonitor(now: now),
        _telemetryService = telemetryService,
        _backgroundRefreshCooldown = backgroundRefreshCooldown,
        _now = now ?? DateTime.now;

  final CalTrackerApiClient _apiClient;
  final NutritionCacheStore? _cacheStore;
  final BackendHealthMonitor _healthMonitor;
  final ClientTelemetryService? _telemetryService;
  final Duration _backgroundRefreshCooldown;
  final DateTime Function() _now;
  final Map<String, Future<DailySummary>> _dailySummaryRefreshes = {};
  final Map<String, DateTime> _dailySummaryRefreshStartedAt = {};
  final Map<String, Future<AgentChatProposalCommitResult>>
      _agentProposalCommits = {};
  final Set<String> _pendingDailySummaryRefreshes = {};
  Future<List<MealTemplate>>? _templatesRefresh;
  Future<List<UsualFood>>? _usualFoodsRefresh;
  DateTime? _templatesRefreshStartedAt;
  DateTime? _usualFoodsRefreshStartedAt;
  bool _pendingTemplatesRefresh = false;
  bool _pendingUsualFoodsRefresh = false;
  final StreamController<NutritionDataChange> _dataChanges =
      StreamController<NutritionDataChange>.broadcast();
  final LinkedHashSet<String> _seenMutationIds = LinkedHashSet<String>();
  final Map<String, Future<void>> _cacheMutationQueues = {};
  final Map<String, int> _cacheGenerations = {};
  String? _activeUserId;
  int _userEpoch = 0;
  int _localMutationCounter = 0;
  bool _isDisposed = false;

  bool get isBackendLikelyHealthy => _healthMonitor.isLikelyHealthy;
  Stream<NutritionDataChange> get dataChanges => _dataChanges.stream;

  void activateCacheForUser(String userId) {
    if (_activeUserId != userId) {
      _activeUserId = userId;
      _userEpoch++;
      _seenMutationIds.clear();
      _cacheMutationQueues.clear();
      _cacheGenerations.clear();
      _clearRefreshState();
    }
    _cacheStore?.activateUser(userId);
  }

  void deactivateCache() {
    _activeUserId = null;
    _userEpoch++;
    _seenMutationIds.clear();
    _cacheMutationQueues.clear();
    _cacheGenerations.clear();
    _clearRefreshState();
    _cacheStore?.deactivateUser();
  }

  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _clearRefreshState();
    await _dataChanges.close();
  }

  Future<void> clearActiveUserCache() async {
    await _cacheStore?.clearActiveUserCache();
  }

  Future<bool> checkBackendHealth() {
    return _healthMonitor.check(() async {
      final json = await _apiClient.getHealth();
      if (json['ok'] == false) {
        throw const ApiException(503, 'Backend is not healthy');
      }
    });
  }

  Future<CachedNutritionValue<DailySummary>?> cachedDailySummary({
    String? date,
  }) {
    final cacheStore = _cacheStore;
    if (cacheStore == null) {
      return Future.value();
    }
    return cacheStore.readDailySummary(_dateOnly(date));
  }

  Future<void> putCachedDailySummary(DailySummary summary) async {
    try {
      await _cacheStore?.writeDailySummary(summary);
    } on Object catch (error) {
      _recordCacheWriteFailure(
        cacheKey: 'daily_summary',
        operation: 'writeDailySummary',
        error: error,
      );
    }
  }

  Future<DailySummary> refreshDailySummary({String? date, bool force = false}) {
    final cacheStore = _cacheStore;
    final normalizedDate = _dateOnly(date);
    if (cacheStore == null) {
      return getDailySummary(date: normalizedDate);
    }

    final existing = _dailySummaryRefreshes[normalizedDate];
    if (existing != null) {
      if (force) _pendingDailySummaryRefreshes.add(normalizedDate);
      return existing;
    }

    final startedAt = _dailySummaryRefreshStartedAt[normalizedDate];
    if (!force && startedAt != null) {
      final isCoolingDown =
          _now().difference(startedAt) < _backgroundRefreshCooldown;
      if (isCoolingDown) {
        return cachedDailySummary(date: normalizedDate).then(
          (cached) =>
              cached?.value ??
              _refreshDailySummaryFromBackend(
                normalizedDate,
                generation:
                    _cacheGenerations['daily_summary:$normalizedDate'] ?? 0,
                scope: _captureScope(),
              ),
        );
      }
    }

    final refresh = _refreshDailySummaryFromBackend(
      normalizedDate,
      generation: _cacheGenerations['daily_summary:$normalizedDate'] ?? 0,
      scope: _captureScope(),
    );
    _dailySummaryRefreshStartedAt[normalizedDate] = _now();
    _dailySummaryRefreshes[normalizedDate] = refresh;
    refresh.then<void>(
      (_) => _finishDailySummaryRefresh(normalizedDate, refresh),
      onError: (_, __) => _finishDailySummaryRefresh(normalizedDate, refresh),
    );
    return refresh;
  }

  Future<CachedNutritionValue<List<MealTemplate>>?> cachedTemplates() {
    final cacheStore = _cacheStore;
    if (cacheStore == null) {
      return Future.value();
    }
    return cacheStore.readMealTemplates();
  }

  Future<void> putCachedTemplates(List<MealTemplate> templates) async {
    try {
      await _cacheStore?.writeMealTemplates(templates);
    } on Object catch (error) {
      _recordCacheWriteFailure(
        cacheKey: 'meal_templates',
        operation: 'writeMealTemplates',
        error: error,
      );
    }
  }

  Future<List<MealTemplate>> refreshTemplates({bool force = false}) {
    final cacheStore = _cacheStore;
    if (cacheStore == null) return getTemplates();

    final existing = _templatesRefresh;
    if (existing != null) {
      if (force) _pendingTemplatesRefresh = true;
      return existing;
    }
    final startedAt = _templatesRefreshStartedAt;
    if (!force && startedAt != null) {
      final isCoolingDown =
          _now().difference(startedAt) < _backgroundRefreshCooldown;
      if (isCoolingDown) {
        return cachedTemplates().then(
          (cached) =>
              cached?.value ??
              _refreshTemplatesFromBackend(
                generation: _cacheGenerations['meal_templates'] ?? 0,
                scope: _captureScope(),
              ),
        );
      }
    }

    final refresh = _refreshTemplatesFromBackend(
      generation: _cacheGenerations['meal_templates'] ?? 0,
      scope: _captureScope(),
    );
    _templatesRefreshStartedAt = _now();
    _templatesRefresh = refresh;
    refresh.then<void>(
      (_) => _finishTemplatesRefresh(refresh),
      onError: (_, __) => _finishTemplatesRefresh(refresh),
    );
    return refresh;
  }

  Future<CachedNutritionValue<List<UsualFood>>?> cachedUsualFoods() {
    final cacheStore = _cacheStore;
    if (cacheStore == null) {
      return Future.value();
    }
    return cacheStore.readUsualFoods();
  }

  Future<void> putCachedUsualFoods(List<UsualFood> foods) async {
    try {
      await _cacheStore?.writeUsualFoods(foods);
    } on Object catch (error) {
      _recordCacheWriteFailure(
        cacheKey: 'usual_foods',
        operation: 'writeUsualFoods',
        error: error,
      );
    }
  }

  Future<List<UsualFood>> refreshUsualFoods({bool force = false}) {
    final cacheStore = _cacheStore;
    if (cacheStore == null) return getUsualFoods();

    final existing = _usualFoodsRefresh;
    if (existing != null) {
      if (force) _pendingUsualFoodsRefresh = true;
      return existing;
    }
    final startedAt = _usualFoodsRefreshStartedAt;
    if (!force && startedAt != null) {
      final isCoolingDown =
          _now().difference(startedAt) < _backgroundRefreshCooldown;
      if (isCoolingDown) {
        return cachedUsualFoods().then(
          (cached) =>
              cached?.value ??
              _refreshUsualFoodsFromBackend(
                generation: _cacheGenerations['usual_foods'] ?? 0,
                scope: _captureScope(),
              ),
        );
      }
    }

    final refresh = _refreshUsualFoodsFromBackend(
      generation: _cacheGenerations['usual_foods'] ?? 0,
      scope: _captureScope(),
    );
    _usualFoodsRefreshStartedAt = _now();
    _usualFoodsRefresh = refresh;
    refresh.then<void>(
      (_) => _finishUsualFoodsRefresh(refresh),
      onError: (_, __) => _finishUsualFoodsRefresh(refresh),
    );
    return refresh;
  }

  Future<AgentRunResult> logText(
    String text, {
    String? activeProposalId,
  }) async {
    final scope = _captureScope();
    final json = activeProposalId == null
        ? await _apiClient.runAgent(text)
        : await _apiClient.runAgent(text, activeProposalId: activeProposalId);
    _healthMonitor.recordSuccess();
    final result = agentRunResultFromJson(json);
    await _cacheAgentResult(result, expectedScope: scope);
    return result;
  }

  Future<VoiceMealRunResult> logAudio(
    File audioFile, {
    String? activeProposalId,
  }) async {
    final scope = _captureScope();
    final json = activeProposalId == null
        ? await _apiClient.runVoiceMeal(audioFile, source: 'flutter')
        : await _apiClient.runVoiceMeal(
            audioFile,
            source: 'flutter',
            activeProposalId: activeProposalId,
          );
    _healthMonitor.recordSuccess();
    final result =
        agentRunResultFromJson(json['result'] as Map<String, Object?>);
    await _cacheAgentResult(result, expectedScope: scope);
    return VoiceMealRunResult(
      transcript: json['transcript'] as String,
      provider: json['provider'] as String,
      model: json['model'] as String,
      traceId: json['traceId'] as String,
      result: result,
    );
  }

  Stream<AgentChatStreamEvent> streamAgentChat(
    String message, {
    String? conversationId,
    String? activeProposalId,
  }) async* {
    final scope = _captureScope();
    await for (final json in _apiClient.streamAgentChat(
      message,
      conversationId: conversationId,
      activeProposalId: activeProposalId,
    )) {
      final event = _parseAgentChatStreamEvent(json);
      final result = event.result;
      if (result != null) {
        await _cacheAgentResult(result, expectedScope: scope);
      }
      yield event;
    }
    _healthMonitor.recordSuccess();
  }

  Stream<AgentChatStreamEvent> streamAgentChatAudio(
    File audioFile, {
    String? conversationId,
    String? activeProposalId,
  }) async* {
    final scope = _captureScope();
    await for (final json in _apiClient.streamAgentChatAudio(
      audioFile,
      conversationId: conversationId,
      activeProposalId: activeProposalId,
    )) {
      final event = _parseAgentChatStreamEvent(json);
      final result = event.result;
      if (result != null) {
        await _cacheAgentResult(result, expectedScope: scope);
      }
      yield event;
    }
    _healthMonitor.recordSuccess();
  }

  Future<List<AgentConversationSummary>> listAgentConversations() async {
    final json = await _apiClient.listAgentConversations();
    _healthMonitor.recordSuccess();
    return (json['conversations'] as List<Object?>? ?? const [])
        .cast<Map<String, Object?>>()
        .map(AgentConversationSummary.fromJson)
        .toList();
  }

  Future<AgentConversationDetail> getAgentConversation(
    String conversationId,
  ) async {
    final json = await _apiClient.getAgentConversation(conversationId);
    _healthMonitor.recordSuccess();
    return _parseAgentConversationDetail(json, conversationId: conversationId);
  }

  Future<AgentChatProposalCommitResult> commitAgentChatProposal({
    required String conversationId,
    required String proposalId,
    required String sourceToolCallId,
    required String clientMutationId,
  }) {
    final scope = _captureScope();
    final operationKey =
        '${scope.userId ?? '<signed-out>'}:$proposalId:$clientMutationId';
    final existing = _agentProposalCommits[operationKey];
    if (existing != null) return existing;
    final request = _commitAgentChatProposal(
      conversationId: conversationId,
      proposalId: proposalId,
      sourceToolCallId: sourceToolCallId,
      clientMutationId: clientMutationId,
      expectedScope: scope,
    );
    late final Future<AgentChatProposalCommitResult> future;
    void removeIfCurrent() {
      if (identical(_agentProposalCommits[operationKey], future)) {
        _agentProposalCommits.remove(operationKey);
      }
    }

    future = request.then<AgentChatProposalCommitResult>(
      (result) {
        removeIfCurrent();
        return result;
      },
      onError: (Object error, StackTrace stackTrace) {
        removeIfCurrent();
        return Future<AgentChatProposalCommitResult>.error(error, stackTrace);
      },
    );
    _agentProposalCommits[operationKey] = future;
    return future;
  }

  Future<AgentChatProposalCommitResult> _commitAgentChatProposal({
    required String conversationId,
    required String proposalId,
    required String sourceToolCallId,
    required String clientMutationId,
    required _RepositoryScope expectedScope,
  }) async {
    final json = await _apiClient.commitAgentChatProposal(
      conversationId: conversationId,
      proposalId: proposalId,
      sourceToolCallId: sourceToolCallId,
      clientMutationId: clientMutationId,
    );
    _healthMonitor.recordSuccess();
    if (!_isScopeCurrent(expectedScope)) {
      throw const StaleNutritionResponseException();
    }
    final result = agentRunResultFromJson(
      json['result'] as Map<String, Object?>,
    );
    if (result.kind != 'meal_committed' ||
        result.meal == null ||
        result.sourceProposalId == null ||
        result.confirmedMutation == null) {
      throw const ApiException(502, 'Invalid direct commit response.');
    }
    // Reconciliation writes the authoritative snapshot through the active
    // user's cache before publishing the granular data-change event.
    await reconcileConfirmedMutation(result.confirmedMutation!);
    if (!_isScopeCurrent(expectedScope)) {
      throw const StaleNutritionResponseException();
    }
    return AgentChatProposalCommitResult(
      clientMutationId: json['clientMutationId'] as String? ?? clientMutationId,
      reused: json['reused'] as bool? ?? false,
      result: result,
      conversationMessage: AgentConversationMessage.fromJson(
        json['conversationMessage'] as Map<String, Object?>,
      ),
    );
  }

  Future<void> deleteAgentConversation(String conversationId) async {
    final json = await _apiClient.deleteAgentConversation(conversationId);
    _healthMonitor.recordSuccess();
    final ok =
        json['ok'] == true || json['deleted'] == true || json['hidden'] == true;
    if (!ok) {
      throw const ApiException(404, 'Conversation was not found.');
    }
  }

  Future<FoodSearchResult> searchFoods(
    String query, {
    int limit = 10,
    String? barcode,
  }) async {
    final stopwatch = Stopwatch()..start();
    String? requestId;
    try {
      final response = await _apiClient.searchFoodsWithRequestId(
        query: query,
        barcode: barcode,
        limit: limit,
      );
      requestId = response.requestId;
      final json = response.body;
      _healthMonitor.recordSuccess();
      stopwatch.stop();
      final result = FoodSearchResult(
        items: (json['items'] as List<Object?>? ?? const [])
            .cast<Map<String, Object?>>()
            .map(MealItem.fromJson)
            .toList(),
        candidateGroups: _parseCandidateGroups(json['candidateGroups']),
      );
      _recordFoodSearchResult(
        query: query,
        barcode: barcode,
        limit: limit,
        result: result,
        duration: stopwatch.elapsed,
        requestId: requestId,
        status: 'success',
      );
      return result;
    } on Object catch (error) {
      stopwatch.stop();
      _recordFoodSearchResult(
        query: query,
        barcode: barcode,
        limit: limit,
        result: const FoodSearchResult(items: []),
        duration: stopwatch.elapsed,
        requestId:
            error is ApiException ? error.traceId ?? requestId : requestId,
        status: 'failure',
        error: error,
      );
      rethrow;
    }
  }

  AgentChatStreamEvent _parseAgentChatStreamEvent(
    Map<String, Object?> json,
  ) {
    final toolCallJson = json['toolCall'];
    final resultJson = json['result'];
    final suggestionsJson = json['suggestions'];
    final execution = AgentToolExecutionSnapshot.tryFromJson(json['execution']);
    AgentRunResult? directResult;
    if (resultJson is Map<String, Object?>) {
      try {
        directResult = agentRunResultFromJson(resultJson);
      } on Object {
        directResult = null;
      }
    }
    return AgentChatStreamEvent(
      type: json['type'] as String? ?? 'unknown',
      conversationId: json['conversationId'] as String?,
      message: json['message'] as String?,
      delta: json['delta'] as String?,
      transcript: json['transcript'] as String?,
      error: execution?.error ??
          (json['error'] is Map<String, Object?>
              ? ApiErrorDetails.fromJson(json['error'] as Map<String, Object?>)
              : null),
      toolCall: execution?.toolCall ??
          (toolCallJson is Map<String, Object?>
              ? AgentToolCallFeedback.fromJson(toolCallJson)
              : null),
      result: execution?.result ?? directResult,
      widget: execution?.widget ?? json['widget'],
      execution: execution,
      suggestions: suggestionsJson is List<Object?>
          ? suggestionsJson
              .whereType<Map<String, Object?>>()
              .map(AgentChatSuggestion.fromJson)
              .where((suggestion) =>
                  suggestion.label.isNotEmpty && suggestion.value.isNotEmpty)
              .toList()
          : const [],
    );
  }

  Future<Meal> commitProposal(String proposalId, {MealLabel? mealLabel}) async {
    final scope = _captureScope();
    final json = await _apiClient.commitProposal(
      proposalId,
      mealLabel: mealLabel,
    );
    _healthMonitor.recordSuccess();
    final output = json['output'] as Map<String, Object?>;
    final meal = Meal.fromJson(output['meal'] as Map<String, Object?>);
    await _reconcileResponseMutation(json, expectedScope: scope);
    await _mergeMealIntoCachedSummary(meal, expectedScope: scope);
    return meal;
  }

  Future<Meal> correctMealItems(String mealId, List<MealItem> items) async {
    final scope = _captureScope();
    final json = await _apiClient.correctMeal(
      mealId,
      items.map((item) => item.toJson()).toList(),
    );
    _healthMonitor.recordSuccess();
    final output = json['output'] as Map<String, Object?>;
    final meal = Meal.fromJson(output['meal'] as Map<String, Object?>);
    await _reconcileResponseMutation(json, expectedScope: scope);
    await _mergeMealIntoCachedSummary(meal, expectedScope: scope);
    return meal;
  }

  Future<MealProposal> updateProposalItems(
    String proposalId,
    List<MealItem> items,
  ) async {
    final json = await _apiClient.correctProposal(
      proposalId: proposalId,
      items: items.map((item) => item.toJson()).toList(),
    );
    _healthMonitor.recordSuccess();
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
    _healthMonitor.recordSuccess();
    final output = json['output'] as Map<String, Object?>;
    return MealProposal.fromJson(output['proposal'] as Map<String, Object?>);
  }

  Future<bool> deleteMeal(String mealId, {bool confirmed = false}) async {
    final scope = _captureScope();
    final json = await _apiClient.deleteMeal(mealId, confirmed: confirmed);
    _healthMonitor.recordSuccess();
    await _reconcileResponseMutation(json, expectedScope: scope);
    final output = json['output'] as Map<String, Object?>;
    return output['deleted'] as bool? ?? false;
  }

  Future<DailySummary> getDailySummary({String? date}) async {
    return _fetchDailySummaryFromBackend(_dateOnly(date));
  }

  Future<DailySummary> _refreshDailySummaryFromBackend(
    String date, {
    required int generation,
    required _RepositoryScope scope,
  }) async {
    final summary = await _fetchDailySummaryFromBackend(date);
    if (_isScopeCurrent(scope) &&
        (_cacheGenerations['daily_summary:$date'] ?? 0) == generation) {
      await putCachedDailySummary(summary);
    }
    return summary;
  }

  Future<DailySummary> _fetchDailySummaryFromBackend(String date) async {
    final json = await _apiClient.getDailySummary(date: date);
    _healthMonitor.recordSuccess();
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
    final scope = _captureScope();
    final json = await _apiClient.updateDailyGoals(
      date: _dateOnly(date),
      calories: calories,
      hydrationGoalLiters: hydrationGoalLiters,
      calorieTargetSource: calorieTargetSource,
      macroFields: macroConfig?.toApiJson(calories: macroTargetCalories),
    );
    _healthMonitor.recordSuccess();
    final goals = DailyGoals.fromJson(json['goals'] as Map<String, Object?>);
    final summaryJson = json['summary'];
    final summary = summaryJson is Map<String, Object?>
        ? DailySummary.fromJson(summaryJson)
        : null;
    await _publishLocalEffects(
      [
        NutritionDataEffect(
          domain: NutritionDataDomain.dailyGoals,
          operation: NutritionDataOperation.replace,
          date: goals.date,
          snapshot: goals.toJson(),
        ),
        if (summary != null)
          NutritionDataEffect(
            domain: NutritionDataDomain.dailySummary,
            operation: NutritionDataOperation.replace,
            date: summary.date,
            snapshot: summary.toJson(),
          ),
      ],
      expectedScope: scope,
    );
    await _mergeGoalsIntoCachedSummary(goals, expectedScope: scope);
    return goals;
  }

  Future<DailySummary> updateDailyHydration({
    String? date,
    required double waterConsumedLiters,
  }) async {
    final scope = _captureScope();
    final json = await _apiClient.updateDailyHydration(
      date: _dateOnly(date),
      waterConsumedLiters: waterConsumedLiters,
    );
    _healthMonitor.recordSuccess();
    final summary = DailySummary.fromJson(
      json['summary'] as Map<String, Object?>,
    );
    await _publishLocalEffect(
      NutritionDataEffect(
        domain: NutritionDataDomain.dailySummary,
        operation: NutritionDataOperation.replace,
        date: summary.date,
        snapshot: summary.toJson(),
      ),
      expectedScope: scope,
    );
    return summary;
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
    _healthMonitor.recordSuccess();
    return CalorieEstimate.fromJson(json);
  }

  Future<List<Meal>> getMealHistory() async {
    final json = await _apiClient.getMealHistory();
    _healthMonitor.recordSuccess();
    final output = json['output'] as Map<String, Object?>;
    return (output['meals'] as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(Meal.fromJson)
        .toList();
  }

  Future<List<MealTemplate>> getTemplates() async {
    return _fetchTemplatesFromBackend();
  }

  Future<List<MealTemplate>> _refreshTemplatesFromBackend({
    required int generation,
    required _RepositoryScope scope,
  }) async {
    final templates = await _fetchTemplatesFromBackend();
    if (_isScopeCurrent(scope) &&
        (_cacheGenerations['meal_templates'] ?? 0) == generation) {
      await putCachedTemplates(templates);
    }
    return templates;
  }

  Future<List<MealTemplate>> _fetchTemplatesFromBackend() async {
    final json = await _apiClient.getTemplates();
    _healthMonitor.recordSuccess();
    final output = json['output'] as Map<String, Object?>;
    return (output['templates'] as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(MealTemplate.fromJson)
        .toList();
  }

  Future<List<UsualFood>> getUsualFoods() async {
    return _fetchUsualFoodsFromBackend();
  }

  Future<List<UsualFood>> _refreshUsualFoodsFromBackend({
    required int generation,
    required _RepositoryScope scope,
  }) async {
    final foods = await _fetchUsualFoodsFromBackend();
    if (_isScopeCurrent(scope) &&
        (_cacheGenerations['usual_foods'] ?? 0) == generation) {
      await putCachedUsualFoods(foods);
    }
    return foods;
  }

  Future<List<UsualFood>> _fetchUsualFoodsFromBackend() async {
    final json = await _apiClient.getUsualFoods();
    _healthMonitor.recordSuccess();
    final output = _responseOutput(json);
    final foods = output['usualFoods'] ?? output['foods'] ?? output['items'];
    return (foods as List<Object?>? ?? const [])
        .cast<Map<String, Object?>>()
        .map(UsualFood.fromJson)
        .toList();
  }

  Future<MealTemplate> setTemplateTrustedMode(
    MealTemplate template,
    bool enabled,
  ) async {
    final scope = _captureScope();
    final body = template.toUpdateJson()
      ..['trustedAutoCommitEnabled'] = enabled;
    final json = await _apiClient.updateTemplate(template.id, body);
    _healthMonitor.recordSuccess();
    final output = json['output'] as Map<String, Object?>;
    final updated = MealTemplate.fromJson(
      output['template'] as Map<String, Object?>,
    );
    await _reconcileResponseMutation(json, expectedScope: scope);
    await _replaceCachedTemplate(updated, expectedScope: scope);
    return updated;
  }

  Future<MealTemplate> createTemplate({
    required String title,
    required List<MealItem> items,
    required List<String> aliases,
    bool trustedAutoCommitEnabled = false,
  }) async {
    final scope = _captureScope();
    final json = await _apiClient.createTemplate({
      'title': title,
      'trustedAutoCommitEnabled': trustedAutoCommitEnabled,
      'items': items.map((item) => item.toJson()).toList(),
      'aliases': aliases,
    });
    _healthMonitor.recordSuccess();
    final output = json['output'] as Map<String, Object?>;
    final template = MealTemplate.fromJson(
      output['template'] as Map<String, Object?>,
    );
    await _reconcileResponseMutation(json, expectedScope: scope);
    await _appendCachedTemplate(template, expectedScope: scope);
    return template;
  }

  Future<MealTemplate> updateTemplate({
    required String templateId,
    required String title,
    required List<MealItem> items,
    required List<String> aliases,
    bool trustedAutoCommitEnabled = false,
  }) async {
    final scope = _captureScope();
    final json = await _apiClient.updateTemplate(templateId, {
      'title': title,
      'trustedAutoCommitEnabled': trustedAutoCommitEnabled,
      'items': items.map((item) => item.toJson()).toList(),
      'aliases': aliases,
    });
    _healthMonitor.recordSuccess();
    final output = json['output'] as Map<String, Object?>;
    final template = MealTemplate.fromJson(
      output['template'] as Map<String, Object?>,
    );
    await _reconcileResponseMutation(json, expectedScope: scope);
    await _replaceCachedTemplate(template, expectedScope: scope);
    return template;
  }

  Future<UsualMealDraft> draftUsualMeal(String text) async {
    Map<String, Object?> json;
    try {
      json = await _apiClient.draftUsualMeal(text);
    } on ApiException catch (error) {
      if (error.statusCode != 404 && error.code != 'unimplemented_action') {
        rethrow;
      }
      json = await _apiClient.executeAction('draft_usual_meal', {'text': text});
    }
    _healthMonitor.recordSuccess();
    return UsualMealDraft.fromJson(_responseOutput(json));
  }

  Future<UsualFood> createUsualFood(UsualFoodInput input) async {
    final scope = _captureScope();
    final json = await _apiClient.createUsualFood(input.toJson());
    _healthMonitor.recordSuccess();
    final food = _parseUsualFoodResponse(json);
    await _reconcileResponseMutation(json, expectedScope: scope);
    await _appendCachedUsualFood(food, expectedScope: scope);
    return food;
  }

  Future<UsualFood> updateUsualFood(String foodId, UsualFoodInput input) async {
    final scope = _captureScope();
    final json = await _apiClient.updateUsualFood(
      foodId,
      input.toJson(includeEmptyOptional: true),
    );
    _healthMonitor.recordSuccess();
    final food = _parseUsualFoodResponse(json);
    await _reconcileResponseMutation(json, expectedScope: scope);
    await _replaceCachedUsualFood(food, expectedScope: scope);
    return food;
  }

  Future<bool> deleteUsualFood(String foodId) async {
    final scope = _captureScope();
    final json = await _apiClient.deleteUsualFood(foodId);
    _healthMonitor.recordSuccess();
    await _reconcileResponseMutation(json, expectedScope: scope);
    final output = _responseOutput(json);
    final deleted = output['deleted'] as bool? ?? true;
    if (deleted) {
      await _removeCachedUsualFood(foodId, expectedScope: scope);
    }
    return deleted;
  }

  Future<UsualFoodDraft> draftUsualFood(String text) async {
    final json = await _apiClient.draftUsualFood(text);
    _healthMonitor.recordSuccess();
    final output = _responseOutput(json);
    return UsualFoodDraft.fromJson(output['draft'] as Map<String, Object?>);
  }

  Future<bool> deleteTemplate(String templateId) async {
    final scope = _captureScope();
    final json = await _apiClient.deleteTemplate(templateId);
    _healthMonitor.recordSuccess();
    await _reconcileResponseMutation(json, expectedScope: scope);
    final output = json['output'] as Map<String, Object?>;
    final deleted = output['deleted'] as bool? ?? false;
    if (deleted) {
      await _removeCachedTemplate(templateId, expectedScope: scope);
    }
    return deleted;
  }

  Future<String> transcribeAudio(File audioFile) async {
    final json = await _apiClient.transcribeAudio(audioFile, source: 'flutter');
    _healthMonitor.recordSuccess();
    return json['transcript'] as String;
  }

  Future<void> _reconcileResponseMutation(
    Map<String, Object?> response, {
    required _RepositoryScope expectedScope,
  }) async {
    if (!_isScopeCurrent(expectedScope)) return;
    final mutation = ConfirmedNutritionMutation.tryParse(
      response['confirmedMutation'],
    );
    if (mutation != null && _isScopeCurrent(expectedScope)) {
      await reconcileConfirmedMutation(mutation);
    }
  }

  Future<void> _publishLocalEffect(
    NutritionDataEffect effect, {
    required _RepositoryScope expectedScope,
  }) =>
      _publishLocalEffects([effect], expectedScope: expectedScope);

  Future<void> _publishLocalEffects(
    List<NutritionDataEffect> effects, {
    required _RepositoryScope expectedScope,
  }) {
    if (!_isScopeCurrent(expectedScope)) return Future.value();
    return reconcileConfirmedMutation(
      ConfirmedNutritionMutation(
        version: 1,
        // Deterministic API endpoints that predate the envelope still share
        // the same local reconciliation path after their response succeeds.
        mutationId:
            'local-${_now().microsecondsSinceEpoch}-${++_localMutationCounter}',
        committedAt: _now().toUtc(),
        effects: effects,
      ),
    );
  }

  /// Reconciles a server-confirmed mutation before notifying any ViewModel.
  /// The active cache owner is captured locally; agent payloads never choose a
  /// user scope and stale account work is ignored after logout/account switch.
  Future<void> reconcileConfirmedMutation(
    ConfirmedNutritionMutation mutation,
  ) async {
    final userId = _activeUserId;
    final epoch = _userEpoch;
    if (userId == null || _isDisposed || mutation.effects.isEmpty) return;
    if (_seenMutationIds.contains(mutation.mutationId)) return;
    _seenMutationIds.add(mutation.mutationId);
    while (_seenMutationIds.length > 100) {
      _seenMutationIds.remove(_seenMutationIds.first);
    }

    for (final effect in mutation.effects) {
      if (!_isCurrentScope(userId, epoch)) return;
      await _queueCacheMutation(
        _cacheKeyForEffect(effect),
        () => _reconcileEffect(effect, userId: userId, epoch: epoch),
      );
    }
    if (_isCurrentScope(userId, epoch) && !_dataChanges.isClosed) {
      _dataChanges.add(NutritionDataChange(userId: userId, mutation: mutation));
    }
  }

  Future<void> _reconcileEffect(
    NutritionDataEffect effect, {
    required String userId,
    required int epoch,
  }) async {
    if (!_isCurrentScope(userId, epoch)) return;
    final cacheStore = _cacheStore;
    switch (effect.domain) {
      case NutritionDataDomain.dailySummary:
        final date = effect.date!;
        _invalidateCacheKey('daily_summary:$date');
        final summary = effect.dailySummary;
        if (summary != null && summary.date == date) {
          if (_isCurrentScope(userId, epoch)) {
            await putCachedDailySummary(summary);
          }
        } else {
          await cacheStore?.markDailySummaryStale(date);
          _refreshAffectedDailySummary(date, userId, epoch);
        }
      case NutritionDataDomain.dailyGoals:
        final date = effect.date ?? effect.dailyGoals?.date;
        final goals = effect.dailyGoals;
        if (date == null || goals == null) return;
        _invalidateCacheKey('daily_summary:$date');
        final cached = await cachedDailySummary(date: date);
        if (!_isCurrentScope(userId, epoch)) return;
        if (cached != null) {
          await putCachedDailySummary(
              dailySummaryWithGoals(cached.value, goals));
        } else {
          await cacheStore?.markDailySummaryStale(date);
          _refreshAffectedDailySummary(date, userId, epoch);
        }
      case NutritionDataDomain.mealTemplates:
        _invalidateCacheKey('meal_templates');
        final template = effect.mealTemplate;
        if (effect.operation == NutritionDataOperation.invalidate ||
            (effect.operation != NutritionDataOperation.delete &&
                template == null)) {
          await cacheStore?.markMealTemplatesStale();
          _refreshAffectedTemplates(userId, epoch);
          return;
        }
        final cached = await cachedTemplates();
        if (!_isCurrentScope(userId, epoch)) return;
        if (cached == null) {
          await cacheStore?.markMealTemplatesStale();
          _refreshAffectedTemplates(userId, epoch);
          return;
        }
        final id = effect.entityId!;
        final next = effect.operation == NutritionDataOperation.delete
            ? cached.value.where((item) => item.id != id).toList()
            : _upsertById(cached.value, template!, (item) => item.id);
        await putCachedTemplates(next);
      case NutritionDataDomain.usualFoods:
        _invalidateCacheKey('usual_foods');
        final food = effect.usualFood;
        if (effect.operation == NutritionDataOperation.invalidate ||
            (effect.operation != NutritionDataOperation.delete &&
                food == null)) {
          await cacheStore?.markUsualFoodsStale();
          _refreshAffectedUsualFoods(userId, epoch);
          return;
        }
        final cached = await cachedUsualFoods();
        if (!_isCurrentScope(userId, epoch)) return;
        if (cached == null) {
          await cacheStore?.markUsualFoodsStale();
          _refreshAffectedUsualFoods(userId, epoch);
          return;
        }
        final id = effect.entityId!;
        final next = effect.operation == NutritionDataOperation.delete
            ? cached.value.where((item) => item.id != id).toList()
            : _upsertById(cached.value, food!, (item) => item.id);
        await putCachedUsualFoods(next);
    }
  }

  Future<void> _queueCacheMutation(
    String key,
    Future<void> Function() operation,
  ) {
    final previous = _cacheMutationQueues[key] ?? Future<void>.value();
    final next = previous.catchError((_) {}).then((_) => operation());
    _cacheMutationQueues[key] = next;
    return next.whenComplete(() {
      if (identical(_cacheMutationQueues[key], next)) {
        _cacheMutationQueues.remove(key);
      }
    });
  }

  _RepositoryScope _captureScope() =>
      _RepositoryScope(userId: _activeUserId, epoch: _userEpoch);

  bool _isScopeCurrent(_RepositoryScope scope) =>
      !_isDisposed &&
      _activeUserId == scope.userId &&
      _userEpoch == scope.epoch;

  bool _isCurrentScope(String userId, int epoch) =>
      _isScopeCurrent(_RepositoryScope(userId: userId, epoch: epoch));

  void _clearRefreshState() {
    _dailySummaryRefreshes.clear();
    _dailySummaryRefreshStartedAt.clear();
    _pendingDailySummaryRefreshes.clear();
    _templatesRefresh = null;
    _usualFoodsRefresh = null;
    _templatesRefreshStartedAt = null;
    _usualFoodsRefreshStartedAt = null;
    _pendingTemplatesRefresh = false;
    _pendingUsualFoodsRefresh = false;
  }

  void _finishDailySummaryRefresh(
    String date,
    Future<DailySummary> refresh,
  ) {
    if (!identical(_dailySummaryRefreshes[date], refresh)) return;
    _dailySummaryRefreshes.remove(date);
    final userId = _activeUserId;
    if (_pendingDailySummaryRefreshes.remove(date) && userId != null) {
      _refreshAffectedDailySummary(date, userId, _userEpoch);
    }
  }

  void _finishTemplatesRefresh(Future<List<MealTemplate>> refresh) {
    if (!identical(_templatesRefresh, refresh)) return;
    _templatesRefresh = null;
    final userId = _activeUserId;
    final needsRefresh = _pendingTemplatesRefresh;
    _pendingTemplatesRefresh = false;
    if (needsRefresh && userId != null) {
      _refreshAffectedTemplates(userId, _userEpoch);
    }
  }

  void _finishUsualFoodsRefresh(Future<List<UsualFood>> refresh) {
    if (!identical(_usualFoodsRefresh, refresh)) return;
    _usualFoodsRefresh = null;
    final userId = _activeUserId;
    final needsRefresh = _pendingUsualFoodsRefresh;
    _pendingUsualFoodsRefresh = false;
    if (needsRefresh && userId != null) {
      _refreshAffectedUsualFoods(userId, _userEpoch);
    }
  }

  String _cacheKeyForEffect(NutritionDataEffect effect) =>
      switch (effect.domain) {
        NutritionDataDomain.dailySummary ||
        NutritionDataDomain.dailyGoals =>
          'daily_summary:${effect.date ?? effect.dailyGoals?.date ?? ''}',
        NutritionDataDomain.mealTemplates => 'meal_templates',
        NutritionDataDomain.usualFoods => 'usual_foods',
      };

  void _invalidateCacheKey(String key) {
    _cacheGenerations[key] = (_cacheGenerations[key] ?? 0) + 1;
  }

  void _refreshAffectedDailySummary(String date, String userId, int epoch) {
    if (!_isCurrentScope(userId, epoch)) return;
    unawaited(() async {
      try {
        await refreshDailySummary(date: date, force: true);
      } on Object {
        // Cached data remains visible and marked stale after a background miss.
      }
    }());
  }

  void _refreshAffectedTemplates(String userId, int epoch) {
    if (!_isCurrentScope(userId, epoch)) return;
    unawaited(() async {
      try {
        await refreshTemplates(force: true);
      } on Object {
        // Keep the stale, still-renderable cache value on background failure.
      }
    }());
  }

  void _refreshAffectedUsualFoods(String userId, int epoch) {
    if (!_isCurrentScope(userId, epoch)) return;
    unawaited(() async {
      try {
        await refreshUsualFoods(force: true);
      } on Object {
        // Keep the stale, still-renderable cache value on background failure.
      }
    }());
  }

  Future<void> _cacheAgentResult(
    AgentRunResult result, {
    required _RepositoryScope expectedScope,
  }) async {
    if (!_isScopeCurrent(expectedScope)) return;
    final mutation = result.confirmedMutation;
    if (mutation != null) {
      await reconcileConfirmedMutation(mutation);
      if (!_isScopeCurrent(expectedScope)) return;
    }
    final summary = result.summary;
    if (summary != null && _isScopeCurrent(expectedScope)) {
      await putCachedDailySummary(summary);
    }
    final meal = result.meal;
    if (meal != null) {
      await _mergeMealIntoCachedSummary(meal, expectedScope: expectedScope);
    }
    final meals = result.meals;
    if (meals != null) {
      for (final meal in meals) {
        await _mergeMealIntoCachedSummary(meal, expectedScope: expectedScope);
        if (!_isScopeCurrent(expectedScope)) return;
      }
    }
    final templates = result.templates;
    if (templates != null && _isScopeCurrent(expectedScope)) {
      await putCachedTemplates(templates);
    }
    final usualFoods = result.usualFoods;
    if (usualFoods != null && _isScopeCurrent(expectedScope)) {
      await putCachedUsualFoods(usualFoods);
    }
    final template = result.template;
    if (template != null) {
      await _replaceCachedTemplate(template, expectedScope: expectedScope);
    }
  }

  Future<void> _mergeMealIntoCachedSummary(
    Meal meal, {
    required _RepositoryScope expectedScope,
  }) async {
    if (!_isScopeCurrent(expectedScope)) return;
    final cached = await cachedDailySummary(
      date: _dateFromDateTime(meal.occurredAt),
    );
    if (cached == null || !_isScopeCurrent(expectedScope)) return;
    final existingMeals = cached.value.meals;
    final hasMeal = existingMeals.any((item) => item.id == meal.id);
    final meals = hasMeal
        ? existingMeals.map((item) => item.id == meal.id ? meal : item).toList()
        : [...existingMeals, meal];
    await putCachedDailySummary(dailySummaryWithMeals(cached.value, meals));
  }

  Future<void> _mergeGoalsIntoCachedSummary(
    DailyGoals goals, {
    required _RepositoryScope expectedScope,
  }) async {
    if (!_isScopeCurrent(expectedScope)) return;
    final cached = await cachedDailySummary(date: goals.date);
    if (cached == null || !_isScopeCurrent(expectedScope)) return;
    await putCachedDailySummary(dailySummaryWithGoals(cached.value, goals));
  }

  Future<void> _appendCachedTemplate(
    MealTemplate template, {
    required _RepositoryScope expectedScope,
  }) async {
    if (!_isScopeCurrent(expectedScope)) return;
    final cached = await cachedTemplates();
    if (cached == null || !_isScopeCurrent(expectedScope)) return;
    await putCachedTemplates([...cached.value, template]);
  }

  Future<void> _replaceCachedTemplate(
    MealTemplate template, {
    required _RepositoryScope expectedScope,
  }) async {
    if (!_isScopeCurrent(expectedScope)) return;
    final cached = await cachedTemplates();
    if (cached == null || !_isScopeCurrent(expectedScope)) return;
    final hasTemplate = cached.value.any((item) => item.id == template.id);
    final templates = hasTemplate
        ? cached.value
            .map((item) => item.id == template.id ? template : item)
            .toList()
        : [...cached.value, template];
    await putCachedTemplates(templates);
  }

  Future<void> _removeCachedTemplate(
    String templateId, {
    required _RepositoryScope expectedScope,
  }) async {
    if (!_isScopeCurrent(expectedScope)) return;
    final cached = await cachedTemplates();
    if (cached == null || !_isScopeCurrent(expectedScope)) return;
    await putCachedTemplates(
      cached.value.where((item) => item.id != templateId).toList(),
    );
  }

  Future<void> _appendCachedUsualFood(
    UsualFood food, {
    required _RepositoryScope expectedScope,
  }) async {
    if (!_isScopeCurrent(expectedScope)) return;
    final cached = await cachedUsualFoods();
    if (cached == null || !_isScopeCurrent(expectedScope)) return;
    await putCachedUsualFoods([...cached.value, food]);
  }

  Future<void> _replaceCachedUsualFood(
    UsualFood food, {
    required _RepositoryScope expectedScope,
  }) async {
    if (!_isScopeCurrent(expectedScope)) return;
    final cached = await cachedUsualFoods();
    if (cached == null || !_isScopeCurrent(expectedScope)) return;
    final hasFood = cached.value.any((item) => item.id == food.id);
    final foods = hasFood
        ? cached.value.map((item) => item.id == food.id ? food : item).toList()
        : [...cached.value, food];
    await putCachedUsualFoods(foods);
  }

  Future<void> _removeCachedUsualFood(
    String foodId, {
    required _RepositoryScope expectedScope,
  }) async {
    if (!_isScopeCurrent(expectedScope)) return;
    final cached = await cachedUsualFoods();
    if (cached == null || !_isScopeCurrent(expectedScope)) return;
    await putCachedUsualFoods(
      cached.value.where((item) => item.id != foodId).toList(),
    );
  }

  String _dateOnly(String? date) => date ?? _dateFromDateTime(_now());

  String _dateFromDateTime(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  void _recordCacheWriteFailure({
    required String cacheKey,
    required String operation,
    required Object error,
  }) {
    final telemetry = _telemetryService;
    if (telemetry == null) return;
    telemetry.record(
      ClientTelemetryEvent(
        eventType: 'mobile.cache_write_failed',
        flow: 'nutrition_cache',
        surface: 'mobile',
        severity: 'warning',
        status: 'failure',
        route: '/v1/nutrition/cache/$cacheKey',
        method: 'cache_write',
        durationMs: null,
        errorCode: error.runtimeType.toString(),
        errorMessage: error.toString(),
        metadata: <String, Object?>{
          'cacheKey': cacheKey,
          'operation': operation,
        },
      ),
    );
  }

  void _recordFoodSearchResult({
    required String query,
    required String? barcode,
    required int limit,
    required FoodSearchResult result,
    required Duration duration,
    required String? requestId,
    required String status,
    Object? error,
  }) {
    final telemetry = _telemetryService;
    if (telemetry == null) return;
    final items = result.items;
    final groups = result.candidateGroups;
    final isZero = items.isEmpty;
    final isApiFailure = status == 'failure';
    telemetry.record(
      ClientTelemetryEvent(
        eventType: isApiFailure
            ? 'mobile.food_search_failed'
            : 'mobile.food_search_completed',
        flow: 'food_search',
        surface: 'mobile',
        severity: isApiFailure ? 'error' : (isZero ? 'info' : 'info'),
        status: status,
        traceId: requestId,
        route: '/v1/foods/search',
        method: 'POST',
        durationMs: duration.inMilliseconds,
        errorCode: error is ApiException ? error.code : null,
        errorMessage: error?.toString(),
        metadata: <String, Object?>{
          'queryLength': query.length,
          'barcode': barcode,
          'limit': limit,
          'resultCount': items.length,
          'candidateGroupCount': groups?.length ?? 0,
          'zeroResults': isZero,
        },
      ),
    );
  }
}

class _RepositoryScope {
  const _RepositoryScope({required this.userId, required this.epoch});

  final String? userId;
  final int epoch;
}

Map<String, Object?> _responseOutput(Map<String, Object?> json) {
  return json['output'] as Map<String, Object?>? ?? json;
}

List<Object?> _jsonList(Object? value) => value is List ? value : const [];

AgentConversationDetail _parseAgentConversationDetail(
  Map<String, Object?> json, {
  required String conversationId,
}) {
  final messages = _jsonList(json['messages'])
      .map(AgentConversationMessage.tryFromJson)
      .whereType<AgentConversationMessage>()
      .toList();
  final toolExecutions = _jsonList(json['toolExecutions'])
      .map(AgentToolExecutionSnapshot.tryFromJson)
      .whereType<AgentToolExecutionSnapshot>()
      .toList();
  final conversationJson = json['conversation'];
  AgentConversationSummary? conversation;
  if (conversationJson is Map) {
    try {
      conversation = AgentConversationSummary.fromJson(
        conversationJson.map((key, value) => MapEntry(key.toString(), value)),
      );
    } on Object {
      // Fall back to the requested ID and valid message subset.
    }
  }
  conversation ??= _fallbackConversationSummary(conversationId, messages);
  return AgentConversationDetail(
    conversation: conversation,
    messages: messages,
    toolExecutions: toolExecutions,
  );
}

AgentConversationSummary _fallbackConversationSummary(
  String conversationId,
  List<AgentConversationMessage> messages,
) {
  final createdAt = messages.isEmpty
      ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
      : messages.first.createdAt;
  final updatedAt = messages.isEmpty ? createdAt : messages.last.createdAt;
  final firstUserText = messages
      .where((message) => message.role == 'user')
      .map((message) => message.content.trim())
      .firstWhere((text) => text.isNotEmpty, orElse: () => 'Nutrition chat');
  return AgentConversationSummary(
    id: conversationId,
    title: firstUserText,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

AgentRunResult agentRunResultFromJson(Map<String, Object?> json) {
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
    usualFoods: json['usualFoods'] == null
        ? null
        : (json['usualFoods'] as List<Object?>)
            .cast<Map<String, Object?>>()
            .map(UsualFood.fromJson)
            .toList(),
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
    usualFoodDraft: json['usualFoodDraft'] == null
        ? _parseTopLevelUsualFoodDraft(json)
        : _parseNestedUsualFoodDraft(
            json['usualFoodDraft'] as Map<String, Object?>,
          ),
    sourceProposalId: json['sourceProposalId'] as String?,
    usualMealDraft: json['usualMealDraft'] == null
        ? null
        : UsualMealDraft.fromJson(
            _responseOutput(json['usualMealDraft'] as Map<String, Object?>),
          ),
    confirmedMutation: ConfirmedNutritionMutation.tryParse(
      json['confirmedMutation'],
    ),
  );
}

UsualFood _parseUsualFoodResponse(Map<String, Object?> json) {
  final output = _responseOutput(json);
  if (output['id'] is String) {
    return UsualFood.fromJson(output);
  }
  final food = output['usualFood'] ?? output['food'] ?? output['item'];
  return UsualFood.fromJson(food as Map<String, Object?>);
}

UsualFoodDraft? _parseTopLevelUsualFoodDraft(Map<String, Object?> json) {
  if (json['draft'] is! Map<String, Object?>) return null;
  return UsualFoodDraft.fromJson(json['draft'] as Map<String, Object?>);
}

UsualFoodDraft _parseNestedUsualFoodDraft(Map<String, Object?> json) {
  final output = _responseOutput(json);
  final draft = output['draft'] is Map<String, Object?>
      ? output['draft'] as Map<String, Object?>
      : output;
  return UsualFoodDraft.fromJson(draft);
}

List<T> _upsertById<T>(
  List<T> items,
  T item,
  String Function(T item) idOf,
) {
  final exists = items.any((existing) => idOf(existing) == idOf(item));
  return exists
      ? items
          .map((existing) => idOf(existing) == idOf(item) ? item : existing)
          .toList(growable: false)
      : [...items, item];
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
