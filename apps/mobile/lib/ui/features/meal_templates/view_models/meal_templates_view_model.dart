import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/nutrition_repository.dart';
import '../../../../domain/models/nutrition_models.dart';
import '../../../../domain/models/nutrition_summary_updates.dart';
import '../../../core/user_visible_error.dart';

class MealTemplatesViewModel extends ChangeNotifier {
  MealTemplatesViewModel({
    required NutritionRepository nutritionRepository,
    DateTime Function()? now,
  })  : _nutritionRepository = nutritionRepository,
        _now = now ?? DateTime.now;

  final NutritionRepository _nutritionRepository;
  final DateTime Function() _now;
  List<MealTemplate> _templates = const [];
  List<UsualFood> _usualFoods = const [];
  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _isSaving = false;
  bool _hasLoaded = false;
  Future<void>? _loadOperation;
  String? _error;

  List<MealTemplate> get templates => _templates;
  List<UsualFood> get usualFoods => _usualFoods;
  bool get isLoading => _isLoading && !hasLoaded;
  bool get isRefreshing => _isRefreshing;
  bool get isSaving => _isSaving;
  bool get hasLoaded => _hasLoaded;
  String? get error => _error;

  MealTemplate? templateById(String id) {
    for (final template in _templates) {
      if (template.id == id) return template;
    }
    return null;
  }

  Future<void> load({bool forceRefresh = false}) {
    if (_loadOperation != null) return _loadOperation!;
    _loadOperation = _load(forceRefresh: forceRefresh).whenComplete(() {
      _loadOperation = null;
    });
    return _loadOperation!;
  }

  Future<void> _load({required bool forceRefresh}) async {
    if (!forceRefresh) {
      final cachedTemplates = await _nutritionRepository.cachedTemplates();
      final cachedUsualFoods = await _nutritionRepository.cachedUsualFoods();
      if (cachedTemplates != null || cachedUsualFoods != null) {
        _templates = cachedTemplates?.value ?? _templates;
        _usualFoods = cachedUsualFoods?.value ?? _usualFoods;
        _hasLoaded = true;
        _isLoading = false;
        _error = null;
        notifyListeners();
      }
    }

    final hadVisibleData = hasLoaded;
    if (hadVisibleData) {
      _isRefreshing = true;
    } else {
      _isLoading = true;
    }
    notifyListeners();

    try {
      final results = await Future.wait([
        _nutritionRepository.refreshTemplates(force: forceRefresh),
        _nutritionRepository.refreshUsualFoods(force: forceRefresh),
      ]);
      _templates = results[0] as List<MealTemplate>;
      _usualFoods = results[1] as List<UsualFood>;
      _hasLoaded = true;
      _error = null;
    } catch (error) {
      if (!hadVisibleData) {
        _error = userVisibleErrorMessage(
          error,
          context: UserErrorContext.mealTemplatesLoad,
        );
      }
    } finally {
      _isLoading = false;
      _isRefreshing = false;
      notifyListeners();
    }
  }

