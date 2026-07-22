import 'dart:async';

import 'package:cal_tracker_mobile/app/app.dart';
import 'package:cal_tracker_mobile/data/repositories/auth_repository.dart';
import 'package:cal_tracker_mobile/data/repositories/nutrition_repository.dart';
import 'package:cal_tracker_mobile/data/services/app_preferences_repository.dart';
import 'package:cal_tracker_mobile/domain/models/auth_models.dart';
import 'package:cal_tracker_mobile/domain/models/nutrition_models.dart';
import 'package:cal_tracker_mobile/ui/features/auth/view_models/auth_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockNutritionRepository extends Mock implements NutritionRepository {}

void main() {
  testWidgets(
      'holds the dashboard route while a valid saved session is restored',
      (tester) async {
    final restore = Completer<AuthUser?>();
    final authRepository = _MockAuthRepository();
    final nutritionRepository = _MockNutritionRepository();
    _stubNutritionRepository(nutritionRepository);
    when(() => authRepository.restoreSession()).thenAnswer(
      (_) => restore.future,
    );

    await tester.pumpWidget(
      CalTrackerBootstrap(
        preferencesRepository: _FakePreferencesRepository(),
        authRepository: authRepository,
        nutritionRepository: nutritionRepository,
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('auth_restore_gate')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth_submit_button')), findsNothing);
    verifyNever(
      () => nutritionRepository.refreshDailySummary(
        date: any(named: 'date'),
        force: any(named: 'force'),
      ),
    );

    restore.complete(_user);
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('auth_submit_button')), findsNothing);
    expect(
        find.byKey(const ValueKey('dashboard_progress_card')), findsOneWidget);
    verify(
      () => nutritionRepository.refreshDailySummary(
        date: any(named: 'date'),
        force: any(named: 'force'),
      ),
    ).called(greaterThan(0));
  });

  testWidgets('redirects to auth only after saved session validation fails',
      (tester) async {
    final restore = Completer<AuthUser?>();
    final authRepository = _MockAuthRepository();
    final nutritionRepository = _MockNutritionRepository();
    _stubNutritionRepository(nutritionRepository);
    when(() => authRepository.restoreSession()).thenAnswer(
      (_) => restore.future,
    );

    await tester.pumpWidget(
      CalTrackerBootstrap(
        preferencesRepository: _FakePreferencesRepository(),
        authRepository: authRepository,
        nutritionRepository: nutritionRepository,
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('auth_restore_gate')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth_submit_button')), findsNothing);

    restore.complete(null);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('auth_restore_gate')), findsNothing);
    expect(find.byKey(const ValueKey('auth_submit_button')), findsOneWidget);
    verifyNever(
      () => nutritionRepository.refreshDailySummary(
        date: any(named: 'date'),
        force: any(named: 'force'),
      ),
    );
  });

  testWidgets('redirects authenticated users away from auth route',
      (tester) async {
    final authRepository = _MockAuthRepository();
    final nutritionRepository = _MockNutritionRepository();
    _stubNutritionRepository(nutritionRepository);
    when(() => authRepository.restoreSession()).thenAnswer(
      (_) async => _user,
    );

    await tester.pumpWidget(
      CalTrackerBootstrap(
        preferencesRepository: _FakePreferencesRepository(),
        authRepository: authRepository,
        nutritionRepository: nutritionRepository,
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    final dashboardContext = tester.element(
      find.byKey(const ValueKey('dashboard_progress_card')),
    );
    GoRouter.of(dashboardContext).go('/auth');
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('auth_submit_button')), findsNothing);
    expect(
        find.byKey(const ValueKey('dashboard_progress_card')), findsOneWidget);
  });

  testWidgets(
      'logout redirects and starts cache cleanup before the backend finishes',
      (tester) async {
    final logoutCompleter = Completer<void>();
    final authRepository = _MockAuthRepository();
    final nutritionRepository = _MockNutritionRepository();
    _stubNutritionRepository(nutritionRepository);
    when(() => authRepository.restoreSession()).thenAnswer((_) async => _user);
    when(() => authRepository.logout())
        .thenAnswer((_) => logoutCompleter.future);
    when(() => nutritionRepository.clearActiveUserCache())
        .thenAnswer((_) async {});

    await tester.pumpWidget(
      CalTrackerBootstrap(
        preferencesRepository: _FakePreferencesRepository(),
        authRepository: authRepository,
        nutritionRepository: nutritionRepository,
        checkForUpdates: false,
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    final dashboardContext = tester.element(
      find.byKey(const ValueKey('dashboard_progress_card')),
    );
    final logout = dashboardContext.read<AuthViewModel>().logout();
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('auth_submit_button')), findsOneWidget);
    verify(() => nutritionRepository.clearActiveUserCache()).called(1);
    verify(() => nutritionRepository.deactivateCache()).called(1);

    logoutCompleter.complete();
    await logout;
  });
}

void _stubNutritionRepository(_MockNutritionRepository nutritionRepository) {
  when(
    () => nutritionRepository.dataChanges,
  ).thenAnswer((_) => const Stream.empty());
  when(
    () => nutritionRepository.cachedDailySummary(date: any(named: 'date')),
  ).thenAnswer((_) async => null);
  when(
    () => nutritionRepository.refreshDailySummary(
      date: any(named: 'date'),
      force: any(named: 'force'),
    ),
  ).thenAnswer((_) async => _summary);
  when(
    () => nutritionRepository.cachedTemplates(),
  ).thenAnswer((_) async => null);
  when(
    () => nutritionRepository.refreshTemplates(force: any(named: 'force')),
  ).thenAnswer((_) async => const []);
  when(
    () => nutritionRepository.cachedUsualFoods(),
  ).thenAnswer((_) async => null);
  when(
    () => nutritionRepository.refreshUsualFoods(force: any(named: 'force')),
  ).thenAnswer((_) async => const []);
  when(
    () => nutritionRepository.checkBackendHealth(),
  ).thenAnswer((_) async => true);
}

class _FakePreferencesRepository implements AppPreferencesRepository {
  ThemeMode savedThemeMode = ThemeMode.light;
  String? savedLocaleCode;
  int nextHeroIndex = 0;

  @override
  Future<ThemeMode> loadThemeMode() async => savedThemeMode;

  @override
  Future<void> saveThemeMode(ThemeMode mode) async {
    savedThemeMode = mode;
  }

  @override
  Future<String?> loadLocaleCode() async => savedLocaleCode;

  @override
  Future<void> saveLocaleCode(String code) async {
    savedLocaleCode = code;
  }

  @override
  Future<int> nextAuthHeroIndex({int count = 5}) async {
    final value = nextHeroIndex % count;
    nextHeroIndex++;
    return value;
  }
}

const _user = AuthUser(
  id: 'user-1',
  email: 'user@example.com',
  displayName: 'Test User',
  trustedModeEnabled: false,
);

const _emptyNutrition = NutritionSnapshot(
  calories: 0,
  proteinGrams: 0,
  carbsGrams: 0,
  fatGrams: 0,
);

const _targetNutrition = NutritionSnapshot(
  calories: 1920,
  proteinGrams: 120,
  carbsGrams: 220,
  fatGrams: 70,
);

const _summary = DailySummary(
  date: '2026-05-19',
  consumed: _emptyNutrition,
  target: _targetNutrition,
  remaining: _targetNutrition,
  hydrationGoalLiters: 0,
  waterConsumedLiters: 0,
  calorieTargetConfigured: true,
  calorieTargetSource: 'manual',
  meals: [],
);
