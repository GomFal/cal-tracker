import 'dart:convert';

import 'package:cal_tracker_mobile/app/app.dart';
import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:patrol/patrol.dart';

const _patrolApiConfig = ApiConfig(baseUrl: 'http://10.0.2.2:3000');

void main() {
  patrolTest('sets first calorie target and balanced macro distribution',
      ($) async {
    final user = await _createPatrolUser('macro-wizard');
    await _login($, user);

    await $(const ValueKey('nav_home_button')).tap();
    await $(const ValueKey('dashboard_progress_card')).waitUntilVisible(
      timeout: const Duration(seconds: 20),
    );
    await $(const ValueKey('dashboard_progress_card')).tap();
    await $(const ValueKey('dashboard_calorie_target_field')).enterText('2000');
    await $(const ValueKey('dashboard_save_calorie_target_button')).tap();

    await $(const ValueKey('macro_prompt_set_distribution')).waitUntilVisible(
      timeout: const Duration(seconds: 20),
    );
    await $(const ValueKey('macro_prompt_set_distribution')).tap();
    await $('Set your macros').waitUntilVisible(
      timeout: const Duration(seconds: 20),
    );
    await $(const ValueKey('macro_preset_balanced')).tap();
    await $(const ValueKey('macro_distribution_save_button')).tap();

    await $(const ValueKey('nav_menu_button')).tap();
    await $(const ValueKey('macro_distribution_row')).waitUntilVisible(
      timeout: const Duration(seconds: 20),
    );
    await $('Balanced: 30% protein, 40% carbs, 30% fat').waitUntilVisible(
      timeout: const Duration(seconds: 20),
    );
  });
}

Future<void> _login(PatrolIntegrationTester $, _PatrolUser user) async {
  await $.tester.pumpWidget(
    const CalTrackerBootstrap(apiConfig: _patrolApiConfig),
  );
  await $.pump(const Duration(milliseconds: 500));
  await $(const ValueKey('email_field')).waitUntilVisible(
    timeout: const Duration(seconds: 20),
  );
  await $(const ValueKey('email_field')).enterText(user.email);
  await $(const ValueKey('password_field')).enterText('password123');
  FocusManager.instance.primaryFocus?.unfocus();
  await $.pump(const Duration(milliseconds: 250));
  await $(const ValueKey('auth_submit_button')).scrollTo().tap();
  await $(const ValueKey('dashboard_progress_card')).waitUntilVisible(
    timeout: const Duration(seconds: 20),
  );
}

Future<_PatrolUser> _createPatrolUser(String prefix) async {
  final email = '$prefix-${DateTime.now().microsecondsSinceEpoch}@example.com';
  final uri = Uri.parse('${_patrolApiConfig.baseUrl}/v1/auth/register');
  final response = await _sendWithRetry(
    () => http.post(
      uri,
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': 'password123',
        'displayName': 'Patrol User',
      }),
    ),
    'POST $uri',
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

Future<http.Response> _sendWithRetry(
  Future<http.Response> Function() request,
  String label,
) async {
  Object? lastError;
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      return await request().timeout(const Duration(seconds: 10));
    } catch (error) {
      lastError = error;
      await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
    }
  }
  throw StateError('$label failed after retries: $lastError');
}

class _PatrolUser {
  const _PatrolUser({
    required this.email,
    required this.accessToken,
  });

  final String email;
  final String accessToken;
}
