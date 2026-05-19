import 'package:flutter/foundation.dart';

import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/nutrition_repository.dart';
import '../../../../domain/models/auth_models.dart';
import '../../../../domain/models/nutrition_models.dart';
import '../../../core/user_visible_error.dart';

class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel({
    required AuthRepository authRepository,
    required NutritionRepository nutritionRepository,
  }) : _authRepository = authRepository,
       _nutritionRepository = nutritionRepository;

  final AuthRepository _authRepository;
  final NutritionRepository _nutritionRepository;
  DailyGoals? _goals;
  bool _isLoading = false;
  String? _error;

  DailyGoals? get goals => _goals;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    try {
      final summary = await _nutritionRepository.getDailySummary();
      _goals = DailyGoals(
        date: summary.date,
        target: summary.target,
        hydrationGoalGlasses: summary.hydrationGoalGlasses,
        calorieTargetConfigured: summary.calorieTargetConfigured,
        calorieTargetSource: summary.calorieTargetSource,
      );
      _error = null;
    } catch (error) {
      _error = userVisibleErrorMessage(
        error,
        context: UserErrorContext.settingsLoad,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<DailyGoals?> updateGoals({
    int? calories,
    int? hydrationGoalGlasses,
    String? calorieTargetSource,
  }) async {
    _isLoading = true;
    notifyListeners();
    try {
      final goals = await _nutritionRepository.updateDailyGoals(
        calories: calories,
        hydrationGoalGlasses: hydrationGoalGlasses,
        calorieTargetSource: calorieTargetSource,
      );
      _goals = goals;
      _error = null;
      return goals;
    } catch (error) {
      _error = userVisibleErrorMessage(
        error,
        context: UserErrorContext.settingsSave,
      );
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<AuthUser?> setTrustedMode(bool enabled) async {
    _isLoading = true;
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
      _isLoading = false;
      notifyListeners();
    }
  }
}
