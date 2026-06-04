import 'dart:convert';

import '../../domain/models/nutrition_models.dart';
import 'app_preferences_storage.dart';

class CachedNutritionValue<T> {
  const CachedNutritionValue({required this.value, required this.cachedAt});

  final T value;
  final DateTime cachedAt;

  bool isOlderThan(Duration age, DateTime now) {
    return now.difference(cachedAt) > age;
  }
}

class NutritionCacheStore {
  NutritionCacheStore({
    required AppPreferencesStorage storage,
    DateTime Function()? now,
    Duration maxEntryAge = const Duration(days: 7),
  }) : _storage = storage,
       _now = now ?? DateTime.now,
       _maxEntryAge = maxEntryAge;

  static const _schemaVersion = 1;
  static const _keyPrefix = 'nutrition_cache:v1';

  final AppPreferencesStorage _storage;
  final DateTime Function() _now;
  final Duration _maxEntryAge;
  String? _activeUserKey;

  bool get hasActiveUser => _activeUserKey != null;

  void activateUser(String userId) {
    _activeUserKey = base64Url.encode(utf8.encode(userId));
  }

  void deactivateUser() {
    _activeUserKey = null;
  }

  Future<void> clearActiveUserCache() async {
    final userKey = _activeUserKey;
    if (userKey == null) return;
    await _storage.removeWhere(
      (key) => key.startsWith('$_keyPrefix:$userKey:'),
    );
    _activeUserKey = null;
  }

  Future<CachedNutritionValue<DailySummary>?> readDailySummary(String date) {
    return _read(
      'daily_summary:$date',
      (payload) => DailySummary.fromJson(_objectMap(payload)),
    );
  }

  Future<void> writeDailySummary(DailySummary summary) {
    return _write('daily_summary:${summary.date}', summary.toJson());
  }

  Future<CachedNutritionValue<List<MealTemplate>>?> readMealTemplates() {
    return _read(
      'meal_templates',
      (payload) => _objectList(payload).map(MealTemplate.fromJson).toList(),
    );
  }

  Future<void> writeMealTemplates(List<MealTemplate> templates) {
    return _write(
      'meal_templates',
      templates.map((template) => template.toJson()).toList(),
    );
  }

  Future<CachedNutritionValue<List<UsualFood>>?> readUsualFoods() {
    return _read(
      'usual_foods',
      (payload) => _objectList(payload).map(UsualFood.fromJson).toList(),
    );
  }

  Future<void> writeUsualFoods(List<UsualFood> foods) {
    return _write('usual_foods', foods.map((food) => food.toJson()).toList());
  }

  Future<CachedNutritionValue<T>?> _read<T>(
    String cacheKey,
    T Function(Object? payload) decode,
  ) async {
    final storageKey = _storageKey(cacheKey);
    if (storageKey == null) return null;

    final raw = await _storage.readString(storageKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      final envelope = _objectMap(decoded);
      if (envelope['schemaVersion'] != _schemaVersion) {
        await _storage.remove(storageKey);
        return null;
      }
      final cachedAtRaw = envelope['cachedAt'];
      if (cachedAtRaw is! String) {
        await _storage.remove(storageKey);
        return null;
      }
      final cachedAt = DateTime.tryParse(cachedAtRaw);
      if (cachedAt == null || _now().difference(cachedAt) > _maxEntryAge) {
        await _storage.remove(storageKey);
        return null;
      }
      return CachedNutritionValue(
        value: decode(_normalizeJsonValue(envelope['payload'])),
        cachedAt: cachedAt,
      );
    } on Object {
      await _storage.remove(storageKey);
      return null;
    }
  }

  Future<void> _write(String cacheKey, Object? payload) async {
    final storageKey = _storageKey(cacheKey);
    if (storageKey == null) return;
    final envelope = {
      'schemaVersion': _schemaVersion,
      'cachedAt': _now().toUtc().toIso8601String(),
      'payload': payload,
    };
    await _storage.writeString(storageKey, jsonEncode(envelope));
  }

  String? _storageKey(String cacheKey) {
    final userKey = _activeUserKey;
    if (userKey == null) return null;
    return '$_keyPrefix:$userKey:$cacheKey';
  }
}

Object? _normalizeJsonValue(Object? value) {
  if (value is Map) {
    return value.map(
      (key, nestedValue) =>
          MapEntry(key.toString(), _normalizeJsonValue(nestedValue)),
    );
  }
  if (value is List) {
    return value.map(_normalizeJsonValue).toList();
  }
  return value;
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is! Map) {
    throw const FormatException('Expected JSON object');
  }
  return Map<String, Object?>.from(value);
}

List<Map<String, Object?>> _objectList(Object? value) {
  if (value is! List) {
    throw const FormatException('Expected JSON array');
  }
  return value.map(_objectMap).toList();
}
