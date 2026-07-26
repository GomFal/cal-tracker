import 'package:flutter/foundation.dart';

import '../data/services/mobile_update_service.dart';
import '../domain/models/mobile_update_models.dart';

class MobileUpdateViewModel extends ChangeNotifier {
  MobileUpdateViewModel({required MobileUpdateService updateService})
      : _updateService = updateService;

  final MobileUpdateService _updateService;

  bool _checking = false;
  bool _opening = false;
  bool _resumingPermission = false;
  bool _awaitingInstallPermission = false;
  double? _downloadProgress;
  bool _dialogHandled = false;
  MobileUpdateFailureCode? _error;
  MobileUpdateCheck? _update;
  bool _disposed = false;

  bool get checking => _checking;
  bool get opening => _opening;
  bool get awaitingInstallPermission => _awaitingInstallPermission;
  double? get downloadProgress => _downloadProgress;
  MobileUpdateFailureCode? get error => _error;
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
      _error = caught.code;
    } on Object {
      if (_disposed) return;
      _error = MobileUpdateFailureCode.checkUnavailable;
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
    await _installUpdate(requestInstallPermission: true);
  }

  Future<void> resumePendingInstallation() async {
    if (_disposed ||
        !_awaitingInstallPermission ||
        _opening ||
        _resumingPermission) {
      return;
    }
    _resumingPermission = true;
    final permissionGranted = await _updateService.canInstallPackages();
    if (_disposed) return;
    _resumingPermission = false;
    if (!permissionGranted) {
      _awaitingInstallPermission = false;
      _error = MobileUpdateFailureCode.installPermissionDenied;
      _notifyListenersIfActive();
      return;
    }
    _awaitingInstallPermission = false;
    await _installUpdate(requestInstallPermission: false);
  }

  Future<void> _installUpdate({
    required bool requestInstallPermission,
  }) async {
    final manifest = _update?.manifest;
    if (manifest == null || _opening) return;
    _opening = true;
    _downloadProgress = null;
    _error = null;
    _notifyListenersIfActive();
    try {
      await _updateService.downloadAndInstall(
        manifest,
        requestInstallPermission: requestInstallPermission,
        onProgress: _setDownloadProgress,
      );
      _awaitingInstallPermission = false;
    } on MobileUpdateException catch (caught) {
      if (caught.code == MobileUpdateFailureCode.installPermissionRequired) {
        _awaitingInstallPermission = true;
      } else {
        _awaitingInstallPermission = false;
        _error = caught.code;
      }
    } on Object {
      _awaitingInstallPermission = false;
      _error = MobileUpdateFailureCode.installFailed;
    } finally {
      if (!_disposed) {
        _opening = false;
        _downloadProgress = null;
        _notifyListenersIfActive();
      }
    }
  }

  void clearError(MobileUpdateFailureCode error) {
    if (_error != error) return;
    _error = null;
    _notifyListenersIfActive();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notifyListenersIfActive() {
    if (!_disposed) notifyListeners();
  }

  void _setDownloadProgress(double progress) {
    if (_disposed) return;
    final normalized = progress.clamp(0, 1).toDouble();
    final previous = _downloadProgress;
    if (previous != null &&
        normalized < 1 &&
        (normalized - previous).abs() < 0.01) {
      return;
    }
    _downloadProgress = normalized;
    _notifyListenersIfActive();
  }
}
