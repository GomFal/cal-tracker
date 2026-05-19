import 'package:flutter/foundation.dart';

import '../../../../data/repositories/nutrition_repository.dart';
import '../../../../domain/models/macro_distribution.dart';
import '../../../../domain/models/nutrition_models.dart';
import '../../../core/user_visible_error.dart';

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
  DateTime? _lastLoadedAt;
  Future<void>? _loadOperation;
  String? _error;

  DailySummary? get summary => _summary;
  bool get isLoading => _isLoading;
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
