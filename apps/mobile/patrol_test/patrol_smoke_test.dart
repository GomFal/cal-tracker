import 'dart:async';
import 'dart:convert';

import 'package:cal_tracker_mobile/app/app.dart';
import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:cal_tracker_mobile/ui/features/voice_log/view_models/voice_log_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:patrol/patrol.dart';
import 'package:provider/provider.dart';

const _patrolApiConfig = ApiConfig(baseUrl: 'http://10.0.2.2:3000');

void main() {
  patrolTest('auth screen accepts typed credentials', ($) async {
    await _pumpApp($);

    expect($(const ValueKey('auth_brand_icon')), findsOneWidget);
    expect($(const ValueKey('login_hero_carousel')), findsOneWidget);
    await $(const ValueKey('email_field')).enterText('demo@example.com');
    await $(const ValueKey('password_field')).enterText('password123');

    expect($(const ValueKey('auth_submit_button')), findsOneWidget);
    expect($(const ValueKey('google_sign_in_button')), findsOneWidget);
  });

  patrolTest('switches main tabs through the shell navigation', ($) async {
    await _pumpAndAuthenticate($, openMealCreate: false);

    await $(const ValueKey('main_nav_stats')).tap();
    await $.pumpAndSettle();
    expect($('Calories and meal history'), findsOneWidget);

    await $(const ValueKey('main_nav_usual')).tap();
    await $.pumpAndSettle();
    expect($('Usual meals'), findsOneWidget);

    await $(const ValueKey('main_nav_menu')).tap();
    await $.pumpAndSettle();
    expect($('Account and preferences'), findsOneWidget);

    await $(const ValueKey('main_nav_home')).tap();
    await $.pumpAndSettle();
    expect($(const ValueKey('dashboard_progress_card')), findsOneWidget);
  }, tags: 'navigation');

  patrolTest('logs a Spanish bread and butter meal through the agent',
      ($) async {
    await _pumpAndAuthenticate($);

    await $(const ValueKey('meal_text_field')).enterText(
      'quiero añadir un desayuno de 100g de pan y 20g de mantequilla',
    );
    await $(const ValueKey('submit_meal_button')).tap();

    expect($('Bread and Butter'), findsOneWidget);
    await $(const ValueKey('confirm_proposal_button')).scrollTo().tap();

    expect($('Logged. You can correct it from history.'), findsOneWidget);
    expect($('Bread and Butter'), findsOneWidget);
  });

  patrolTest('revises an active bread and butter proposal before commit',
      ($) async {
    final user = await _createPatrolUser('proposal-revision');
    await _seedCorrectionTemplate(user);
    await _loginPatrolUser($, user);
    await _openMealCreate($);

    await $(const ValueKey('meal_text_field')).enterText(
      'log patrol correction meal',
    );
    await $(const ValueKey('submit_meal_button')).tap();

    await $('Bread and Butter').waitUntilVisible(
      timeout: const Duration(seconds: 30),
    );
    final viewModel = _voiceLogViewModel($);
    await _waitForVoiceLogIdle($, viewModel);
    expect(viewModel.proposal?.title, 'Bread and Butter');

    await $(const ValueKey('meal_text_field')).enterText(
      'No, the butter was 40 grams',
    );
    await $(const ValueKey('submit_meal_button')).tap();

    await _waitForVoiceLogIdle($, viewModel);
    expect(
      viewModel.proposal?.items.any(
        (item) => item.name == 'Butter' && item.quantity == 40,
      ),
      isTrue,
    );
    expect($('Bread and Butter'), findsOneWidget);

    await $(const ValueKey('edit_proposal_button')).scrollTo().tap();
    await $(const ValueKey('proposal_item_name_0')).waitUntilVisible(
      timeout: const Duration(seconds: 20),
    );
    final firstName = _textFieldValue(
      $,
      const ValueKey('proposal_item_name_0'),
    );
    final firstQuantity = _textFieldValue(
      $,
      const ValueKey('proposal_item_quantity_0'),
    );
    final secondName = _textFieldValue(
      $,
      const ValueKey('proposal_item_name_1'),
    );
    final secondQuantity = _textFieldValue(
      $,
      const ValueKey('proposal_item_quantity_1'),
    );
    expect(
      [
        (name: firstName, quantity: firstQuantity),
        (name: secondName, quantity: secondQuantity),
      ].any((item) => item.name == 'Butter' && item.quantity == '40'),
      isTrue,
    );
  }, tags: 'proposal_revision');

  patrolTest('logs a Spanish bread and ham meal through the agent', ($) async {
    await _pumpAndAuthenticate($);

    await $(const ValueKey('meal_text_field')).enterText(
      'Añade a mi desayuno 100 gramos de pan y 100 gramos de jamón.',
    );
    await $(const ValueKey('submit_meal_button')).tap();

    expect($('Bread and Ham'), findsOneWidget);
    expect($('Bread 100 g'), findsOneWidget);
    expect($('Ham 100 g'), findsOneWidget);
  });

  patrolTest('preserves Spanish meat and rice quantities and opens editor',
      ($) async {
    await _pumpAndAuthenticate($);

    await $(const ValueKey('meal_text_field')).enterText(
      'Añada al almuerzo 100 gramos de carne y 100 gramos de arroz',
    );
    await $(const ValueKey('submit_meal_button')).tap();

    expect($('Chicken breast and Cooked rice'), findsOneWidget);
    expect($('Chicken breast 100 g'), findsOneWidget);
    expect($('Cooked rice 100 g'), findsOneWidget);

    await $(const ValueKey('edit_proposal_button')).scrollTo().tap();
    expect($('Edit ingredients'), findsOneWidget);
    expect($(const ValueKey('proposal_item_name_0')), findsOneWidget);
    expect($(const ValueKey('proposal_item_quantity_0')), findsOneWidget);
    expect($(const ValueKey('add_proposal_item_button')), findsOneWidget);
  });

  patrolTest('shows resolver clarification for unresolved ingredients',
      ($) async {
    await _pumpAndAuthenticate($);

    await $(const ValueKey('meal_text_field')).enterText(
      'Añade 100 gramos de pan y 100 gramos de zzzzzzz',
    );
    await $(const ValueKey('submit_meal_button')).tap();

    await $(const ValueKey('resolver_clarification_card')).scrollTo();
    expect($(const ValueKey('resolver_clarification_card')), findsOneWidget);
    expect($('Needs a little more detail'), findsOneWidget);
    expect($('Food matches'), findsOneWidget);
  });
}

