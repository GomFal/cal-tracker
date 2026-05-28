import 'package:cal_tracker_mobile/app/app.dart';
import 'package:cal_tracker_mobile/data/repositories/auth_repository.dart';
import 'package:cal_tracker_mobile/data/services/app_preferences_repository.dart';
import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:cal_tracker_mobile/data/services/secure_token_storage.dart';
import 'package:cal_tracker_mobile/domain/models/auth_models.dart';
import 'package:cal_tracker_mobile/generated/api/cal_tracker_api.dart';
import 'package:cal_tracker_mobile/ui/core/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows auth screen before a stored session exists',
      (tester) async {
    await _pumpAuthApp(tester, _FakePreferencesRepository());

    expect(
        find.byKey(const ValueKey('auth_brand_better_word')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('auth_brand_calories_word')),
      findsOneWidget,
    );
    final headline = tester.widget<Text>(
      find.byKey(const ValueKey('auth_hero_headline')),
    );
    expect(headline.textSpan?.toPlainText(), 'Track your\ncalories, better.');
    expect(find.byKey(const ValueKey('auth_brand_icon')), findsOneWidget);
    expect(find.byKey(const ValueKey('login_hero_carousel')), findsOneWidget);
    expect(find.byKey(const ValueKey('login_hero_image_0')), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.byKey(const ValueKey('email_field')), findsOneWidget);
    expect(find.byKey(const ValueKey('google_sign_in_button')), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.byKey(const ValueKey('password_field')), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.byKey(const ValueKey('auth_submit_button')), findsOneWidget);
  });

  testWidgets('auth hero carousel advances to the next image', (tester) async {
    await _pumpAuthApp(tester, _FakePreferencesRepository());

    expect(find.byKey(const ValueKey('login_hero_image_0')), findsOneWidget);
    expect(find.byKey(const ValueKey('login_hero_image_1')), findsNothing);

    await tester.pump(const Duration(seconds: 11));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();

    expect(find.byKey(const ValueKey('login_hero_image_1')), findsOneWidget);
  });

  testWidgets('starts in Spanish when saved locale preference is Spanish',
      (tester) async {
    await _pumpAuthApp(
      tester,
      _FakePreferencesRepository(
        ThemeMode.light,
        'es',
      ),
    );

    expect(find.text('Correo'), findsOneWidget);
    final headline = tester.widget<Text>(
      find.byKey(const ValueKey('auth_hero_headline')),
    );
    expect(
      headline.textSpan?.toPlainText().replaceAll('\n', ' '),
      'Controla mejor tus calorías.',
    );
  });

  testWidgets('keeps auth screen light when saved theme mode is dark',
      (tester) async {
    await _pumpAuthApp(
      tester,
      _FakePreferencesRepository(ThemeMode.dark),
    );

    final emailFieldContext =
        tester.element(find.byKey(const ValueKey('email_field')));

    expect(Theme.of(emailFieldContext).brightness, Brightness.light);
    expect(emailFieldContext.freshPalette, FreshPalette.light);
  });
}

Future<void> _pumpAuthApp(
  WidgetTester tester,
  _FakePreferencesRepository preferencesRepository,
) async {
  await tester.pumpWidget(
    CalTrackerBootstrap(
      preferencesRepository: preferencesRepository,
      authRepository: _FakeAuthRepository(),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
      : super(
          apiClient: _unusedApiClient(),
          tokenStorage: _MemoryTokenStorage(),
        );

  @override
  Future<AuthUser?> restoreSession() async => null;
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

class _MemoryTokenStorage implements TokenStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<StoredTokens?> read() async => null;

  @override
  Future<void> write(StoredTokens tokens) async {}
}

CalTrackerApiClient _unusedApiClient() {
  return CalTrackerApiClient(
    config: const ApiConfig(baseUrl: 'http://localhost'),
    tokenStorage: _MemoryTokenStorage(),
  );
}
