import 'package:cal_tracker_mobile/data/services/app_preferences_storage.dart';
import 'package:cal_tracker_mobile/data/services/nutrition_cache_store.dart';
import 'package:cal_tracker_mobile/domain/models/nutrition_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NutritionCacheStore', () {
    test('persists daily summaries under the active user', () async {
      final storage = _MemoryPreferencesStorage();
      final store = NutritionCacheStore(storage: storage);

      store.activateUser('user-a');
      await store.writeDailySummary(_summary('2026-05-10'));

      final cached = await store.readDailySummary('2026-05-10');
      expect(cached?.value.date, '2026-05-10');

      store.activateUser('user-b');
      expect(await store.readDailySummary('2026-05-10'), isNull);

      store.activateUser('user-a');
      expect((await store.readDailySummary('2026-05-10'))?.value.date,
          '2026-05-10');
    });

    test('expires stale entries and removes them from storage', () async {
      var now = DateTime.utc(2026, 5, 10);
      final storage = _MemoryPreferencesStorage();
      final store = NutritionCacheStore(
        storage: storage,
        now: () => now,
        maxEntryAge: const Duration(days: 1),
      );
      store.activateUser('user-a');
      await store.writeMealTemplates([_template('template-1')]);
      expect(storage.values, hasLength(1));

      now = now.add(const Duration(days: 2));

      expect(await store.readMealTemplates(), isNull);
      expect(storage.values, isEmpty);
    });

    test('clears only the active user cache', () async {
      final storage = _MemoryPreferencesStorage();
      final store = NutritionCacheStore(storage: storage);

      store.activateUser('user-a');
      await store.writeDailySummary(_summary('2026-05-10'));
      store.activateUser('user-b');
      await store.writeDailySummary(_summary('2026-05-11'));

      await store.clearActiveUserCache();

      store.activateUser('user-a');
      expect(await store.readDailySummary('2026-05-10'), isNotNull);
      store.activateUser('user-b');
      expect(await store.readDailySummary('2026-05-11'), isNull);
    });
  });
}

class _MemoryPreferencesStorage implements AppPreferencesStorage {
  final values = <String, String>{};

  @override
  Future<String?> readString(String key) async => values[key];

  @override
  Future<void> writeString(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<Set<String>> readKeys() async => values.keys.toSet();

  @override
  Future<void> removeWhere(bool Function(String key) test) async {
    values.removeWhere((key, value) => test(key));
  }
}

const _nutrition = NutritionSnapshot(
  calories: 400,
  proteinGrams: 30,
  carbsGrams: 45,
  fatGrams: 12,
);

DailySummary _summary(String date) {
  return DailySummary(
    date: date,
    consumed: _nutrition,
    target: _nutrition,
    remaining: _nutrition,
    hydrationGoalLiters: 2,
    waterConsumedLiters: 1,
    calorieTargetConfigured: true,
    calorieTargetSource: 'manual',
    meals: const [],
  );
}

MealTemplate _template(String id) {
  return MealTemplate(
    id: id,
    title: 'Usual lunch',
    trustedAutoCommitEnabled: false,
    nutrition: _nutrition,
    items: const [],
    aliases: const [],
  );
}
