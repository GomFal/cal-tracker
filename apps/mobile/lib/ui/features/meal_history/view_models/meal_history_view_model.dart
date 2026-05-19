import 'package:flutter/foundation.dart';

import '../../../../data/repositories/nutrition_repository.dart';
import '../../../../domain/models/nutrition_models.dart';
import '../../../core/user_visible_error.dart';

class MealHistoryViewModel extends ChangeNotifier {
  MealHistoryViewModel({
    required NutritionRepository nutritionRepository,
    Duration cacheTtl = const Duration(seconds: 60),
    DateTime Function()? now,
  }) : _nutritionRepository = nutritionRepository,
       _cacheTtl = cacheTtl,
       _now = now ?? DateTime.now;

  final NutritionRepository _nutritionRepository;
  final Duration _cacheTtl;
  final DateTime Function() _now;
  List<DailySummary> _weekSummaries = const [];
  String _selectedDate = _formatDateOnly(DateTime.now());
  bool _isLoading = false;
  bool _hasLoaded = false;
  DateTime? _lastLoadedAt;
  Future<void>? _loadOperation;
  String? _error;

  List<DailySummary> get weekSummaries => _weekSummaries;
  String get selectedDate => _selectedDate;
  DailySummary? get selectedSummary {
    for (final summary in _weekSummaries) {
      if (summary.date == _selectedDate) return summary;
    }
    return _weekSummaries.isEmpty ? null : _weekSummaries.last;
  }

  List<Meal> get meals => selectedSummary?.meals ?? const [];
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> load({bool forceRefresh = false}) {
    final isCacheFresh =
        _lastLoadedAt != null && _now().difference(_lastLoadedAt!) < _cacheTtl;
    if (!forceRefresh && _hasLoaded && isCacheFresh) {
      return Future.value();
    }
    if (_loadOperation != null) return _loadOperation!;

    final showLoading = forceRefresh || !_hasLoaded;
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
      await _loadWeekSummaries();
      if (!_weekSummaries.any((summary) => summary.date == _selectedDate)) {
        _selectedDate = _formatDateOnly(_now());
      }
      _hasLoaded = true;
      _lastLoadedAt = _now();
      _error = null;
    } catch (error) {
      if (showLoading) {
        _error = userVisibleErrorMessage(
          error,
          context: UserErrorContext.mealHistoryLoad,
        );
      }
    } finally {
      if (showLoading) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

  void selectDate(String date) {
    _selectedDate = date;
    notifyListeners();
  }

  Future<void> correctMealItems(Meal meal, List<MealItem> items) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _nutritionRepository.correctMealItems(meal.id, items);
      await _loadWeekSummaries();
      _hasLoaded = true;
      _lastLoadedAt = _now();
      _error = null;
    } catch (error) {
      _error = userVisibleErrorMessage(
        error,
        context: UserErrorContext.mealHistorySave,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteMeal(Meal meal) async {
    _isLoading = true;
    notifyListeners();
    try {
      final deleted = await _nutritionRepository.deleteMeal(
        meal.id,
        confirmed: true,
      );
      if (deleted) {
        await _loadWeekSummaries();
      }
      _hasLoaded = true;
      _lastLoadedAt = _now();
      _error = null;
    } catch (error) {
      _error = userVisibleErrorMessage(
        error,
        context: UserErrorContext.mealHistorySave,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadWeekSummaries() async {
    _weekSummaries = await Future.wait(
      _weekDates(_now()).map(
        (date) =>
            _nutritionRepository.getDailySummary(date: _formatDateOnly(date)),
      ),
    );
  }
}

List<DateTime> _weekDates(DateTime anchor) {
  final today = DateTime(anchor.year, anchor.month, anchor.day);
  final monday = today.subtract(Duration(days: today.weekday - 1));
  return List.generate(7, (index) => monday.add(Duration(days: index)));
}

String _formatDateOnly(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
