import 'package:cal_tracker_mobile/app/theme.dart';
import 'package:cal_tracker_mobile/data/repositories/auth_repository.dart';
import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:cal_tracker_mobile/data/services/secure_token_storage.dart';
import 'package:cal_tracker_mobile/domain/models/auth_models.dart';
import 'package:cal_tracker_mobile/generated/api/cal_tracker_api.dart';
import 'package:cal_tracker_mobile/l10n/generated/app_localizations.dart';
import 'package:cal_tracker_mobile/ui/features/auth/view_models/auth_view_model.dart';
import 'package:cal_tracker_mobile/ui/features/auth/views/auth_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _testEmail = 'new-user@example.com';
const _testPassword = 'correct-horse-battery';
const _testDisplayName = 'New User';

void main() {
  testWidgets('authentication fields start empty in login and register modes', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();
    await tester.pumpWidget(_AuthTestApp(repository: repository));
    await tester.pump();

    expect(_fieldText(tester, 'email_field'), isEmpty);
    expect(_fieldText(tester, 'password_field'), isEmpty);

    await _tapVisible(tester, const ValueKey('auth_toggle_mode_button'));
    await tester.pump();

    expect(_fieldText(tester, 'display_name_field'), isEmpty);
    expect(_fieldText(tester, 'email_field'), isEmpty);
    expect(_fieldText(tester, 'password_field'), isEmpty);
  });

  testWidgets(
    'registration validates malformed emails before calling the API',
    (tester) async {
      final repository = _FakeAuthRepository();
      await tester.pumpWidget(_AuthTestApp(repository: repository));
      await tester.pump();

      await _tapVisible(tester, const ValueKey('auth_toggle_mode_button'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('email_field')),
        'demo444422iii§@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('password_field')),
        _testPassword,
      );
      await tester.enterText(
        find.byKey(const ValueKey('display_name_field')),
        _testDisplayName,
      );
      await _tapVisible(tester, const ValueKey('auth_submit_button'));
      await tester.pump();

      expect(
        find.text('Enter a valid email address, like name@example.com.'),
        findsOneWidget,
      );
      expect(repository.registerCalls, 0);
      expect(find.textContaining('ApiException'), findsNothing);
    },
  );

  testWidgets('registration errors do not expose account existence', (
    tester,
  ) async {
    final repository = _FakeAuthRepository(
      registerError: const ApiException(
        409,
        'An account already exists for this email',
        code: 'email_already_registered',
        traceId: 'trace-secret',
      ),
    );
    await tester.pumpWidget(_AuthTestApp(repository: repository));
    await tester.pump();

    await _tapVisible(tester, const ValueKey('auth_toggle_mode_button'));
    await tester.pump();
    await _enterRegistrationCredentials(tester);
    await _tapVisible(tester, const ValueKey('auth_submit_button'));
    await tester.pump();

    expect(find.text('Account creation failed'), findsOneWidget);
    expect(
      find.text('We could not create your account. Try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('already exists'), findsNothing);
    expect(find.textContaining('ApiException'), findsNothing);
    expect(find.textContaining('409'), findsNothing);
    expect(find.textContaining('trace-secret'), findsNothing);
  });

  testWidgets('successful registration shows check email notice', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();
    await tester.pumpWidget(_AuthTestApp(repository: repository));
    await tester.pump();

    await _tapVisible(tester, const ValueKey('auth_toggle_mode_button'));
    await tester.pump();
    await _enterRegistrationCredentials(tester);
    await _tapVisible(tester, const ValueKey('auth_submit_button'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('auth_check_email_banner')),
      findsOneWidget,
    );
    expect(find.text('Check your email'), findsOneWidget);
    expect(
      find.text(
        'If this address can be used, you’ll receive an email with the next step. Check your spam folder too.',
      ),
      findsOneWidget,
    );
    expect(repository.registerCalls, 1);
  });

  testWidgets('login failure hides account lookup details', (tester) async {
    final repository = _FakeAuthRepository(
      loginError: const ApiException(
        401,
        'Invalid email or password',
        code: 'invalid_credentials',
      ),
    );
    await tester.pumpWidget(_AuthTestApp(repository: repository));
    await tester.pump();

    await _enterLoginCredentials(tester);
    await _tapVisible(tester, const ValueKey('auth_submit_button'));
    await tester.pump();

    expect(find.text('Sign in failed'), findsOneWidget);
    expect(find.text('Email or password does not match.'), findsOneWidget);
    expect(find.textContaining('invalid_credentials'), findsNothing);
    expect(find.textContaining('401'), findsNothing);
  });

  testWidgets('login before confirmation asks the user to check email', (
    tester,
  ) async {
    final repository = _FakeAuthRepository(
      loginError: const ApiException(
        403,
        'Confirm your email before signing in.',
        code: 'email_not_verified',
      ),
    );
    await tester.pumpWidget(_AuthTestApp(repository: repository));
    await tester.pump();

    await _enterLoginCredentials(tester);
    await _tapVisible(tester, const ValueKey('auth_submit_button'));
    await tester.pump();

    expect(find.text('Sign in failed'), findsOneWidget);
    expect(
      find.text('Check your email and confirm your account before signing in.'),
      findsOneWidget,
    );
  });
}

String _fieldText(WidgetTester tester, String key) {
  return tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;
}

Future<void> _enterLoginCredentials(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('email_field')),
    _testEmail,
  );
  await tester.enterText(
    find.byKey(const ValueKey('password_field')),
    _testPassword,
  );
}

Future<void> _enterRegistrationCredentials(WidgetTester tester) async {
  await _enterLoginCredentials(tester);
  await tester.enterText(
    find.byKey(const ValueKey('display_name_field')),
    _testDisplayName,
  );
}

Future<void> _tapVisible(WidgetTester tester, ValueKey<String> key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder.hitTestable());
}

class _AuthTestApp extends StatelessWidget {
  const _AuthTestApp({required this.repository});

  final _FakeAuthRepository repository;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthViewModel(authRepository: repository),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildLightTheme(),
        home: const AuthScreen(),
      ),
    );
  }
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({this.loginError, this.registerError})
      : super(
            apiClient: _unusedApiClient(), tokenStorage: _MemoryTokenStorage());

  final Object? loginError;
  final Object? registerError;
  int registerCalls = 0;

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    if (loginError != null) throw loginError!;
    return _session(email);
  }

  @override
  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    registerCalls += 1;
    if (registerError != null) throw registerError!;
  }

  @override
  Future<AuthSession> confirmEmail(String token) async =>
      _session('demo@example.com');

  @override
  Future<AuthSession?> loginWithGoogle() async => null;

  @override
  Future<AuthUser?> restoreSession() async => null;
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

AuthSession _session(String email, {String displayName = 'Test User'}) {
  return AuthSession(
    accessToken: 'access-token',
    refreshToken: 'refresh-token',
    user: AuthUser(
      id: 'user-id',
      email: email,
      displayName: displayName,
      trustedModeEnabled: false,
    ),
  );
}
