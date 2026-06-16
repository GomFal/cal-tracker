import 'package:flutter/foundation.dart';

import '../data/services/mobile_update_service.dart';
import '../domain/models/mobile_update_models.dart';

class MobileUpdateViewModel extends ChangeNotifier {
  MobileUpdateViewModel({required MobileUpdateService updateService})
      : _updateService = updateService;

  final MobileUpdateService _updateService;

  bool _checking = false;
  bool _opening = false;
  bool _dialogHandled = false;
  String? _error;
  MobileUpdateCheck? _update;
  bool _disposed = false;

  bool get checking => _checking;
  bool get opening => _opening;
  String? get error => _error;
  MobileUpdateCheck? get update => _update;
  bool get shouldShowDialog =>
      !_dialogHandled && (_update?.updateAvailable ?? false);

  Future<void> checkForUpdate() async {
    if (_disposed || _checking) return;
    _checking = true;
    _error = null;
    _notifyListenersIfActive();
    try {
      final update = await _updateService.checkForUpdate();
      if (_disposed) return;
      _update = update;
    } on MobileUpdateException catch (caught) {
      if (_disposed) return;
      _error = caught.message;
    } on Object catch (caught) {
      if (_disposed) return;
      _error = '$caught';
    } finally {
      if (!_disposed) {
        _checking = false;
        _notifyListenersIfActive();
      }
    }
  }

  void markDialogHandled() {
    if (_dialogHandled) return;
    _dialogHandled = true;
    _notifyListenersIfActive();
  }

  Future<void> openUpdate() async {
    final manifest = _update?.manifest;
    if (manifest == null) return;
    _opening = true;
    _error = null;
    _notifyListenersIfActive();
    try {
      await _updateService.openDownload(manifest);
    } on MobileUpdateException catch (caught) {
      _error = caught.message;
    } on Object catch (caught) {
      _error = '$caught';
    } finally {
      if (!_disposed) {
        _opening = false;
        _notifyListenersIfActive();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notifyListenersIfActive() {
    if (!_disposed) notifyListeners();
  }
}
