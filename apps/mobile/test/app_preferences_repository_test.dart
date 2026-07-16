import 'package:cal_tracker_mobile/data/services/app_preferences_repository.dart';
import 'package:cal_tracker_mobile/data/services/app_preferences_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('persists and restores all supported theme modes', () async {
    final repository = AppPreferencesRepository(
      storage: AppPreferencesStorage(),
    );

    await repository.saveThemeMode(ThemeMode.light);
    expect(await repository.loadThemeMode(), ThemeMode.light);

    await repository.saveThemeMode(ThemeMode.dark);
    expect(await repository.loadThemeMode(), ThemeMode.dark);

    await repository.saveThemeMode(ThemeMode.system);
    expect(await repository.loadThemeMode(), ThemeMode.system);
  });
}
