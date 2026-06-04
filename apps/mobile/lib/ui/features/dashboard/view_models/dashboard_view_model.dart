import 'package:flutter/foundation.dart';

import '../../../../data/repositories/nutrition_repository.dart';
import '../../../../domain/models/macro_distribution.dart';
import '../../../../domain/models/nutrition_models.dart';
import '../../../core/user_visible_error.dart';
import '../../hydration/hydration_format.dart';

class DashboardViewModel extends ChangeNotifier {
  DashboardViewModel({
    required NutritionRepository nutritionRepository,
    Duration cacheTtl = const Duration(seconds: 60),
    DateTime Function()? now,
  })  : _nutritionRepository = nutritionRepository,
        _cacheTtl = cacheTtl,
        _now = now ?? DateTime.now;

  final NutritionRepository _nutritionRepository;
  final Duration _cacheTtl;
  final DateTime Function() _now;
  DailySummary? _summary;
  bool _isLoading = false;
  bool _isSavingWater = false;
  DateTime? _lastLoadedAt;
  Future<void>? _loadOperation;
  Future<void>? _waterSaveOperation;
  DailySummary? _confirmedWaterSummary;
  double? _pendingWaterLiters;
  String? _error;

  DailySummary? get summary => _summary;
  bool get isLoading => _isLoading && !_isSavingWater;
  String? get error => _error;

  Future<void> load({bool forceRefresh = false}) {
    final isCacheFresh =
        _lastLoadedAt != null && _now().difference(_lastLoadedAt!) < _cacheTtl;
    if (!forceRefresh && _summary != null && isCacheFresh) {
      return Future.value();
    }
    if (_loadOperation != null) return _loadOperation!;

    final showLoading = forceRefresh || _summary == null;
    _loadOperation = _load(showLoading: showLoading).whenComplete(() {
      _loadOperation = null;
    });
    return _loadOperation!;
  }

  Future<void> _load({required bool showLoading}) async {
    if (showLoading) {
      _isLoading = true;
      notifyListeners();
    }
    try {
      _summary = await _nutritionRepository.getDailySummary();
      _lastLoadedAt = _now();
      _error = null;
    } catch (error) {
      if (showLoading) {
        _error = userVisibleErrorMessage(
          error,
          context: UserErrorContext.dashboardLoad,
        );
      }
    } finally {
      if (showLoading) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

  Future<void> correctMealItems(Meal meal, List<MealItem> items) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _nutritionRepository.correctMealItems(meal.id, items);
      _summary = await _nutritionRepository.getDailySummary();
      _lastLoadedAt = _now();
      _error = null;
    } catch (error) {
      _error = userVisibleErrorMessage(
        error,
        context: UserErrorContext.dashboardSave,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<FoodSearchResult> searchFoods(String query, {int limit = 10}) {
    return _nutritionRepository.searchFoods(query, limit: limit);
  }

  Future<bool> deleteMeal(Meal meal) async {
    _isLoading = true;
    notifyListeners();
    try {
      final deleted = await _nutritionRepository.deleteMeal(
        meal.id,
        confirmed: true,
      );
      if (deleted) {
        _summary = await _nutritionRepository.getDailySummary();
        _lastLoadedAt = _now();
      }
      _error = null;
      return deleted;
    } catch (error) {
      _error = userVisibleErrorMessage(
        error,
        context: UserErrorContext.dashboardSave,
      );
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateCalorieTarget(
    int calories, {
    String source = 'manual',
    MacroDistributionConfig? macroConfig,
  }) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _nutritionRepository.updateDailyGoals(
        calories: calories,
        calorieTargetSource: source,
        macroConfig: macroConfig,
        macroCalorieTarget: calories,
      );
      _summary = await _nutritionRepository.getDailySummary();
      _error = null;
      return true;
    } catch (error) {
      _error = userVisibleErrorMessage(
        error,
        context: UserErrorContext.dashboardSave,
      );
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateDailyWater(double waterConsumedLiters) {
    final nextWater = _normalizedWater(waterConsumedLiters);
    _confirmedWaterSummary ??= _summary;
    _pendingWaterLiters = nextWater;
    _isSavingWater = true;
    if (_summary != null) {
      _summary = _summaryWithWater(_summary!, nextWater);
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
        _lastLoadedAt = _now();
        _error = null;
        if (_pendingWaterLiters == null) {
          _summary = savedSummary;
          notifyListeners();
        }
      }
    } catch (error) {
      _summary = _confirmedWaterSummary;
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

  double _normalizedWater(double waterConsumedLiters) {
    final goal = roundHydrationLiters(_summary?.hydrationGoalLiters ?? 10);
    final clamped = waterConsumedLiters.clamp(0, goal).toDouble();
    return roundHydrationLiters(clamped);
  }

  DailySummary _summaryWithWater(
    DailySummary summary,
    double waterConsumedLiters,
  ) {
    return DailySummary(
      date: summary.date,
      consumed: summary.consumed,
      target: summary.target,
      remaining: summary.remaining,
      hydrationGoalLiters: summary.hydrationGoalLiters,
      waterConsumedLiters: waterConsumedLiters,
      calorieTargetConfigured: summary.calorieTargetConfigured,
      calorieTargetSource: summary.calorieTargetSource,
      macroMode: summary.macroMode,
      macroSource: summary.macroSource,
      macroPreset: summary.macroPreset,
      proteinPct: summary.proteinPct,
      carbsPct: summary.carbsPct,
      fatPct: summary.fatPct,
      macroCalories: summary.macroCalories,
      calorieDeltaKcal: summary.calorieDeltaKcal,
      meals: summary.meals,
    );
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
}
