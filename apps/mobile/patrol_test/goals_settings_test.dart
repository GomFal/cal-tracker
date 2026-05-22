import 'dart:convert';

import 'package:cal_tracker_mobile/app/app.dart';
import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:patrol/patrol.dart';

const _patrolApiConfig = ApiConfig(baseUrl: 'http://10.0.2.2:3000');

void main() {
  patrolTest('sets first calorie target from the Home setup prompt', ($) async {
    final user = await _createPatrolUser('home-goal-setup');
    await _login($, user);

    await $(const ValueKey('nav_home_button')).tap();
    await $(const ValueKey('dashboard_progress_card')).waitUntilVisible(
      timeout: const Duration(seconds: 20),
    );
    expect($('??'), findsNothing);

    await $(const ValueKey('dashboard_progress_card')).tap();
    await $(const ValueKey('dashboard_calorie_target_field')).enterText('1900');
    await $(const ValueKey('dashboard_save_calorie_target_button')).tap();

    await $('1900').waitUntilVisible(
      timeout: const Duration(seconds: 20),
    );
  });

  patrolTest('uses calorie calculator estimate before saving Home target',
      ($) async {
    final user = await _createPatrolUser('home-calculator');
    await _login($, user);

    await $(const ValueKey('nav_home_button')).tap();
    await $(const ValueKey('dashboard_progress_card')).tap();
    await $(const ValueKey('calorie_calculator_link')).tap();
    await $('What is your biological sex?').waitUntilVisible(
      timeout: const Duration(seconds: 20),
    );
    await $.pumpAndSettle();

    await $(const ValueKey('calorie_wizard_sex_female')).tap();
    await $(const ValueKey('calorie_wizard_next_button')).tap();

    await $(const ValueKey('calorie_wizard_birth_month_wheel'))
        .waitUntilVisible(timeout: const Duration(seconds: 20));
    await $(const ValueKey('calorie_wizard_next_button')).tap();

    await $(const ValueKey('calorie_wizard_height_ruler'))
        .waitUntilVisible(timeout: const Duration(seconds: 20));
    await $(const ValueKey('calorie_wizard_next_button')).tap();

    await $(const ValueKey('calorie_wizard_weight_ruler'))
        .waitUntilVisible(timeout: const Duration(seconds: 20));
    await $(const ValueKey('calorie_wizard_next_button')).tap();

    await $(const ValueKey('calorie_wizard_goal_lose_fat')).tap();
    await $(const ValueKey('calorie_wizard_next_button')).tap();

    await $(const ValueKey('calorie_wizard_pace_moderate')).tap();
    await $(const ValueKey('calorie_wizard_next_button')).tap();

    await $(const ValueKey('calorie_wizard_activity_lightly_active')).tap();
    await $(const ValueKey('calorie_wizard_next_button')).tap();

    await $(const ValueKey('calorie_wizard_target_value')).waitUntilVisible(
      timeout: const Duration(seconds: 20),
    );
    await $(const ValueKey('calorie_wizard_use_estimate_button')).tap();

    await $(const ValueKey('dashboard_remaining_calories')).waitUntilVisible(
      timeout: const Duration(seconds: 20),
    );
  });

  patrolTest('edits goals from Menu and updates Home immediately', ($) async {
    final user = await _createPatrolUser('goals-menu');
    await _login($, user);

    await $(const ValueKey('nav_menu_button')).tap();
    await $(const ValueKey('calorie_target_row')).waitUntilVisible(
      timeout: const Duration(seconds: 20),
    );

    await $(const ValueKey('calorie_target_row')).tap();
    await $(const ValueKey('calorie_target_field')).enterText('2300');
    await $(const ValueKey('save_goal_button')).scrollTo().tap();
    await $('2300 Kcal daily target').waitUntilVisible(
      timeout: const Duration(seconds: 20),
    );

    await $(const ValueKey('hydration_goal_row')).tap();
    await $(const ValueKey('hydration_goal_value')).waitUntilVisible(
      timeout: const Duration(seconds: 20),
    );
    for (var index = 0; index < 10; index++) {
      await $(const ValueKey('hydration_goal_increase_button')).tap();
    }
    await $(const ValueKey('save_goal_button')).tap();
    await $('2.5 L per day').waitUntilVisible(
      timeout: const Duration(seconds: 20),
    );

    await $(const ValueKey('nav_home_button')).tap();
    await $('2300').waitUntilVisible(
      timeout: const Duration(seconds: 20),
    );
  });

  patrolTest('shows the same target calories on Home and Stats', ($) async {
    final user = await _createPatrolUser('goals-consistency');
    final today = _formatDateOnly(DateTime.now());
    await _putGoals(
      accessToken: user.accessToken,
      date: today,
      calories: 2450,
      hydrationGoalLiters: 2.5,
    );
    await _login($, user);

    await $(const ValueKey('nav_home_button')).tap();
    await $('2450').waitUntilVisible(
      timeout: const Duration(seconds: 20),
    );

    await $(const ValueKey('nav_stats_button')).tap();
    await $('Target: 2450 Kcal').waitUntilVisible(
      timeout: const Duration(seconds: 20),
    );
  });

  patrolTest('keeps previous day target after today target changes', ($) async {
    final user = await _createPatrolUser('goals-history');
    final today = DateTime.now();
    final previous = today.subtract(const Duration(days: 1));
    final todayDate = _formatDateOnly(today);
    final previousDate = _formatDateOnly(previous);

    await _putGoals(
      accessToken: user.accessToken,
      date: previousDate,
      calories: 1800,
      hydrationGoalLiters: 2.5,
    );
    await _getDailySummary(user.accessToken, previousDate);
    await _seedCommittedMeal(
      accessToken: user.accessToken,
      title: 'Previous target meal',
      occurredAt: '${previousDate}T12:00:00.000Z',
      calories: 360,
    );
    await _seedCommittedMeal(
      accessToken: user.accessToken,
      title: 'Today target meal',
      occurredAt: '${todayDate}T12:00:00.000Z',
      calories: 420,
    );
    await _putGoals(
      accessToken: user.accessToken,
      date: todayDate,
      calories: 2400,
      hydrationGoalLiters: 3,
    );

    await _login($, user);
    await $(const ValueKey('nav_stats_button')).tap();
    await $('Target: 2400 Kcal').waitUntilVisible(
      timeout: const Duration(seconds: 20),
    );
    await $('Logged meals').waitUntilVisible(
      timeout: const Duration(seconds: 20),
    );
    expect($('Today target meal'), findsWidgets);

    await $(ValueKey('stats_day_$previousDate')).tap();
    await $('Target: 1800 Kcal').waitUntilVisible(
      timeout: const Duration(seconds: 20),
    );
    expect($('Previous target meal'), findsWidgets);
    expect($('Today target meal'), findsNothing);
  });
}

