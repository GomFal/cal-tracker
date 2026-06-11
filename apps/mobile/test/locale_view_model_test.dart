import 'package:cal_tracker_mobile/app/locale_view_model.dart';
import 'package:cal_tracker_mobile/data/services/app_preferences_repository.dart';
import 'package:cal_tracker_mobile/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults to English before loading preferences', () {
    final viewModel = LocaleViewModel(
      preferencesRepository: _FakePreferencesRepository(),
    );

    expect(viewModel.locale, AppLocalizations.supportedLocales.first);
    expect(
      viewModel.localeTag,
      AppLocalizations.supportedLocales.first.toLanguageTag(),
    );
  });

  test(
    'load keeps English default without notifying when no preference exists',
    () async {
      final viewModel = LocaleViewModel(
        preferencesRepository: _FakePreferencesRepository(),
      );
      var notifications = 0;
      viewModel.addListener(() => notifications++);

      await viewModel.load();

      expect(viewModel.locale, AppLocalizations.supportedLocales.first);
      expect(notifications, 0);
    },
  );

  test(
    'load applies stored Spanish preference and notifies listeners',
    () async {
      final repository = _FakePreferencesRepository(localeCode: 'es');
      final viewModel = LocaleViewModel(preferencesRepository: repository);
      var notifications = 0;
      viewModel.addListener(() => notifications++);

      await viewModel.load();

      expect(viewModel.locale, const Locale('es'));
      expect(viewModel.localeTag, 'es');
      expect(notifications, 1);
    },
  );

  test('setLocaleTag persists, normalizes, and avoids duplicates', () async {
    final repository = _FakePreferencesRepository();
    final viewModel = LocaleViewModel(preferencesRepository: repository);
    var notifications = 0;
    viewModel.addListener(() => notifications++);

    await viewModel.setLocaleTag('es');

    expect(viewModel.locale, const Locale('es'));
    expect(repository.savedLocaleCodes, ['es']);
    expect(notifications, 1);

    await viewModel.setLocaleTag('es');

    expect(repository.savedLocaleCodes, ['es']);
    expect(notifications, 1);

    await viewModel.setLocaleTag('en-US');

    expect(viewModel.locale, const Locale('en'));
    expect(repository.savedLocaleCodes, ['es', 'en']);
    expect(notifications, 2);
  });
}

class _FakePreferencesRepository implements AppPreferencesRepository {
  _FakePreferencesRepository({this.localeCode});

  String? localeCode;
  final List<String> savedLocaleCodes = [];

  @override
  Future<String?> loadLocaleCode() async => localeCode;

  @override
  Future<void> saveLocaleCode(String code) async {
    localeCode = code;
    savedLocaleCodes.add(code);
  }

  @override
  Future<ThemeMode> loadThemeMode() async => ThemeMode.light;

  @override
  Future<void> saveThemeMode(ThemeMode mode) async {}

  @override
  Future<int> nextAuthHeroIndex({int count = 5}) async => 0;
}
