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
