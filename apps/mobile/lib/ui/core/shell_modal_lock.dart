import 'package:flutter/material.dart';

class ShellModalLockController extends ChangeNotifier {
  final Set<Route<dynamic>> _popupRoutes = <Route<dynamic>>{};
  bool _isLocked = false;

  bool get isLocked => _isLocked;

  void track(Route<dynamic> route) {
    if (route is! PopupRoute<dynamic>) return;
    _popupRoutes.add(route);
    _sync();
  }

  void untrack(Route<dynamic> route) {
    if (!_popupRoutes.remove(route)) return;
    _sync();
  }

  void replace({
    Route<dynamic>? newRoute,
    Route<dynamic>? oldRoute,
  }) {
    if (oldRoute != null) {
      _popupRoutes.remove(oldRoute);
    }
    if (newRoute is PopupRoute<dynamic>) {
      _popupRoutes.add(newRoute);
    }
    _sync();
  }

  void _sync() {
    final value = _popupRoutes.isNotEmpty;
    if (_isLocked == value) return;
    _isLocked = value;
    notifyListeners();
  }
}

class ShellModalLockObserver extends NavigatorObserver {
  ShellModalLockObserver(this.controller);

  final ShellModalLockController controller;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    controller.track(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    controller.untrack(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    controller.untrack(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    controller.replace(newRoute: newRoute, oldRoute: oldRoute);
  }
}