  Future<void> setTrustedMode(MealTemplate template, bool enabled) async {
    final previous = _templates;
    final optimistic = MealTemplate(
      id: template.id,
      title: template.title,
      trustedAutoCommitEnabled: enabled,
      nutrition: template.nutrition,
      items: template.items,
      aliases: template.aliases,
    );
    _templates = _templates
        .map((item) => item.id == template.id ? optimistic : item)
        .toList();
    _isSaving = true;
    _error = null;
    unawaited(_nutritionRepository.putCachedTemplates(_templates));
    notifyListeners();

    try {
      final updated = await _nutritionRepository.setTemplateTrustedMode(
        template,
        enabled,
      );
      _templates = _templates
          .map((item) => item.id == updated.id ? updated : item)
          .toList();
      _hasLoaded = true;
      await _nutritionRepository.putCachedTemplates(_templates);
      _error = null;
    } catch (error) {
      _templates = previous;
      await _nutritionRepository.putCachedTemplates(previous);
      _error = userVisibleErrorMessage(
        error,
        context: UserErrorContext.mealTemplatesSave,
      );
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<MealTemplate> createTemplate({
    required String title,
    required List<MealItem> items,
    required List<String> aliases,
  }) async {
    final temporary = mealTemplateWithItems(
      id: _temporaryId('template'),
      title: title,
      trustedAutoCommitEnabled: false,
      items: items,
      aliases: aliases,
    );
    _templates = [..._templates, temporary];
    _hasLoaded = true;
    _isSaving = true;
    _error = null;
    unawaited(_nutritionRepository.putCachedTemplates(_templates));
    notifyListeners();

    try {
      final template = await _nutritionRepository.createTemplate(
        title: title,
        items: items,
        aliases: aliases,
        trustedAutoCommitEnabled: false,
      );
      _templates = _templates
          .map((item) => item.id == temporary.id ? template : item)
          .toList();
      await _nutritionRepository.putCachedTemplates(_templates);
      _error = null;
      return template;
    } catch (error) {
      _templates = _templates.where((item) => item.id != temporary.id).toList();
      await _nutritionRepository.putCachedTemplates(_templates);
      _error = userVisibleErrorMessage(
        error,
        context: UserErrorContext.mealTemplatesSave,
      );
      rethrow;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<MealTemplate> updateTemplate(
    MealTemplate template, {
    required String title,
    required List<MealItem> items,
    required List<String> aliases,
  }) async {
    final previous = _templates;
    final optimistic = mealTemplateWithItems(
      id: template.id,
      title: title,
      trustedAutoCommitEnabled: false,
      items: items,
      aliases: aliases,
    );
    _templates = _templates
        .map((item) => item.id == template.id ? optimistic : item)
        .toList();
    _hasLoaded = true;
    _isSaving = true;
    _error = null;
    unawaited(_nutritionRepository.putCachedTemplates(_templates));
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
      await _nutritionRepository.putCachedTemplates(_templates);
      _error = null;
      return updated;
    } catch (error) {
      _templates = previous;
      await _nutritionRepository.putCachedTemplates(previous);
      _error = userVisibleErrorMessage(
        error,
        context: UserErrorContext.mealTemplatesSave,
      );
      rethrow;
    } finally {
      _isSaving = false;
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

  Future<UsualFood?> createUsualFood(UsualFoodInput input) async {
    final temporary = _usualFoodFromInput(_temporaryId('usual-food'), input);
    _usualFoods = [..._usualFoods, temporary];
    _hasLoaded = true;
    _isSaving = true;
    _error = null;
    unawaited(_nutritionRepository.putCachedUsualFoods(_usualFoods));
    notifyListeners();

    try {
      final food = await _nutritionRepository.createUsualFood(input);
      _usualFoods = _usualFoods
          .map((item) => item.id == temporary.id ? food : item)
          .toList();
      await _nutritionRepository.putCachedUsualFoods(_usualFoods);
      _error = null;
      return food;
    } catch (error) {
      _usualFoods =
          _usualFoods.where((item) => item.id != temporary.id).toList();
      await _nutritionRepository.putCachedUsualFoods(_usualFoods);
      _error = userVisibleErrorMessage(error);
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<UsualFood?> updateUsualFood(
      UsualFood food, UsualFoodInput input) async {
    final previous = _usualFoods;
    final optimistic = _usualFoodFromInput(
      food.id,
      input,
      createdAt: food.createdAt,
      updatedAt: DateTime.now(),
    );
    _usualFoods = _usualFoods
        .map((item) => item.id == food.id ? optimistic : item)
        .toList();
    _hasLoaded = true;
    _isSaving = true;
    _error = null;
    unawaited(_nutritionRepository.putCachedUsualFoods(_usualFoods));
    notifyListeners();

    try {
      final updated = await _nutritionRepository.updateUsualFood(
        food.id,
        input,
      );
      _usualFoods = _usualFoods
          .map((item) => item.id == updated.id ? updated : item)
          .toList();
      await _nutritionRepository.putCachedUsualFoods(_usualFoods);
      _error = null;
      return updated;
    } catch (error) {
      _usualFoods = previous;
      await _nutritionRepository.putCachedUsualFoods(previous);
      _error = userVisibleErrorMessage(error);
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> deleteUsualFood(UsualFood food) async {
    final previous = _usualFoods;
    _usualFoods = _usualFoods.where((item) => item.id != food.id).toList();
    _isSaving = true;
    _error = null;
    unawaited(_nutritionRepository.putCachedUsualFoods(_usualFoods));
    notifyListeners();

    try {
      final deleted = await _nutritionRepository.deleteUsualFood(food.id);
      if (!deleted) {
        _usualFoods = previous;
        await _nutritionRepository.putCachedUsualFoods(previous);
      }
      _hasLoaded = true;
      _error = null;
    } catch (error) {
      _usualFoods = previous;
      await _nutritionRepository.putCachedUsualFoods(previous);
      _error = userVisibleErrorMessage(error);
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<UsualFoodDraft> draftUsualFood(String text) {
    return _nutritionRepository.draftUsualFood(text);
  }

  Future<void> deleteTemplate(MealTemplate template) async {
    final previous = _templates;
    _templates = _templates.where((item) => item.id != template.id).toList();
    _isSaving = true;
    _error = null;
    unawaited(_nutritionRepository.putCachedTemplates(_templates));
    notifyListeners();

    try {
      final deleted = await _nutritionRepository.deleteTemplate(template.id);
      if (!deleted) {
        _templates = previous;
        await _nutritionRepository.putCachedTemplates(previous);
      }
      _hasLoaded = true;
      _error = null;
    } catch (error) {
      _templates = previous;
      await _nutritionRepository.putCachedTemplates(previous);
      _error = userVisibleErrorMessage(
        error,
        context: UserErrorContext.mealTemplatesSave,
      );
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  void reset() {
    _templates = const [];
    _usualFoods = const [];
    _isLoading = false;
    _isRefreshing = false;
    _isSaving = false;
    _hasLoaded = false;
    _loadOperation = null;
    _error = null;
    notifyListeners();
  }

  String _temporaryId(String prefix) {
    return 'pending-$prefix-${_now().microsecondsSinceEpoch}';
  }

  UsualFood _usualFoodFromInput(
    String id,
    UsualFoodInput input, {
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UsualFood(
      id: id,
      name: input.name,
      canonicalName: input.canonicalName,
      brand: input.brand,
      barcode: input.barcode,
      servingGrams: input.servingGrams,
      nutrition: input.nutrition,
      aliases: input.aliases,
      nutrients: input.nutrients,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
