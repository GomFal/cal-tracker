import 'dart:async';
import 'dart:convert';

import 'package:cal_tracker_mobile/app/app.dart';
import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:cal_tracker_mobile/domain/models/nutrition_models.dart';
import 'package:cal_tracker_mobile/ui/features/voice_log/view_models/voice_log_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:patrol/patrol.dart';
import 'package:provider/provider.dart';

const _patrolApiConfig = ApiConfig(baseUrl: 'http://10.0.2.2:3000');

void main() {
  patrolTest(
      'manual food search clear button is constrained and clears results',
      ($) async {
    await _createAndLogin($, 'trello-clear');
    await _openMealCreate($);

    await $(const ValueKey('manual_food_search_field')).enterText('bread');
    await $(const ValueKey('manual_food_search_clear')).waitUntilVisible(
      timeout: const Duration(seconds: 20),
    );
    await $(const ValueKey('manual_food_search_result_button_0'))
        .waitUntilVisible(timeout: const Duration(seconds: 20));

    final searchField = $.tester.widget<TextField>(
      find.byKey(const ValueKey('manual_food_search_field')),
    );
    expect(
      searchField.decoration?.suffixIconConstraints,
      const BoxConstraints(minWidth: 56, minHeight: 48),
    );

    await $(const ValueKey('manual_food_search_clear')).tap();
    await $.pumpAndSettle();

    final clearedField = $.tester.widget<TextField>(
      find.byKey(const ValueKey('manual_food_search_field')),
    );
    expect(clearedField.controller?.text, isEmpty);
    expect(
        find.byKey(const ValueKey('manual_food_search_clear')), findsNothing);
    expect(
      find.byKey(const ValueKey('manual_food_search_result_button_0')),
      findsNothing,
    );
  });

  patrolTest('menu semantic copy is localized and has no dead three-dot action',
      ($) async {
    await _createAndLogin($, 'trello-menu');
    await _openMenu($);

    await $('Macro distribution').waitUntilVisible(
      timeout: const Duration(seconds: 20),
    );
    expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);

    await _openUsuals($);
    await $('Usuals').waitUntilVisible(timeout: const Duration(seconds: 20));

    await _openMenu($);
    await _chooseLanguage($, const ValueKey('language_option_es'));
    await $('Distribución de macros').waitUntilVisible(
      timeout: const Duration(seconds: 20),
    );
    await _chooseLanguage($, const ValueKey('language_option_en'));
    await $('Macro distribution').waitUntilVisible(
      timeout: const Duration(seconds: 20),
    );
  });

  patrolTest('proposal editor add button searches and saves a new ingredient',
      ($) async {
    final user = await _createAndLogin($, 'trello-add-ingredient');
    await _seedBreadTemplate(user, 'patrol trello bread seed');
    await _openMealCreate($);

    await $(const ValueKey('meal_text_field')).enterText(
      'patrol trello bread seed',
    );
    await $(const ValueKey('submit_meal_button')).tap();
    await $(const ValueKey('confirm_proposal_button')).waitUntilVisible(
      timeout: const Duration(seconds: 60),
    );

    await $(const ValueKey('edit_proposal_button')).scrollTo().tap();
    await $(const ValueKey('add_proposal_item_button')).waitUntilVisible(
      timeout: const Duration(seconds: 20),
    );
    await $(const ValueKey('add_proposal_item_button')).tap();
    await $.pumpAndSettle();

    await $(const ValueKey('proposal_item_1_search_toggle')).tap();
    await $(const ValueKey('proposal_item_1_search_field')).enterText('rice');
    await $(const ValueKey('proposal_item_1_search_result_button_0'))
        .waitUntilVisible(timeout: const Duration(seconds: 20));
    await $(const ValueKey('proposal_item_1_search_result_button_0')).tap();
    await $.pumpAndSettle();

    await $(const ValueKey('save_proposal_edits_button')).scrollTo().tap();
    final viewModel = _voiceLogViewModel($);
    await _waitForVoiceLogIdle($, viewModel);

    expect(viewModel.proposal?.items.length, greaterThan(1));
    expect(
      viewModel.proposal?.items.any(
        (item) => item.name.toLowerCase().contains('rice'),
      ),
      isTrue,
    );
  });

  patrolTest('update proposal items without active proposal creates a proposal',
      ($) async {
    await _createAndLogin($, 'trello-no-active-proposal');
    await _openMealCreate($);

    final viewModel = _voiceLogViewModel($);
    expect(viewModel.proposal, isNull);

    await viewModel.updateProposalItems([_breadMealItem()]);
    await _waitForVoiceLogIdle($, viewModel);
    await $.pumpAndSettle();

    expect(viewModel.proposal, isNotNull);
    expect(viewModel.proposal?.items.single.name, 'Bread');
    expect($(const ValueKey('confirm_proposal_button')), findsOneWidget);
  });
}

Future<_PatrolUser> _createAndLogin(
  PatrolIntegrationTester $,
  String prefix,
) async {
  final user = await _createPatrolUser(prefix);
  await _login($, user);
  await _setEnglishLanguage($);
  return user;
}

