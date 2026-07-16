import 'dart:io';

import 'package:cal_tracker_mobile/local_toolkit/data/local_toolkit_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('local toolkit fakes provide authenticated editable fixture data',
      () async {
    final dependencies = createLocalToolkitDependencies(
      store: createLocalFixtureStore(
        now: () => DateTime(2026, 5, 28, 12),
      ),
    );

    final user = await dependencies.authRepository.restoreSession();
    expect(user, isNotNull);
    expect(user!.email, 'local@bettercalories.test');

    final summary = await dependencies.nutritionRepository.getDailySummary();
    expect(summary.meals, isNotEmpty);

    dependencies.store.clearTodayMeals();
    final emptySummary =
        await dependencies.nutritionRepository.getDailySummary();
    expect(emptySummary.meals, isEmpty);

    dependencies.store.addSampleMeal();
    final updatedSummary =
        await dependencies.nutritionRepository.getDailySummary();
    expect(updatedSummary.meals, hasLength(1));
  });

  test('local authentication uses fixture data without a backend', () async {
    final dependencies = createLocalToolkitDependencies();

    await dependencies.authRepository.logout();
    expect(dependencies.store.sessionActive, isFalse);

    final session = await dependencies.authRepository.login(
      email: 'fixture-user@bettercalories.test',
      password: 'fixture-password',
    );

    expect(session.user.email, 'fixture-user@bettercalories.test');
    expect(dependencies.store.sessionActive, isTrue);
    expect(await dependencies.tokenStorage.read(), isNotNull);
  });

  test('local agent scenarios return explicit fixture results', () async {
    final dependencies = createLocalToolkitDependencies();

    dependencies.store.selectScenario('clarification');
    final clarification =
        await dependencies.nutritionRepository.logText('anything');
    expect(clarification.kind, 'clarification_required');
    expect(clarification.candidateGroups, isNotEmpty);

    dependencies.store.selectScenario('auto_committed');
    final voice = await dependencies.nutritionRepository.logAudio(
      File('/tmp/local_toolkit_fake_audio.wav'),
    );
    expect(voice.transcript, 'local auto commit');
    expect(voice.result.kind, 'meal_committed');
  });
}
