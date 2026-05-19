import 'package:flutter/foundation.dart';

import '../../../../data/repositories/auth_repository.dart';
import '../../../../domain/models/auth_models.dart';
import '../../../core/user_visible_error.dart';

enum AuthErrorSource { login, register, google, session }

class AuthViewModel extends ChangeNotifier {
  AuthViewModel({required AuthRepository authRepository})
    : _authRepository = authRepository;

  final AuthRepository _authRepository;

  AuthUser? _user;
  bool _isLoading = false;
  String? _error;
  AuthErrorSource? _errorSource;

  AuthUser? get user => _user;
  bool get hasSession => _user != null;
  bool get isLoading => _isLoading;
  String? get error => _error;
  AuthErrorSource? get errorSource => _errorSource;

  Future<void> restoreSession() async {
    _setLoading(true);
    try {
      _user = await _authRepository.restoreSession();
      _error = null;
      _errorSource = null;
    } catch (error) {
      _setError(error, AuthErrorSource.session);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> login(String email, String password) async {
    _setLoading(true);
    try {
      _user = (await _authRepository.login(
        email: email,
        password: password,
      )).user;
      _error = null;
      _errorSource = null;
    } catch (error) {
      _setError(error, AuthErrorSource.login);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loginWithGoogle() async {
    _setLoading(true);
    try {
      final session = await _authRepository.loginWithGoogle();
      if (session != null) {
        _user = session.user;
        _error = null;
        _errorSource = null;
      }
    } catch (error) {
      _setError(error, AuthErrorSource.google);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> register(
    String email,
    String password,
    String displayName,
  ) async {
    _setLoading(true);
    try {
      _user = (await _authRepository.register(
        email: email,
        password: password,
        displayName: displayName,
      )).user;
      _error = null;
      _errorSource = null;
    } catch (error) {
      _setError(error, AuthErrorSource.register);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> logout() async {
    await _authRepository.logout();
    _user = null;
    notifyListeners();
  }

  void setUser(AuthUser user) {
    _user = user;
    notifyListeners();
  }

  void clearError() {
    if (_error == null && _errorSource == null) return;
    _error = null;
    _errorSource = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(Object error, AuthErrorSource source) {
    _errorSource = source;
    _error = userVisibleErrorMessage(
      error,
      context: switch (source) {
        AuthErrorSource.login => UserErrorContext.authLogin,
        AuthErrorSource.register => UserErrorContext.authRegister,
        AuthErrorSource.google => UserErrorContext.authGoogle,
        AuthErrorSource.session => UserErrorContext.sessionRestore,
      },
    );
  }
}
