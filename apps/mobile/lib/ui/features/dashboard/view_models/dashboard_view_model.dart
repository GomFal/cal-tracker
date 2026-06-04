import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/nutrition_repository.dart';
import '../../../../domain/models/macro_distribution.dart';
import '../../../../domain/models/nutrition_models.dart';
import '../../../../domain/models/nutrition_summary_updates.dart';
import '../../../core/user_visible_error.dart';
import '../../hydration/hydration_format.dart';

class DashboardViewModel extends ChangeNotifier {
  DashboardViewModel({
    required NutritionRepository nutritionRepository,
    DateTime Function()? now,
  }) : _nutritionRepository = nutritionRepository,
       _now = now ?? DateTime.now;

  final NutritionRepository _nutritionRepository;
  final DateTime Function() _now;
  DailySummary? _summary;
  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _isSaving = false;
  bool _isSavingWater = false;
  Future<void>? _loadOperation;
  Future<void>? _waterSaveOperation;
  DailySummary? _confirmedWaterSummary;
  double? _pendingWaterLiters;
  String? _error;

  DailySummary? get summary => _summary;
  bool get hasVisibleData => _summary != null;
  bool get isLoading => _isLoading && !hasVisibleData;
  bool get isRefreshing => _isRefreshing;
  bool get isSaving => _isSaving || _isSavingWater;
  String? get error => _error;

  Future<void> load({bool forceRefresh = false}) {
    if (_loadOperation != null) return _loadOperation!;
    _loadOperation = _load(forceRefresh: forceRefresh).whenComplete(() {
      _loadOperation = null;
    });
    return _loadOperation!;
  }