Future<void> _login(PatrolIntegrationTester $, _PatrolUser user) async {
  await $.pumpWidgetAndSettle(
    const CalTrackerBootstrap(apiConfig: _patrolApiConfig),
  );
  await $(const ValueKey('email_field')).enterText(user.email);
  await $(const ValueKey('password_field')).enterText('password123');
  FocusManager.instance.primaryFocus?.unfocus();
  await $.pumpAndSettle();
  await $(const ValueKey('auth_submit_button')).scrollTo().tap();
  await $(const ValueKey('nav_log_button')).waitUntilVisible(
    timeout: const Duration(seconds: 20),
  );
  await _setEnglishLanguage($);
}

Future<void> _setEnglishLanguage(PatrolIntegrationTester $) async {
  await $(const ValueKey('nav_menu_button')).tap();
  await $(const ValueKey('language_settings_row')).waitUntilVisible(
    timeout: const Duration(seconds: 20),
  );
  await $(const ValueKey('language_settings_row')).tap();
  await $(const ValueKey('language_option_en')).waitUntilVisible(
    timeout: const Duration(seconds: 20),
  );
  await $(const ValueKey('language_option_en')).tap();
  await $.pumpAndSettle();
  await $(const ValueKey('nav_log_button')).tap();
  await $(const ValueKey('meal_text_field')).waitUntilVisible(
    timeout: const Duration(seconds: 20),
  );
}

Future<_PatrolUser> _createPatrolUser(String prefix) async {
  final email = '$prefix-${DateTime.now().microsecondsSinceEpoch}@example.com';
  final response = await _postJson(
    Uri.parse('${_patrolApiConfig.baseUrl}/v1/auth/register'),
    headers: const {'content-type': 'application/json'},
    body: jsonEncode({
      'email': email,
      'password': 'password123',
      'displayName': 'Patrol User',
    }),
  );
  if (response.statusCode != 200 && response.statusCode != 201) {
    throw StateError(
      'Failed to create Patrol user ${response.statusCode}: ${response.body}',
    );
  }
  final body = jsonDecode(response.body) as Map<String, Object?>;
  return _PatrolUser(
    email: email,
    accessToken: body['accessToken'] as String,
  );
}