Future<void> _pumpAndAuthenticate(
  PatrolIntegrationTester $, {
  bool openMealCreate = true,
}) async {
  await _pumpApp($);
  if ($(const ValueKey('meal_text_field')).exists) return;

  if (!$(const ValueKey('dashboard_progress_card')).exists) {
    final email = 'patrol-${DateTime.now().microsecondsSinceEpoch}@example.com';
    await _registerPatrolUser(email);
    await $(const ValueKey('email_field')).enterText(email);
    await $(const ValueKey('password_field')).enterText('password123');
    FocusManager.instance.primaryFocus?.unfocus();
    await $.pump(const Duration(milliseconds: 300));
    await $(const ValueKey('auth_submit_button')).scrollTo().tap();
    await $(const ValueKey('dashboard_progress_card')).waitUntilVisible(
      timeout: const Duration(seconds: 20),
    );
  }

  if (openMealCreate) {
    await _openMealCreate($);
  }
}

Future<void> _loginPatrolUser(
  PatrolIntegrationTester $,
  _PatrolUser user,
) async {
  await _pumpApp($);
  if ($(const ValueKey('dashboard_progress_card')).exists) return;
  await $(const ValueKey('email_field')).enterText(user.email);
  await $(const ValueKey('password_field')).enterText(user.password);
  FocusManager.instance.primaryFocus?.unfocus();
  await $.pump(const Duration(milliseconds: 300));
  await $(const ValueKey('auth_submit_button')).scrollTo().tap();
  await $(const ValueKey('dashboard_progress_card')).waitUntilVisible(
    timeout: const Duration(seconds: 20),
  );
}

Future<void> _pumpApp(PatrolIntegrationTester $) async {
  await $.tester.pumpWidget(
    const CalTrackerBootstrap(apiConfig: _patrolApiConfig),
  );
  await $.pump(const Duration(milliseconds: 500));
}

Future<void> _openMealCreate(PatrolIntegrationTester $) async {
  if ($(const ValueKey('meal_text_field')).exists) return;
  final context = $.tester.element(
    find.byKey(const ValueKey('dashboard_progress_card')),
  );
  GoRouter.of(context).go('/meal/create');
  await $.pumpAndSettle();
  await $(const ValueKey('meal_text_field')).waitUntilVisible(
    timeout: const Duration(seconds: 20),
  );
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

String _textFieldValue(PatrolIntegrationTester $, ValueKey<String> key) {
  final field = $.tester.widget<TextField>(find.byKey(key));
  return field.controller?.text ?? '';
}

Future<void> _registerPatrolUser(String email) async {
  final response = await http.post(
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
}

Future<_PatrolUser> _createPatrolUser(String prefix) async {
  final email =
      'patrol-$prefix-${DateTime.now().microsecondsSinceEpoch}@example.com';
  final response = await http.post(
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
    password: 'password123',
    accessToken: body['accessToken'] as String,
  );
}

Future<void> _seedCorrectionTemplate(_PatrolUser user) async {
  await _executeAction(user, 'create_meal_template', {
    'title': 'Bread and Butter',
    'trustedAutoCommitEnabled': false,
    'items': [_breadItem(), _butterItem()],
    'aliases': ['log patrol correction meal'],
  });
}

Future<void> _executeAction(
  _PatrolUser user,
  String actionId,
  Map<String, Object?> input,
) async {
  final response = await http.post(
    Uri.parse('${_patrolApiConfig.baseUrl}/v1/actions/$actionId/execute'),
    headers: {
      'content-type': 'application/json',
      'authorization': 'Bearer ${user.accessToken}',
    },
    body: jsonEncode({'input': input, 'source': 'flutter'}),
  );
  if (response.statusCode != 200) {
    throw StateError(
      'Failed to execute $actionId ${response.statusCode}: ${response.body}',
    );
  }
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

Map<String, Object?> _butterItem() => {
      'name': 'Butter',
      'quantity': 20,
      'unit': 'g',
      'calories': 143,
      'proteinGrams': 0.2,
      'carbsGrams': 0,
      'fatGrams': 16.2,
      'source': 'patrol_fixture',
      'canonicalName': 'butter',
      'confidence': 0.95,
    };

class _PatrolUser {
  const _PatrolUser({
    required this.email,
    required this.password,
    required this.accessToken,
  });

  final String email;
  final String password;
  final String accessToken;
}
