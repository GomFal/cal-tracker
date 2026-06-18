import 'dart:convert';

import 'package:app_intents/app_intents.dart';
import '../app/locale_view_model.dart';
import '../data/services/api_config.dart';
import '../data/services/app_preferences_repository.dart';
import '../data/services/app_preferences_storage.dart';
import '../data/services/secure_token_storage.dart';
import '../generated/api/cal_tracker_api.dart';

const _androidAppFunctionsSource = 'android_appfunctions';

const betterCaloriesIntentGetDailySummary =
    'app.bettercalories.GetDailySummary';
const betterCaloriesIntentGetRemainingTargets =
    'app.bettercalories.GetRemainingTargets';
const betterCaloriesIntentGetMealHistory = 'app.bettercalories.GetMealHistory';
const betterCaloriesIntentSearchNutrition =
    'app.bettercalories.SearchNutritionDatabase';
const betterCaloriesIntentProposeMealLog = 'app.bettercalories.ProposeMealLog';
const betterCaloriesIntentGetUsualFoods = 'app.bettercalories.GetUsualFoods';
const betterCaloriesIntentGetUsualMeals = 'app.bettercalories.GetUsualMeals';
const betterCaloriesIntentAskAgent = 'app.bettercalories.AskBetterCalories';
const betterCaloriesIntentExecuteNutritionAction =
    'app.bettercalories.ExecuteNutritionAction';

const _allowedGenericActionIds = <String>{
  'query_food_memory',
  'search_nutrition_database',
  'propose_meal_log',
  'get_daily_summary',
  'get_remaining_targets',
  'get_meal_history',
  'get_usual_foods',
  'get_usual_meals',
  'draft_usual_food',
  'draft_usual_meal',
};

BetterCaloriesAppIntentHandlers? _handlers;
bool _registered = false;

/// Initializes handlers used by Android AppFunctions.
///
/// This is intentionally safe to call from both the normal Flutter app entrypoint
/// and the headless `appIntentsMain` entrypoint used by Android background
/// execution.
void initializeBetterCaloriesAppIntents() {
  if (_registered) return;
  _registered = true;
  final handlers = _handlers ??= BetterCaloriesAppIntentHandlers.create();
  final appIntents = AppIntents();

  appIntents.registerIntentHandler(
    betterCaloriesIntentGetDailySummary,
    handlers.getDailySummary,
  );
  appIntents.registerIntentHandler(
    betterCaloriesIntentGetRemainingTargets,
    handlers.getRemainingTargets,
  );
  appIntents.registerIntentHandler(
    betterCaloriesIntentGetMealHistory,
    handlers.getMealHistory,
  );
  appIntents.registerIntentHandler(
    betterCaloriesIntentSearchNutrition,
    handlers.searchNutritionDatabase,
  );
  appIntents.registerIntentHandler(
    betterCaloriesIntentProposeMealLog,
    handlers.proposeMealLog,
  );
  appIntents.registerIntentHandler(
    betterCaloriesIntentGetUsualFoods,
    handlers.getUsualFoods,
  );
  appIntents.registerIntentHandler(
    betterCaloriesIntentGetUsualMeals,
    handlers.getUsualMeals,
  );
  appIntents.registerIntentHandler(
    betterCaloriesIntentAskAgent,
    handlers.askBetterCalories,
  );
  appIntents.registerIntentHandler(
    betterCaloriesIntentExecuteNutritionAction,
    handlers.executeNutritionAction,
  );
}

class BetterCaloriesAppIntentHandlers {
  BetterCaloriesAppIntentHandlers({required CalTrackerApiClient apiClient})
      : _apiClient = apiClient;

  factory BetterCaloriesAppIntentHandlers.create() {
    final tokenStorage = const SecureTokenStorage();
    final preferencesRepository = AppPreferencesRepository(
      storage: AppPreferencesStorage(),
    );
    return BetterCaloriesAppIntentHandlers(
      apiClient: CalTrackerApiClient(
        config: const ApiConfig.fromEnvironment(),
        tokenStorage: tokenStorage,
        localeTagProvider: () async {
          final savedTag = await preferencesRepository.loadLocaleCode();
          return LocaleViewModel.normalizeLocaleTag(savedTag).toLanguageTag();
        },
      ),
    );
  }

  final CalTrackerApiClient _apiClient;

  Future<Map<String, dynamic>> getDailySummary(
    Map<String, dynamic> params,
  ) {
    return _executeAction(
      'get_daily_summary',
      _withoutBlankValues({'date': _stringParam(params, 'date')}),
    );
  }

  Future<Map<String, dynamic>> getRemainingTargets(
    Map<String, dynamic> params,
  ) {
    return _executeAction(
      'get_remaining_targets',
      _withoutBlankValues({'date': _stringParam(params, 'date')}),
    );
  }

  Future<Map<String, dynamic>> getMealHistory(Map<String, dynamic> params) {
    return _executeAction(
      'get_meal_history',
      _withoutBlankValues({'limit': _intParam(params, 'limit')}),
    );
  }

  Future<Map<String, dynamic>> searchNutritionDatabase(
    Map<String, dynamic> params,
  ) {
    return _executeAction(
      'search_nutrition_database',
      _withoutBlankValues({
        'query': _requiredStringParam(params, 'query'),
        'barcode': _stringParam(params, 'barcode'),
      }),
    );
  }