Future<void> _login(PatrolIntegrationTester $, _PatrolUser user) async {
  await $.pumpWidgetAndSettle(
    const CalTrackerBootstrap(apiConfig: _patrolApiConfig),
  );
  await $.pump(const Duration(milliseconds: 500));
  if (!$(const ValueKey('email_field')).exists) {
    await _logoutCurrentUser($);
  }
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

Future<void> _logoutCurrentUser(PatrolIntegrationTester $) async {
  if ($(const ValueKey('meal_create_screen')).exists) {
    final context = $.tester.element(
      find.byKey(const ValueKey('meal_create_screen')),
    );
    GoRouter.of(context).go('/dashboard');
    await $.pumpAndSettle();
  }
  await _openMenu($);
  await $(find.byIcon(Icons.logout_rounded)).scrollTo().tap();
  await $(const ValueKey('email_field')).waitUntilVisible(
    timeout: const Duration(seconds: 20),
  );
}

Future<void> _openMealCreate(PatrolIntegrationTester $) async {
  if ($(const ValueKey('meal_text_field')).exists) return;
  await _tapNav($, 'home');
  await $(const ValueKey('dashboard_progress_card')).waitUntilVisible(
    timeout: const Duration(seconds: 20),
  );
  final context = $.tester.element(
    find.byKey(const ValueKey('dashboard_progress_card')),
  );
  GoRouter.of(context).go('/meal/create');
  await $.pumpAndSettle();
  await $(const ValueKey('meal_text_field')).waitUntilVisible(
    timeout: const Duration(seconds: 20),
  );
}

Future<void> _openMenu(PatrolIntegrationTester $) async {
  await _tapNav($, 'menu');
  await $(const ValueKey('language_settings_row')).waitUntilVisible(
    timeout: const Duration(seconds: 20),
  );
}

Future<void> _openUsuals(PatrolIntegrationTester $) async {
  await _tapNav($, 'usual');
  await $(const ValueKey('usuals_section_tabs')).waitUntilVisible(
    timeout: const Duration(seconds: 20),
  );
}

Future<void> _tapNav(PatrolIntegrationTester $, String keyName) async {
  final mainKey = ValueKey<String>('main_nav_$keyName');
  final legacyKey = ValueKey<String>('nav_${keyName}_button');
  if ($(mainKey).exists) {
    await $(mainKey).tap();
  } else {
    await $(legacyKey).tap();
  }
  await $.pumpAndSettle();
}

Future<void> _setEnglishLanguage(PatrolIntegrationTester $) async {
  await _openMenu($);
  await _chooseLanguage($, const ValueKey('language_option_en'));
  await $('Language').waitUntilVisible(timeout: const Duration(seconds: 20));
}

Future<void> _chooseLanguage(
  PatrolIntegrationTester $,
  ValueKey<String> optionKey,
) async {
  await $(const ValueKey('language_settings_row')).tap();
  await $(optionKey).waitUntilVisible(timeout: const Duration(seconds: 20));
  await $(optionKey).tap();
  await $.pumpAndSettle();
}

VoiceLogViewModel _voiceLogViewModel(PatrolIntegrationTester $) {
  final context = $.tester.element(
    find.byKey(const ValueKey('meal_create_screen')),
  );
  return context.read<VoiceLogViewModel>();
}

Future<void> _waitForVoiceLogIdle(
  PatrolIntegrationTester $,
  VoiceLogViewModel viewModel,
) async {
  for (var attempt = 0; attempt < 150; attempt++) {
    if (!viewModel.isLoading) return;
    await $.pump(const Duration(milliseconds: 200));
  }
  throw TimeoutException('Voice log did not finish loading.');
}

Future<_PatrolUser> _createPatrolUser(String prefix) async {
  final email = '$prefix-${DateTime.now().microsecondsSinceEpoch}@example.com';
  final uri = Uri.parse('${_patrolApiConfig.baseUrl}/v1/auth/register');
  final response = await _sendWithRetry(
    () => http.post(
      uri,
      headers: const {'content-type': 'application/json'},
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

Future<void> _seedBreadTemplate(_PatrolUser user, String alias) async {
  await _executeAction(user, 'create_meal_template', {
    'title': 'Patrol Trello Bread',
    'trustedAutoCommitEnabled': false,
    'items': [_breadItem()],
    'aliases': [alias],
  });
}

Future<Map<String, Object?>> _executeAction(
  _PatrolUser user,
  String actionId,
  Map<String, Object?> input,
) async {
  final uri =
      Uri.parse('${_patrolApiConfig.baseUrl}/v1/actions/$actionId/execute');
  final response = await _sendWithRetry(
    () => http.post(
      uri,
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer ${user.accessToken}',
      },
      body: jsonEncode({'input': input, 'source': 'flutter'}),
    ),
    'POST $uri',
  );
  if (response.statusCode != 200) {
    throw StateError(
      'Failed to execute $actionId ${response.statusCode}: ${response.body}',
    );
  }
  final body = jsonDecode(response.body) as Map<String, Object?>;
  return body['output'] as Map<String, Object?>;
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

MealItem _breadMealItem() {
  return const MealItem(
    name: 'Bread',
    quantity: 100,
    unit: 'g',
    calories: 265,
    proteinGrams: 9,
    carbsGrams: 49,
    fatGrams: 3.2,
    source: 'patrol_fixture',
    canonicalName: 'bread',
    confidence: 0.95,
  );
}

Map<String, Object?> _breadItem() => {
      'name': 'Bread',
      'quantity': 100,
      'unit': 'g',
      'calories': 265,
      'proteinGrams': 9,
      'carbsGrams': 49,
      'fatGrams': 3.2,
      'source': 'patrol_fixture',
      'canonicalName': 'bread',
      'confidence': 0.95,
    };

class _PatrolUser {
  const _PatrolUser({
    required this.email,
    required this.accessToken,
  });

  final String email;
  final String accessToken;
}
