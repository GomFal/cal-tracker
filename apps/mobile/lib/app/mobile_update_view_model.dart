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

  bool get checking => _checking;
  bool get opening => _opening;
  String? get error => _error;
  MobileUpdateCheck? get update => _update;
  bool get shouldShowDialog =>
      !_dialogHandled && (_update?.updateAvailable ?? false);

  Future<void> checkForUpdate() async {
    if (_checking) return;
    _checking = true;
    _error = null;
    notifyListeners();
    try {
      _update = await _updateService.checkForUpdate();
    } on MobileUpdateException catch (caught) {
      _error = caught.message;
    } on Object catch (caught) {
      _error = '$caught';
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  void markDialogHandled() {
    if (_dialogHandled) return;
    _dialogHandled = true;
    notifyListeners();
  }

  Future<void> openUpdate() async {
    final manifest = _update?.manifest;
    if (manifest == null) return;
    _opening = true;
    _error = null;
    notifyListeners();
    try {
      await _updateService.openDownload(manifest);
    } on MobileUpdateException catch (caught) {
      _error = caught.message;
    } on Object catch (caught) {
      _error = '$caught';
    } finally {
      _opening = false;
      notifyListeners();
    }
  }
}
