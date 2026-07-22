import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/nutrition_repository.dart';
import '../../../../data/services/nutrition_cache_store.dart';
import '../../../../domain/models/nutrition_data_change.dart';
import '../../../../domain/models/nutrition_models.dart';
import '../../../../domain/models/nutrition_summary_updates.dart';
import '../../../core/user_visible_error.dart';

class MealHistoryViewModel extends ChangeNotifier {
  MealHistoryViewModel({
    required NutritionRepository nutritionRepository,
    DateTime Function()? now,
  })  : _nutritionRepository = nutritionRepository,
        _now = now ?? DateTime.now,
        _selectedDate = _formatDateOnly((now ?? DateTime.now)()) {
    _dataChangeSubscription = _nutritionRepository.dataChanges.listen(
      _applyDataChange,
    );
  }

  final NutritionRepository _nutritionRepository;
  final DateTime Function() _now;
  List<DailySummary> _weekSummaries = const [];
  String _selectedDate;
  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _hasLoaded = false;
  bool _isSaving = false;
  Future<void>? _loadOperation;
  String? _error;
  late final StreamSubscription<NutritionDataChange> _dataChangeSubscription;
  int _dataGeneration = 0;

  List<DailySummary> get weekSummaries => _weekSummaries;
  String get selectedDate => _selectedDate;
  DailySummary? get selectedSummary {
    for (final summary in _weekSummaries) {
      if (summary.date == _selectedDate) return summary;
    }
    return _weekSummaries.isEmpty ? null : _weekSummaries.last;
  }

  List<Meal> get meals => selectedSummary?.meals ?? const [];
  bool get hasVisibleData => _hasLoaded;
  bool get isLoading => _isLoading && !hasVisibleData;
  bool get isRefreshing => _isRefreshing;
  bool get isSaving => _isSaving;
  String? get error => _error;

  Future<void> load({bool forceRefresh = false}) {
    if (_loadOperation != null) return _loadOperation!;
    _loadOperation = _load(forceRefresh: forceRefresh).whenComplete(() {
      _loadOperation = null;
    });
    return _loadOperation!;
  }

  Future<void> _load({required bool forceRefresh}) async {
    final dataGeneration = _dataGeneration;
    if (!forceRefresh) {
      final cached = await _cachedWeekSummaries();
      if (cached.isNotEmpty) {
        _weekSummaries = cached;
        _hasLoaded = true;
        if (!_weekSummaries.any((summary) => summary.date == _selectedDate)) {
          _selectedDate = _formatDateOnly(_now());
        }
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
      final refreshed = await _loadWeekSummaries(force: forceRefresh);
      if (dataGeneration == _dataGeneration) {
        _weekSummaries = refreshed;
        if (!_weekSummaries.any((summary) => summary.date == _selectedDate)) {
          _selectedDate = _formatDateOnly(_now());
        }
        _hasLoaded = true;
        _error = null;
      }
    } catch (error) {
      if (!hadVisibleData) {
        _error = userVisibleErrorMessage(
          error,
          context: UserErrorContext.mealHistoryLoad,
        );
      }
    } finally {
      _isLoading = false;
      _isRefreshing = false;
      notifyListeners();
    }
  }

  void selectDate(String date) {
    _selectedDate = date;
    notifyListeners();
  }

  Future<void> correctMealItems(Meal meal, List<MealItem> items) async {
    final previous = _weekSummaries;
    final optimisticMeal = mealWithItems(meal, items);
    _weekSummaries = _replaceMealInWeek(_weekSummaries, optimisticMeal);
    _isSaving = true;
    _error = null;
    _persistWeekSummaries(_weekSummaries);
    notifyListeners();

    try {
      final savedMeal = await _nutritionRepository.correctMealItems(
        meal.id,
        items,
      );
      _weekSummaries = _replaceMealInWeek(_weekSummaries, savedMeal);
      _hasLoaded = true;
      _persistWeekSummaries(_weekSummaries);
      _error = null;
    } catch (error) {
      _weekSummaries = previous;
      _persistWeekSummaries(previous);
      _error = userVisibleErrorMessage(
        error,
        context: UserErrorContext.mealHistorySave,
      );
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> deleteMeal(Meal meal) async {
    final previous = _weekSummaries;
    _weekSummaries = _removeMealFromWeek(_weekSummaries, meal.id);
    _isSaving = true;
    _error = null;
    _persistWeekSummaries(_weekSummaries);
    notifyListeners();

    try {
      final deleted = await _nutritionRepository.deleteMeal(
        meal.id,
        confirmed: true,
      );
      if (!deleted) {
        _weekSummaries = previous;
        _persistWeekSummaries(previous);
      }
      _hasLoaded = true;
      _error = null;
    } catch (error) {
      _weekSummaries = previous;
      _persistWeekSummaries(previous);
      _error = userVisibleErrorMessage(
        error,
        context: UserErrorContext.mealHistorySave,
      );
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  void _applyDataChange(NutritionDataChange change) {
    if (!_hasLoaded) return;
    var changed = false;
    final summaries = [..._weekSummaries];
    for (final effect in change.effects) {
      if (effect.domain != NutritionDataDomain.dailySummary) continue;
      final summary = effect.dailySummary;
      if (summary == null) continue;
      final index = summaries.indexWhere((item) => item.date == summary.date);
      if (index < 0) continue;
      summaries[index] = summary;
      changed = true;
    }
    if (!changed) return;
    _dataGeneration++;
    _weekSummaries = summaries;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _dataChangeSubscription.cancel();
    super.dispose();
  }

  void reset() {
    _weekSummaries = const [];
    _selectedDate = _formatDateOnly(_now());
    _isLoading = false;
    _isRefreshing = false;
    _hasLoaded = false;
    _isSaving = false;
    _loadOperation = null;
    _error = null;
    notifyListeners();
  }

  Future<List<DailySummary>> _cachedWeekSummaries() async {
    final dates = _weekDates(_now()).map(_formatDateOnly).toList();
    final cached = await Future.wait(
      dates.map((date) => _nutritionRepository.cachedDailySummary(date: date)),
    );
    return cached
        .whereType<CachedNutritionValue<DailySummary>>()
        .map((value) => value.value)
        .toList(growable: false);
  }

  Future<List<DailySummary>> _loadWeekSummaries({required bool force}) async {
    return Future.wait(
      _weekDates(_now()).map(
        (date) => _nutritionRepository.refreshDailySummary(
          date: _formatDateOnly(date),
          force: force,
        ),
      ),
    );
  }

  void _persistWeekSummaries(List<DailySummary> summaries) {
    for (final summary in summaries) {
      unawaited(_nutritionRepository.putCachedDailySummary(summary));
    }
  }

  List<DailySummary> _replaceMealInWeek(
    List<DailySummary> summaries,
    Meal meal,
  ) {
    return summaries.map((summary) {
      if (!summary.meals.any((item) => item.id == meal.id)) return summary;
      return replaceMealInSummary(summary, meal);
    }).toList();
  }

  List<DailySummary> _removeMealFromWeek(
    List<DailySummary> summaries,
    String mealId,
  ) {
    return summaries.map((summary) {
      if (!summary.meals.any((meal) => meal.id == mealId)) return summary;
      return removeMealFromSummary(summary, mealId);
    }).toList();
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
