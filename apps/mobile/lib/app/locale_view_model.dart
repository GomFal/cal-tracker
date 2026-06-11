import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../data/services/app_preferences_repository.dart';
import '../l10n/generated/app_localizations.dart';

class LocaleViewModel extends ChangeNotifier {
  LocaleViewModel({required AppPreferencesRepository preferencesRepository})
      : _preferencesRepository = preferencesRepository;

  final AppPreferencesRepository _preferencesRepository;

  Locale _locale = AppLocalizations.supportedLocales.first;

  Locale get locale => _locale;

  String get localeTag => _locale.toLanguageTag();

  Future<void> load() async {
    final savedCode = await _preferencesRepository.loadLocaleCode();
    final nextLocale = normalizeLocaleTag(savedCode);
    if (nextLocale == _locale) return;
    _locale = nextLocale;
    notifyListeners();
  }

  Future<void> setLocaleTag(String tag) async {
    final nextLocale = normalizeLocaleTag(tag);
    if (nextLocale == _locale) return;
    _locale = nextLocale;
    notifyListeners();
    await _preferencesRepository.saveLocaleCode(nextLocale.toLanguageTag());
  }

  static Locale normalizeLocaleTag(String? tag) {
    final normalizedTag = tag?.trim().replaceAll('_', '-').toLowerCase();
    if (normalizedTag == null || normalizedTag.isEmpty) {
      return AppLocalizations.supportedLocales.first;
    }
    for (final locale in AppLocalizations.supportedLocales) {
      if (locale.toLanguageTag().toLowerCase() == normalizedTag) return locale;
    }
    final languageCode = normalizedTag.split('-').first;
    for (final locale in AppLocalizations.supportedLocales) {
      final supportsBareLanguage = locale.countryCode == null &&
          locale.scriptCode == null &&
          locale.languageCode.toLowerCase() == languageCode;
      if (supportsBareLanguage) return locale;
    }
    return AppLocalizations.supportedLocales.first;
  }
}
