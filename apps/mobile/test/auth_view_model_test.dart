import 'dart:async';

import 'package:cal_tracker_mobile/data/repositories/auth_repository.dart';
import 'package:cal_tracker_mobile/domain/models/auth_models.dart';
import 'package:cal_tracker_mobile/ui/features/auth/view_models/auth_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late _MockAuthRepository repository;
  late AuthViewModel viewModel;

  setUp(() {
    repository = _MockAuthRepository();
    viewModel = AuthViewModel(authRepository: repository);
  });

  test('starts in restoring state before session validation completes', () {
    expect(viewModel.status, AuthStatus.restoring);
    expect(viewModel.isRestoring, isTrue);
    expect(viewModel.hasSession, isFalse);
  });

  test('restoreSession authenticates a valid saved session', () async {
    when(() => repository.restoreSession()).thenAnswer((_) async => _user);

    await viewModel.restoreSession();

    expect(viewModel.status, AuthStatus.authenticated);
    expect(viewModel.hasSession, isTrue);
    expect(viewModel.user, _user);
  });

  test('restoreSession marks missing or invalid sessions unauthenticated',
      () async {
    when(() => repository.restoreSession()).thenAnswer((_) async => null);

    await viewModel.restoreSession();

    expect(viewModel.status, AuthStatus.unauthenticated);
    expect(viewModel.hasSession, isFalse);
    expect(viewModel.user, isNull);
  });

  test('login authenticates and logout clears the session', () async {
    when(() => repository.login(email: 'user@example.com', password: 'secret'))
        .thenAnswer((_) async => _session);
    when(() => repository.logout()).thenAnswer((_) async {});

    await viewModel.login('user@example.com', 'secret');

    expect(viewModel.status, AuthStatus.authenticated);
    expect(viewModel.user, _user);

    await viewModel.logout();

    expect(viewModel.status, AuthStatus.unauthenticated);
    expect(viewModel.user, isNull);
  });

  test('logout invalidates UI state before repository work finishes', () async {
    final remoteLogout = Completer<void>();
    when(() => repository.logout()).thenAnswer((_) => remoteLogout.future);
    viewModel.setUser(_user);

    final logout = viewModel.logout();
    var repositoryFinished = false;
    unawaited(logout.then((_) => repositoryFinished = true));
    await Future<void>.delayed(Duration.zero);

    expect(viewModel.status, AuthStatus.unauthenticated);
    expect(viewModel.hasSession, isFalse);
    expect(viewModel.user, isNull);
    expect(repositoryFinished, isFalse);

    remoteLogout.complete();
    await logout;
  });

  test('duplicate logout calls share one repository operation', () async {
    final remoteLogout = Completer<void>();
    when(() => repository.logout()).thenAnswer((_) => remoteLogout.future);
    viewModel.setUser(_user);

    final first = viewModel.logout();
    final second = viewModel.logout();

    expect(identical(first, second), isTrue);
    verify(() => repository.logout()).called(1);

    remoteLogout.complete();
    await Future.wait([first, second]);
  });

  test('rapid login waits until the previous logout teardown is complete',
      () async {
    final remoteLogout = Completer<void>();
    when(() => repository.logout()).thenAnswer((_) => remoteLogout.future);
    when(() => repository.login(
          email: 'user@example.com',
          password: 'new-session',
        )).thenAnswer((_) async => _session);
    viewModel.setUser(_user);

    final logout = viewModel.logout();
    final login = viewModel.login('user@example.com', 'new-session');
    await Future<void>.delayed(Duration.zero);

    verifyNever(() => repository.login(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ));
    expect(viewModel.status, AuthStatus.unauthenticated);

    remoteLogout.complete();
    await Future.wait([logout, login]);

    verify(() => repository.login(
          email: 'user@example.com',
          password: 'new-session',
        )).called(1);
    expect(viewModel.status, AuthStatus.authenticated);
    expect(viewModel.user, _user);
  });

  test('repository logout failure never restores or errors the local session',
      () async {
    when(() => repository.logout())
        .thenThrow(StateError('unexpected adapter failure'));
    viewModel.setUser(_user);

    await expectLater(viewModel.logout(), completes);

    expect(viewModel.status, AuthStatus.unauthenticated);
    expect(viewModel.user, isNull);
    expect(viewModel.error, isNull);
  });

  test('register leaves the user unauthenticated until email confirmation',
      () async {
    when(() => repository.register(
          email: 'user@example.com',
          password: 'password123',
          displayName: 'Test User',
        )).thenAnswer((_) async {});

    await viewModel.register('user@example.com', 'password123', 'Test User');

    expect(viewModel.status, AuthStatus.unauthenticated);
    expect(viewModel.hasSession, isFalse);
    expect(viewModel.user, isNull);
    expect(viewModel.pendingRegistrationEmail, 'user@example.com');
  });

  test('confirmEmail authenticates with the returned session', () async {
    when(() => repository.confirmEmail('confirmation-token'))
        .thenAnswer((_) async => _session);

    await viewModel.confirmEmail('confirmation-token');

    expect(viewModel.status, AuthStatus.authenticated);
    expect(viewModel.user, _user);
    expect(viewModel.pendingRegistrationEmail, isNull);
  });
}

const _user = AuthUser(
  id: 'user-1',
  email: 'user@example.com',
  displayName: 'Test User',
  trustedModeEnabled: false,
);

const _session = AuthSession(
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
  user: _user,
);
