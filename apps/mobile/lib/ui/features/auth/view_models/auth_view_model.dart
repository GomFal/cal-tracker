import 'package:flutter/foundation.dart';

import '../../../../data/repositories/auth_repository.dart';
import '../../../../domain/models/auth_models.dart';

class AuthViewModel extends ChangeNotifier {
  AuthViewModel({required AuthRepository authRepository})
      : _authRepository = authRepository;

  final AuthRepository _authRepository;

  AuthUser? _user;
  bool _isLoading = false;
  bool _isRestoringSession = false;
  String? _error;

  AuthUser? get user => _user;
  bool get hasSession => _user != null;
  bool get isLoading => _isLoading;
  bool get isRestoringSession => _isRestoringSession;
  String? get error => _error;

  Future<void> restoreSession() async {
    _isRestoringSession = true;
    _setLoading(true);
    try {
      _user = await _authRepository.restoreSession();
      _error = null;
    } catch (error) {
      _error = error.toString();
    } finally {
      _isRestoringSession = false;
      _setLoading(false);
    }
  }

  Future<void> login(String email, String password) async {
    _setLoading(true);
    try {
      _user =
          (await _authRepository.login(email: email, password: password)).user;
      _error = null;
    } catch (error) {
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
        _error = null;
      }
    } catch (error) {
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
      _error = null;
    } catch (error) {
      _error = error.toString();
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

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