  Future<void> _load({required bool forceRefresh}) async {
    final date = _today;
    if (!forceRefresh) {
      final cached = await _nutritionRepository.cachedDailySummary(date: date);
      if (cached != null) {
        _summary = cached.value;
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
      _summary = await _nutritionRepository.refreshDailySummary(
        date: date,
        force: forceRefresh,
      );
      _error = null;
    } catch (error) {
      if (!hadVisibleData) {
        _error = userVisibleErrorMessage(
          error,
          context: UserErrorContext.dashboardLoad,
        );
      }
    } finally {
      _isLoading = false;
      _isRefreshing = false;
      notifyListeners();
    }
  }

  Future<void> correctMealItems(Meal meal, List<MealItem> items) async {
    final previous = _summary;
    final optimisticMeal = mealWithItems(meal, items);
    if (previous != null) {
      _summary = replaceMealInSummary(previous, optimisticMeal);
      unawaited(_nutritionRepository.putCachedDailySummary(_summary!));
    }
    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      final savedMeal = await _nutritionRepository.correctMealItems(
        meal.id,
        items,
      );
      if (_summary != null) {
        _summary = replaceMealInSummary(_summary!, savedMeal);
        await _nutritionRepository.putCachedDailySummary(_summary!);
      }
      _error = null;
    } catch (error) {
      _summary = previous;
      if (previous != null) {
        await _nutritionRepository.putCachedDailySummary(previous);
      }
      _error = userVisibleErrorMessage(
        error,
        context: UserErrorContext.dashboardSave,
      );
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<FoodSearchResult> searchFoods(String query, {int limit = 10}) {
    return _nutritionRepository.searchFoods(query, limit: limit);
  }

  Future<bool> deleteMeal(Meal meal) async {
    final previous = _summary;
    if (previous != null) {
      _summary = removeMealFromSummary(previous, meal.id);
      unawaited(_nutritionRepository.putCachedDailySummary(_summary!));
    }
    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      final deleted = await _nutritionRepository.deleteMeal(
        meal.id,
        confirmed: true,
      );
      if (!deleted) {
        _summary = previous;
        if (previous != null) {
          await _nutritionRepository.putCachedDailySummary(previous);
        }
      }
      _error = null;
      return deleted;
    } catch (error) {
      _summary = previous;
      if (previous != null) {
        await _nutritionRepository.putCachedDailySummary(previous);
      }
      _error = userVisibleErrorMessage(
        error,
        context: UserErrorContext.dashboardSave,
      );
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<bool> updateCalorieTarget(
    int calories, {
    String source = 'manual',
    MacroDistributionConfig? macroConfig,
  }) async {
    final previous = _summary;
    if (previous != null) {
      final optimisticGoals = goalsWithOverrides(
        goalsFromSummary(previous),
        calories: calories,
        calorieTargetSource: source,
        macroConfig: macroConfig,
        macroCalorieTarget: calories,
      );
      _summary = dailySummaryWithGoals(previous, optimisticGoals);
      unawaited(_nutritionRepository.putCachedDailySummary(_summary!));
    }
    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      final goals = await _nutritionRepository.updateDailyGoals(
        calories: calories,
        calorieTargetSource: source,
        macroConfig: macroConfig,
        macroCalorieTarget: calories,
      );
      if (_summary != null) {
        _summary = dailySummaryWithGoals(_summary!, goals);
        await _nutritionRepository.putCachedDailySummary(_summary!);
      }
      _error = null;
      return true;
    } catch (error) {
      _summary = previous;
      if (previous != null) {
        await _nutritionRepository.putCachedDailySummary(previous);
      }
      _error = userVisibleErrorMessage(
        error,
        context: UserErrorContext.dashboardSave,
      );
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<bool> updateDailyWater(double waterConsumedLiters) {
    final nextWater = _normalizedWater(waterConsumedLiters);
    _confirmedWaterSummary ??= _summary;
    _pendingWaterLiters = nextWater;
    _isSavingWater = true;
    if (_summary != null) {
      _summary = dailySummaryWithWater(_summary!, nextWater);
      unawaited(_nutritionRepository.putCachedDailySummary(_summary!));
    }
    _error = null;
    notifyListeners();

    final operation = _waterSaveOperation ??= _flushPendingWater();
    return operation.then((_) => _error == null);
  }

  Future<void> _flushPendingWater() async {
    try {
      while (_pendingWaterLiters != null) {
        final waterToSave = _pendingWaterLiters!;
        _pendingWaterLiters = null;
        final savedSummary = await _nutritionRepository.updateDailyHydration(
          waterConsumedLiters: waterToSave,
        );
        _confirmedWaterSummary = savedSummary;
        _error = null;
        if (_pendingWaterLiters == null) {
          _summary = savedSummary;
          notifyListeners();
        }
      }
    } catch (error) {
      _summary = _confirmedWaterSummary;
      if (_summary != null) {
        await _nutritionRepository.putCachedDailySummary(_summary!);
      }
      _pendingWaterLiters = null;
      _error = userVisibleErrorMessage(
        error,
        context: UserErrorContext.dashboardSave,
      );
      notifyListeners();
    } finally {
      _confirmedWaterSummary = null;
      _waterSaveOperation = null;
      _isSavingWater = false;
      notifyListeners();
    }
  }

  void reset() {
    _summary = null;
    _isLoading = false;
    _isRefreshing = false;
    _isSaving = false;
    _isSavingWater = false;
    _loadOperation = null;
    _waterSaveOperation = null;
    _confirmedWaterSummary = null;
    _pendingWaterLiters = null;
    _error = null;
    notifyListeners();
  }

  double _normalizedWater(double waterConsumedLiters) {
    final goal = roundHydrationLiters(_summary?.hydrationGoalLiters ?? 10);
    final clamped = waterConsumedLiters.clamp(0, goal).toDouble();
    return roundHydrationLiters(clamped);
  }

  Future<CalorieEstimate> estimateCalories({
    required int age,
    required String sex,
    required double heightCm,
    required double weightKg,
    required String activityLevel,
    required String goal,
    String? pace,
  }) {
    return _nutritionRepository.estimateCalories(
      age: age,
      sex: sex,
      heightCm: heightCm,
      weightKg: weightKg,
      activityLevel: activityLevel,
      goal: goal,
      pace: pace,
    );
  }

  String get _today {
    final now = _now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}
