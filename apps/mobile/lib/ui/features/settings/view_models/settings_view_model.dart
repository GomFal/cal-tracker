import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/nutrition_repository.dart';
import '../../../../domain/models/auth_models.dart';
import '../../../../domain/models/macro_distribution.dart';
import '../../../../domain/models/nutrition_models.dart';
import '../../../../domain/models/nutrition_summary_updates.dart';
import '../../../core/user_visible_error.dart';

class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel({
    required AuthRepository authRepository,
    required NutritionRepository nutritionRepository,
    DateTime Function()? now,
  }) : _authRepository = authRepository,
       _nutritionRepository = nutritionRepository,
       _now = now ?? DateTime.now;

  final AuthRepository _authRepository;
  final NutritionRepository _nutritionRepository;
  final DateTime Function() _now;
  DailyGoals? _goals;
  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _isSaving = false;
  String? _error;

  DailyGoals? get goals => _goals;
  bool get hasVisibleData => _goals != null;
  bool get isLoading => _isLoading && !hasVisibleData;
  bool get isRefreshing => _isRefreshing;
  bool get isSaving => _isSaving;
  String? get error => _error;

  Future<void> load({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await _nutritionRepository.cachedDailySummary(
        date: _today,
      );
      if (cached != null) {
        _goals = goalsFromSummary(cached.value);
        _error = null;
        _isLoading = false;
        notifyListeners();
      }
    }

    final hadVisibleData = hasVisibleData;
    if (hadVisibleData) {
      _isRefreshing = true;
    } else {
      _isLoading = true;
    }
    notifyListeners();

    try {
      final summary = await _nutritionRepository.refreshDailySummary(
        date: _today,
        force: forceRefresh,
      );
      _goals = goalsFromSummary(summary);
      _error = null;
    } catch (error) {
      if (!hadVisibleData) {
        _error = userVisibleErrorMessage(
          error,
          context: UserErrorContext.settingsLoad,
        );
      }
    } finally {
      _isLoading = false;
      _isRefreshing = false;
      notifyListeners();
    }
  }

  Future<DailyGoals?> updateGoals({
    int? calories,
    double? hydrationGoalLiters,
    String? calorieTargetSource,
    MacroDistributionConfig? macroConfig,
    int? macroCalorieTarget,
  }) async {
    final previous = _goals;
    if (previous != null) {
      _goals = goalsWithOverrides(
        previous,
        calories: calories,
        hydrationGoalLiters: hydrationGoalLiters,
        calorieTargetSource: calorieTargetSource,
        macroConfig: macroConfig,
        macroCalorieTarget: macroCalorieTarget,
      );
      _persistGoalsToCachedSummary(_goals!);
    }
    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      final goals = await _nutritionRepository.updateDailyGoals(
        calories: calories,
        hydrationGoalLiters: hydrationGoalLiters,
        calorieTargetSource: calorieTargetSource,
        macroConfig: macroConfig,
        macroCalorieTarget: macroCalorieTarget,
      );
      _goals = goals;
      _persistGoalsToCachedSummary(goals);
      _error = null;
      return goals;
    } catch (error) {
      _goals = previous;
      if (previous != null) {
        _persistGoalsToCachedSummary(previous);
      }
      _error = userVisibleErrorMessage(
        error,
        context: UserErrorContext.settingsSave,
      );
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<AuthUser?> setTrustedMode(bool enabled) async {
    _isSaving = true;
    notifyListeners();
    try {
      final user = await _authRepository.updateTrustedMode(enabled);
      _error = null;
      return user;
    } catch (error) {
      _error = userVisibleErrorMessage(
        error,
        context: UserErrorContext.settingsSave,
      );
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  void reset() {
    _goals = null;
    _isLoading = false;
    _isRefreshing = false;
    _isSaving = false;
    _error = null;
    notifyListeners();
  }

  void _persistGoalsToCachedSummary(DailyGoals goals) {
    unawaited(() async {
      final cached = await _nutritionRepository.cachedDailySummary(
        date: goals.date,
      );
      if (cached == null) return;
      await _nutritionRepository.putCachedDailySummary(
        dailySummaryWithGoals(cached.value, goals),
      );
    }());
  }

  String get _today {
    final now = _now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}