Future<void> _putGoals({
  required String accessToken,
  required String date,
  required int calories,
  required double hydrationGoalLiters,
}) async {
  final uri = Uri.parse('${_patrolApiConfig.baseUrl}/v1/goals');
  final headers = {
    'authorization': 'Bearer $accessToken',
    'content-type': 'application/json',
  };
  final body = jsonEncode({
    'date': date,
    'calories': calories,
    'hydrationGoalLiters': hydrationGoalLiters,
  });
  final response = await _sendWithRetry(
    () => http.put(uri, headers: headers, body: body),
    'PUT $uri',
  );
  if (response.statusCode != 200) {
    throw StateError(
      'Failed to update goals ${response.statusCode}: ${response.body}',
    );
  }
}

Future<void> _getDailySummary(String accessToken, String date) async {
  final uri =
      Uri.parse('${_patrolApiConfig.baseUrl}/v1/summary/daily?date=$date');
  final response = await _sendWithRetry(
    () => http.get(uri, headers: {'authorization': 'Bearer $accessToken'}),
    'GET $uri',
  );
  if (response.statusCode != 200) {
    throw StateError(
      'Failed to fetch summary ${response.statusCode}: ${response.body}',
    );
  }
}

Future<void> _seedCommittedMeal({
  required String accessToken,
  required String title,
  required String occurredAt,
  required int calories,
}) async {
  final created =
      await _executeAction(accessToken, 'create_meal_proposal_from_items', {
    'phrase': title,
    'title': title,
    'items': [
      {
        'name': title,
        'quantity': 1,
        'unit': 'serving',
        'calories': calories,
        'proteinGrams': 10,
        'carbsGrams': 30,
        'fatGrams': 8,
        'source': 'patrol_fixture',
      }
    ],
  });
  final proposal = created['proposal'] as Map<String, Object?>;
  final response = await _postJson(
    Uri.parse(
      '${_patrolApiConfig.baseUrl}/v1/meals/proposals/${proposal['id']}/commit',
    ),
    headers: {
      'authorization': 'Bearer $accessToken',
      'content-type': 'application/json',
    },
    body: jsonEncode({'occurredAt': occurredAt}),
  );
  if (response.statusCode != 200) {
    throw StateError(
      'Failed to commit meal ${response.statusCode}: ${response.body}',
    );
  }
}

Future<Map<String, Object?>> _executeAction(
  String accessToken,
  String actionId,
  Map<String, Object?> input,
) async {
  final response = await _postJson(
    Uri.parse('${_patrolApiConfig.baseUrl}/v1/actions/$actionId/execute'),
    headers: {
      'authorization': 'Bearer $accessToken',
      'content-type': 'application/json',
    },
    body: jsonEncode({'input': input, 'source': 'flutter'}),
  );
  if (response.statusCode != 200) {
    throw StateError(
      'Failed to execute $actionId ${response.statusCode}: ${response.body}',
    );
  }
  final body = jsonDecode(response.body) as Map<String, Object?>;
  return body['output'] as Map<String, Object?>;
}

Future<http.Response> _postJson(
  Uri uri, {
  required Map<String, String> headers,
  required Object body,
}) async {
  return _sendWithRetry(
    () => http.post(uri, headers: headers, body: body),
    'POST $uri',
  );
}

Future<http.Response> _sendWithRetry(
  Future<http.Response> Function() request,
  String description,
) async {
  Object? lastError;
  http.Response? lastRetryableResponse;
  for (var attempt = 0; attempt < 8; attempt++) {
    try {
      final response = await request();
      if (response.statusCode < 500) {
        return response;
      }
      lastRetryableResponse = response;
    } catch (error) {
      lastError = error;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  if (lastRetryableResponse != null) {
    return lastRetryableResponse;
  }
  throw StateError('Failed to $description: $lastError');
}

String _formatDateOnly(DateTime value) {
  return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

class _PatrolUser {
  const _PatrolUser({
    required this.email,
    required this.accessToken,
  });

  final String email;
  final String accessToken;
}
