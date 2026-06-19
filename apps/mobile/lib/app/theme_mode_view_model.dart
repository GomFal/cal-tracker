import 'package:flutter/material.dart';

import '../data/services/app_preferences_repository.dart';

class ThemeModeViewModel extends ChangeNotifier {
  ThemeModeViewModel({required AppPreferencesRepository preferencesRepository})
      : _preferencesRepository = preferencesRepository;

  final AppPreferencesRepository _preferencesRepository;

  ThemeMode _themeMode = ThemeMode.dark;

  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  Future<void> load() async {
    final savedThemeMode = await _preferencesRepository.loadThemeMode();
    if (savedThemeMode == _themeMode) return;
    _themeMode = savedThemeMode;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    await _preferencesRepository.saveThemeMode(mode);
  }

  Future<void> setDarkMode(bool enabled) {
    return setThemeMode(enabled ? ThemeMode.dark : ThemeMode.light);
  }
}
