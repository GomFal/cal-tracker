import 'package:flutter/foundation.dart';

import '../../../../data/repositories/nutrition_repository.dart';
import '../../../../domain/models/nutrition_models.dart';
import '../../../core/user_visible_error.dart';

class MealTemplatesViewModel extends ChangeNotifier {
  MealTemplatesViewModel({
    required NutritionRepository nutritionRepository,
    Duration cacheTtl = const Duration(seconds: 60),
    DateTime Function()? now,
  }) : _nutritionRepository = nutritionRepository,
       _cacheTtl = cacheTtl,
       _now = now ?? DateTime.now;

  final NutritionRepository _nutritionRepository;
  final Duration _cacheTtl;
  final DateTime Function() _now;
  List<MealTemplate> _templates = const [];
  bool _isLoading = false;
  bool _hasLoaded = false;
  DateTime? _lastLoadedAt;
  Future<void>? _loadOperation;
  String? _error;

  List<MealTemplate> get templates => _templates;
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
      _templates = await _nutritionRepository.getTemplates();
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

  Future<void> createBasicTemplate({
    required String title,
    required List<String> aliases,
  }) async {
    _isLoading = true;
    notifyListeners();
    try {
      final template = await _nutritionRepository.createTemplate(
        title: title,
        aliases: aliases,
        items: const [
          MealItem(
            name: 'Chicken breast',
            quantity: 150,
            unit: 'g',
            calories: 248,
            proteinGrams: 46.5,
            carbsGrams: 0,
            fatGrams: 5.4,
            source: 'manual',
          ),
          MealItem(
            name: 'Cooked rice',
            quantity: 150,
            unit: 'g',
            calories: 195,
            proteinGrams: 4.1,
            carbsGrams: 42,
            fatGrams: 0.5,
            source: 'manual',
          ),
        ],
      );
      _templates = [..._templates, template];
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

  Future<void> deleteTemplate(MealTemplate template) async {
    _isLoading = true;
    notifyListeners();
    try {
      final deleted = await _nutritionRepository.deleteTemplate(template.id);
      if (deleted) {
        _templates = _templates
            .where((item) => item.id != template.id)
            .toList();
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
