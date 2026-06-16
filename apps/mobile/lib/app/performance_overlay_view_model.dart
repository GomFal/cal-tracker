import 'package:flutter/foundation.dart';

class PerformanceOverlayViewModel extends ChangeNotifier {
  bool _visible = false;

  bool get visible => _visible;

  void setVisible(bool visible) {
    if (visible == _visible) return;
    _visible = visible;
    notifyListeners();
  }

  void toggle() {
    setVisible(!_visible);
  }
}