  Future<Map<String, dynamic>> proposeMealLog(Map<String, dynamic> params) {
    return _executeAction(
      'propose_meal_log',
      _withoutBlankValues({
        'text': _requiredStringParam(params, 'text'),
        'occurredAt': _stringParam(params, 'occurredAt'),
      }),
    );
  }

  Future<Map<String, dynamic>> getUsualFoods(Map<String, dynamic> params) {
    return _executeAction('get_usual_foods', const {});
  }

  Future<Map<String, dynamic>> getUsualMeals(Map<String, dynamic> params) {
    return _executeAction('get_usual_meals', const {});
  }

  Future<Map<String, dynamic>> askBetterCalories(Map<String, dynamic> params) {
    return _guard('ask_agent', () async {
      final result = await _apiClient.runAgent(
        _requiredStringParam(params, 'text'),
        activeProposalId: _stringParam(params, 'activeProposalId'),
        source: _androidAppFunctionsSource,
      );
      return _success(
        actionId: 'agent_run',
        output: result,
        message: result['message'] as String?,
      );
    });
  }

  Future<Map<String, dynamic>> executeNutritionAction(
    Map<String, dynamic> params,
  ) {
    return _guard('execute_action', () async {
      final actionId = _requiredStringParam(params, 'actionId');
      if (!_allowedGenericActionIds.contains(actionId)) {
        return _failure(
          actionId: actionId,
          code: 'action_not_allowed',
          message:
              'This Android AppFunction can only execute read, draft, and proposal nutrition actions.',
        );
      }
      final input = _decodeInputJson(_stringParam(params, 'inputJson'));
      return _executeAction(actionId, input);
    });
  }

  Future<Map<String, dynamic>> _executeAction(
    String actionId,
    Map<String, Object?> input,
  ) {
    return _guard(actionId, () async {
      final result = await _apiClient.executeAction(
        actionId,
        input,
        source: _androidAppFunctionsSource,
      );
      return _success(
        actionId: actionId,
        confirmationRequired: result['confirmationRequired'] as bool?,
        output: result['output'],
      );
    });
  }

  Future<Map<String, dynamic>> _guard(
    String actionId,
    Future<Map<String, dynamic>> Function() run,
  ) async {
    try {
      return await run();
    } on ApiException catch (error) {
      return _failure(
        actionId: actionId,
        code: error.code ?? 'api_error',
        message: error.message,
        statusCode: error.statusCode,
        traceId: error.traceId,
      );
    } on FormatException catch (error) {
      return _failure(
        actionId: actionId,
        code: 'invalid_json',
        message: error.message,
      );
    } on ArgumentError catch (error) {
      return _failure(
        actionId: actionId,
        code: 'invalid_arguments',
        message: error.message,
      );
    } on Object catch (error) {
      return _failure(
        actionId: actionId,
        code: 'app_function_error',
        message: error.toString(),
      );
    }
  }
}

Map<String, dynamic> _success({
  required String actionId,
  Object? output,
  bool? confirmationRequired,
  String? message,
}) {
  return <String, dynamic>{
    'ok': true,
    'source': _androidAppFunctionsSource,
    'actionId': actionId,
    if (confirmationRequired != null)
      'confirmationRequired': confirmationRequired,
    if (message != null && message.trim().isNotEmpty) 'message': message,
    if (output != null) 'output': output,
  };
}

Map<String, dynamic> _failure({
  required String actionId,
  required String code,
  required String message,
  int? statusCode,
  String? traceId,
}) {
  return <String, dynamic>{
    'ok': false,
    'source': _androidAppFunctionsSource,
    'actionId': actionId,
    'error': <String, dynamic>{
      'code': code,
      'message': message,
      if (statusCode != null) 'statusCode': statusCode,
      if (traceId != null) 'traceId': traceId,
    },
  };
}

Map<String, Object?> _decodeInputJson(String? inputJson) {
  final trimmed = inputJson?.trim();
  if (trimmed == null || trimmed.isEmpty) return <String, Object?>{};
  final decoded = jsonDecode(trimmed);
  if (decoded is! Map) {
    throw const FormatException('inputJson must be a JSON object.');
  }
  return Map<String, Object?>.fromEntries(
    decoded.entries.map(
      (entry) => MapEntry(entry.key.toString(), entry.value),
    ),
  );
}

Map<String, Object?> _withoutBlankValues(Map<String, Object?> value) {
  return Map<String, Object?>.fromEntries(
    value.entries.where((entry) {
      final v = entry.value;
      return v != null && (v is! String || v.trim().isNotEmpty);
    }),
  );
}

String _requiredStringParam(Map<String, dynamic> params, String key) {
  final value = _stringParam(params, key);
  if (value == null || value.trim().isEmpty) {
    throw ArgumentError.value(value, key, 'Required parameter is missing.');
  }
  return value;
}

String? _stringParam(Map<String, dynamic> params, String key) {
  final value = params[key];
  if (value == null) return null;
  return value.toString();
}

int? _intParam(Map<String, dynamic> params, String key) {
  final value = params[key];
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}
