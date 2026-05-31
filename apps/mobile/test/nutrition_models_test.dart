import 'package:cal_tracker_mobile/domain/models/nutrition_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('usual food update serialization can clear optional fields', () {
    final json = const UsualFoodInput(
      name: 'Rice',
      canonicalName: null,
      brand: null,
      barcode: null,
      servingGrams: 100,
      nutrition: NutritionSnapshot(
        calories: 130,
        proteinGrams: 2.7,
        carbsGrams: 28,
        fatGrams: 0.3,
      ),
      aliases: [],
      nutrients: {},
    ).toJson(includeEmptyOptional: true);

    expect(json, containsPair('canonicalName', null));
    expect(json, containsPair('brand', null));
    expect(json, containsPair('barcode', null));
    expect(json, containsPair('aliases', <String>[]));
    expect(json, containsPair('nutrients', <String, Object?>{}));
  });
}
