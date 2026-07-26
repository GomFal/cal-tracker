import 'dart:io';

import 'package:flutter/services.dart';

abstract interface class MobileUpdateInstaller {
  bool get isSupported;

  Future<bool> canInstallPackages();

  Future<void> openInstallPermissionSettings();

  Future<void> installApk({
    required String filePath,
    required int expectedVersionCode,
    required String expectedSha256,
    required int expectedSizeBytes,
  });
}

class AndroidMobileUpdateInstaller implements MobileUpdateInstaller {
  AndroidMobileUpdateInstaller({
    MethodChannel? channel,
    bool? supported,
  })  : _channel = channel ?? const MethodChannel(_channelName),
        _supported = supported ?? Platform.isAndroid;

  static const _channelName = 'app.bettercalories/mobile_update_installer';

  final MethodChannel _channel;
  final bool _supported;

  @override
  bool get isSupported => _supported;

  @override
  Future<bool> canInstallPackages() async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
  }

  @override
  Future<void> openInstallPermissionSettings() async {
    if (!isSupported) {
      throw const MobileUpdateInstallerException('unsupported_platform');
    }
    await _channel.invokeMethod<void>('openInstallPermissionSettings');
  }

  @override
  Future<void> installApk({
    required String filePath,
    required int expectedVersionCode,
    required String expectedSha256,
    required int expectedSizeBytes,
  }) async {
    if (!isSupported) {
      throw const MobileUpdateInstallerException('unsupported_platform');
    }
    try {
      await _channel.invokeMethod<void>('installApk', {
        'filePath': filePath,
        'expectedVersionCode': expectedVersionCode,
        'expectedSha256': expectedSha256,
        'expectedSizeBytes': expectedSizeBytes,
      });
    } on PlatformException catch (error) {
      throw MobileUpdateInstallerException(error.code);
    }
  }
}

class MobileUpdateInstallerException implements Exception {
  const MobileUpdateInstallerException(this.code);

  final String code;

  @override
  String toString() => 'MobileUpdateInstallerException($code)';
}
