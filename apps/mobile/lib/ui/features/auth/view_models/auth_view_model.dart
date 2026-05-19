import 'package:flutter/foundation.dart';

import '../../../../data/repositories/auth_repository.dart';
import '../../../../domain/models/auth_models.dart';

enum AuthStatus {
  restoring,
  authenticated,
  unauthenticated,
}

class AuthViewModel extends ChangeNotifier {
  AuthViewModel({required AuthRepository authRepository})
      : _authRepository = authRepository;

  final AuthRepository _authRepository;

  AuthUser? _user;
  AuthStatus _status = AuthStatus.restoring;
  bool _isLoading = false;
  String? _error;

  AuthUser? get user => _user;
  AuthStatus get status => _status;
  bool get hasSession => _status == AuthStatus.authenticated && _user != null;
  bool get isRestoring => _status == AuthStatus.restoring;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> restoreSession() async {
    _status = AuthStatus.restoring;
    _setLoading(true);
    try {
      _user = await _authRepository.restoreSession();
      _status =
          _user == null ? AuthStatus.unauthenticated : AuthStatus.authenticated;
      _error = null;
    } catch (error) {
      _user = null;
      _status = AuthStatus.unauthenticated;
      _error = error.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> login(String email, String password) async {
    _setLoading(true);
    try {
      _user =
          (await _authRepository.login(email: email, password: password)).user;
      _status = AuthStatus.authenticated;
      _error = null;
    } catch (error) {
      _user = null;
      _status = AuthStatus.unauthenticated;
      _error = error.toString();
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
        _status = AuthStatus.authenticated;
        _error = null;
      } else if (_user == null) {
        _status = AuthStatus.unauthenticated;
      }
    } catch (error) {
      if (_user == null) {
        _status = AuthStatus.unauthenticated;
      }
      _error = error.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> register(
      String email, String password, String displayName) async {
    _setLoading(true);
    try {
      _user = (await _authRepository.register(
              email: email, password: password, displayName: displayName))
          .user;
      _status = AuthStatus.authenticated;
      _error = null;
    } catch (error) {
      _user = null;
      _status = AuthStatus.unauthenticated;
      _error = error.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> logout() async {
    await _authRepository.logout();
    _user = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  void setUser(AuthUser user) {
    _user = user;
    _status = AuthStatus.authenticated;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
