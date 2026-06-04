import 'package:flutter/material.dart';

import 'app_preferences_storage.dart';

class AppPreferencesRepository {
  const AppPreferencesRepository({required AppPreferencesStorage storage})
      : _storage = storage;

  static const _themeModeKey = 'theme_mode';
  static const _themeModeLight = 'light';
  static const _themeModeDark = 'dark';
  static const _themeModeSystem = 'system';
  static const _authHeroIndexKey = 'auth_hero_index';
  static const _localeCodeKey = 'app_locale';

  final AppPreferencesStorage _storage;

  Future<ThemeMode> loadThemeMode() async {
    final value = await _storage.readString(_themeModeKey);
    return switch (value) {
      _themeModeDark => ThemeMode.dark,
      _themeModeSystem => ThemeMode.system,
      _ => ThemeMode.system,
    };
  }

  Future<void> saveThemeMode(ThemeMode mode) {
    final value = switch (mode) {
      ThemeMode.dark => _themeModeDark,
      ThemeMode.system => _themeModeSystem,
      ThemeMode.light => _themeModeLight,
    };
    return _storage.writeString(_themeModeKey, value);
  }

  Future<String?> loadLocaleCode() {
    return _storage.readString(_localeCodeKey);
  }

  Future<void> saveLocaleCode(String code) {
    return _storage.writeString(_localeCodeKey, code);
  }

  Future<int> nextAuthHeroIndex({int count = 5}) async {
    final rawValue = await _storage.readString(_authHeroIndexKey);
    final current = int.tryParse(rawValue ?? '') ?? -1;
    final next = (current + 1) % count;
    await _storage.writeString(_authHeroIndexKey, '$next');
    return next;
  }
}
