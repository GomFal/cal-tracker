import 'package:flutter/foundation.dart';
import 'dart:io';

import '../../../../data/repositories/nutrition_repository.dart';
import '../../../../domain/models/nutrition_models.dart';
import '../../../core/user_visible_error.dart';

class MealTemplatesViewModel extends ChangeNotifier {
  MealTemplatesViewModel({
    required NutritionRepository nutritionRepository,
    Duration cacheTtl = const Duration(seconds: 60),
    DateTime Function()? now,
  })  : _nutritionRepository = nutritionRepository,
        _cacheTtl = cacheTtl,
        _now = now ?? DateTime.now;

  final NutritionRepository _nutritionRepository;
  final Duration _cacheTtl;
  final DateTime Function() _now;
  List<MealTemplate> _templates = const [];
  List<UsualFood> _usualFoods = const [];
  bool _isLoading = false;
  bool _hasLoaded = false;
  DateTime? _lastLoadedAt;
  Future<void>? _loadOperation;
  String? _error;

  List<MealTemplate> get templates => _templates;
  List<UsualFood> get usualFoods => _usualFoods;
  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  String? get error => _error;

  MealTemplate? templateById(String id) {
    for (final template in _templates) {
      if (template.id == id) return template;
    }
    return null;
  }

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
      _templates = await _nutritionRepository.getTemplates();
      _usualFoods = await _nutritionRepository.getUsualFoods();
      _hasLoaded = true;
      _lastLoadedAt = _now();
      _error = null;
    } catch (error) {
      if (showLoading) {
        _error = userVisibleErrorMessage(
          error,
          context: UserErrorContext.mealTemplatesLoad,
        );
      }
    } finally {
      if (showLoading) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

  Future<void> setTrustedMode(MealTemplate template, bool enabled) async {
    final updated = await _nutritionRepository.setTemplateTrustedMode(
      template,
      enabled,
    );
    _templates = _templates
        .map((item) => item.id == updated.id ? updated : item)
        .toList();
    _hasLoaded = true;
    _lastLoadedAt = _now();
    notifyListeners();
  }

  Future<MealTemplate> createTemplate({
    required String title,
    required List<MealItem> items,
    required List<String> aliases,
  }) async {
    _isLoading = true;
    notifyListeners();
    try {
      final template = await _nutritionRepository.createTemplate(
        title: title,
        items: items,
        aliases: aliases,
        trustedAutoCommitEnabled: false,
      );
      _templates = [..._templates, template];
      _hasLoaded = true;
      _lastLoadedAt = _now();
      _error = null;
      return template;
    } catch (error) {
      _error = userVisibleErrorMessage(
        error,
        context: UserErrorContext.mealTemplatesSave,
      );
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<MealTemplate> updateTemplate(
    MealTemplate template, {
    required String title,
    required List<MealItem> items,
    required List<String> aliases,
  }) async {
    _isLoading = true;
    notifyListeners();
    try {
      final updated = await _nutritionRepository.updateTemplate(
        templateId: template.id,
        title: title,
        items: items,
        aliases: aliases,
        trustedAutoCommitEnabled: false,
      );
      _templates = _templates
          .map((item) => item.id == updated.id ? updated : item)
          .toList();
      _hasLoaded = true;
      _lastLoadedAt = _now();
      _error = null;
      return updated;
    } catch (error) {
      _error = userVisibleErrorMessage(
        error,
        context: UserErrorContext.mealTemplatesSave,
      );
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<UsualMealDraft> draftUsualMeal(String text) {
    return _nutritionRepository.draftUsualMeal(text);
  }

  Future<FoodSearchResult> searchFoods(String query, {int limit = 10}) {
    return _nutritionRepository.searchFoods(query, limit: limit);
  }

  Future<String> transcribeAudio(File audioFile) {
    return _nutritionRepository.transcribeAudio(audioFile);
  }

  Future<String> transcribeUsualFoodAudio(File audioFile) {
    return transcribeAudio(audioFile);
  }

  Future<void> createUsualFood(UsualFoodInput input) async {
    _isLoading = true;
    notifyListeners();
    try {
      final food = await _nutritionRepository.createUsualFood(input);
      _usualFoods = [..._usualFoods, food];
      _hasLoaded = true;
      _lastLoadedAt = _now();
      _error = null;
    } catch (error) {
      _error = userVisibleErrorMessage(error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateUsualFood(UsualFood food, UsualFoodInput input) async {
    _isLoading = true;
    notifyListeners();
    try {
      final updated = await _nutritionRepository.updateUsualFood(
        food.id,
        input,
      );
      _usualFoods = _usualFoods
          .map((item) => item.id == updated.id ? updated : item)
          .toList();
      _hasLoaded = true;
      _lastLoadedAt = _now();
      _error = null;
    } catch (error) {
      _error = userVisibleErrorMessage(error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteUsualFood(UsualFood food) async {
    _isLoading = true;
    notifyListeners();
    try {
      final deleted = await _nutritionRepository.deleteUsualFood(food.id);
      if (deleted) {
        _usualFoods = _usualFoods.where((item) => item.id != food.id).toList();
      }
      _hasLoaded = true;
      _lastLoadedAt = _now();
      _error = null;
    } catch (error) {
      _error = userVisibleErrorMessage(error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<UsualFoodDraft> draftUsualFood(String text) {
    return _nutritionRepository.draftUsualFood(text);
  }

  Future<void> deleteTemplate(MealTemplate template) async {
    _isLoading = true;
    notifyListeners();
    try {
      final deleted = await _nutritionRepository.deleteTemplate(template.id);
      if (deleted) {
        _templates =
            _templates.where((item) => item.id != template.id).toList();
      }
      _hasLoaded = true;
      _lastLoadedAt = _now();
      _error = null;
    } catch (error) {
      _error = userVisibleErrorMessage(
        error,
        context: UserErrorContext.mealTemplatesSave,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
