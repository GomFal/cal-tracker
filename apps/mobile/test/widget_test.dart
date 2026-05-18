import 'dart:convert';

import 'package:cal_tracker_mobile/app/app.dart';
import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:cal_tracker_mobile/data/services/app_preferences_repository.dart';
import 'package:cal_tracker_mobile/data/services/secure_token_storage.dart';
import 'package:cal_tracker_mobile/ui/core/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('shows auth screen before a stored session exists',
      (tester) async {
    await tester.pumpWidget(
      CalTrackerBootstrap(
        preferencesRepository: _FakePreferencesRepository(),
        tokenStorage: _MemoryTokenStorage(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Better Calories'), findsOneWidget);
    expect(
        find.textContaining('Track your', findRichText: true), findsOneWidget);
    expect(find.textContaining('calories better', findRichText: true),
        findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.byKey(const ValueKey('email_field')), findsOneWidget);
    expect(find.byKey(const ValueKey('google_sign_in_button')), findsOneWidget);
  });

  testWidgets('restores stored session without showing auth screen',
      (tester) async {
    final tokenStorage = _MemoryTokenStorage(
      const StoredTokens(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
      ),
    );
    final paths = <String>[];
    final httpClient = MockClient((request) async {
      paths.add(request.url.path);
      if (request.url.path == '/v1/auth/me') {
        expect(request.headers['authorization'], 'Bearer access-token');
        return http.Response(
          jsonEncode({
            'id': 'user-1',
            'email': 'user@example.com',
            'displayName': 'Ada',
            'trustedModeEnabled': false,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/v1/summary/daily') {
        return http.Response(
          jsonEncode({
            'date': '2026-05-11',
            'consumed': _nutrition(0),
            'target': _nutrition(2200),
            'remaining': _nutrition(2200),
            'hydrationGoalGlasses': 12,
            'calorieTargetConfigured': true,
            'calorieTargetSource': 'manual',
            'meals': <Object?>[],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('Not found', 404);
    });

    await tester.pumpWidget(
      CalTrackerBootstrap(
        apiConfig: const ApiConfig(baseUrl: 'http://localhost'),
        preferencesRepository: _FakePreferencesRepository(),
        tokenStorage: tokenStorage,
        httpClient: httpClient,
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const ValueKey('email_field')), findsNothing);

    await tester.pump();
    await tester.pump();

    expect(paths, contains('/v1/auth/me'));
    expect(find.text('Ada'), findsOneWidget);
    expect(find.byKey(const ValueKey('email_field')), findsNothing);
    expect(find.byKey(const ValueKey('google_sign_in_button')), findsNothing);
  });

  testWidgets('starts in Spanish when saved locale preference is Spanish',
      (tester) async {
    await tester.pumpWidget(
      CalTrackerBootstrap(
        preferencesRepository: _FakePreferencesRepository(
          ThemeMode.light,
          'es',
        ),
        tokenStorage: _MemoryTokenStorage(),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Correo'), findsOneWidget);
    expect(find.textContaining('Controla mejor', findRichText: true),
        findsOneWidget);
  });

  testWidgets('keeps auth screen light when saved theme mode is dark',
      (tester) async {
    await tester.pumpWidget(
      CalTrackerBootstrap(
        preferencesRepository: _FakePreferencesRepository(ThemeMode.dark),
        tokenStorage: _MemoryTokenStorage(),
      ),
    );
    await tester.pump();
    await tester.pump();

    final emailFieldContext =
        tester.element(find.byKey(const ValueKey('email_field')));

    expect(Theme.of(emailFieldContext).brightness, Brightness.light);
    expect(emailFieldContext.freshPalette, FreshPalette.light);
  });
}

Map<String, Object?> _nutrition(int calories) {
  return {
    'calories': calories,
    'proteinGrams': 0,
    'carbsGrams': 0,
    'fatGrams': 0,
  };
}

class _MemoryTokenStorage implements TokenStorage {
  _MemoryTokenStorage([this._tokens]);

  StoredTokens? _tokens;

  @override
  Future<void> clear() async {
    _tokens = null;
  }

  @override
  Future<StoredTokens?> read() async => _tokens;

  @override
  Future<void> write(StoredTokens tokens) async {
    _tokens = tokens;
  }
}

class _FakePreferencesRepository implements AppPreferencesRepository {
  _FakePreferencesRepository([
    this.savedThemeMode = ThemeMode.light,
    this.savedLocaleCode,
  ]);

  ThemeMode savedThemeMode;
  String? savedLocaleCode;
  int nextHeroIndex = 0;

  @override
  Future<ThemeMode> loadThemeMode() async => savedThemeMode;

  @override
  Future<void> saveThemeMode(ThemeMode mode) async {
    savedThemeMode = mode;
  }

  @override
  Future<String?> loadLocaleCode() async => savedLocaleCode;

  @override
  Future<void> saveLocaleCode(String code) async {
    savedLocaleCode = code;
  }

  @override
  Future<int> nextAuthHeroIndex({int count = 5}) async {
    final value = nextHeroIndex % count;
    nextHeroIndex++;
    return value;
  }
}
