import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Source of static client metadata used for telemetry + request headers.
typedef PackageInfoLoader = Future<PackageInfo> Function();

/// Lightweight value object describing non-PII client metadata.
@immutable
class ClientMetadata {
  const ClientMetadata({
    required this.appVersion,
    required this.appBuild,
    required this.platform,
    required this.sessionId,
  });

  final String appVersion;
  final String appBuild;
  final String platform;
  final String sessionId;

  Map<String, String> toHeaderMap() {
    return <String, String>{
      'X-App-Version': appVersion,
      'X-App-Build': appBuild,
      'X-Client-Platform': platform,
      'X-Client-Session-Id': sessionId,
    };
  }
}

/// Provides cached client metadata for the running process.
///
/// Values are computed lazily once per process. The session id is a v4
/// UUID generated on first access and reused for the lifetime of the
/// provider, which is typically the lifetime of the app.
class ClientMetadataProvider {
  ClientMetadataProvider({PackageInfoLoader? packageInfoLoader})
    : _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform;

  final PackageInfoLoader _packageInfoLoader;
  Future<ClientMetadata>? _cached;

  /// Returns the metadata, computing it on first access.
  Future<ClientMetadata> read() {
    return _cached ??= _load();
  }

  /// Test/reset hook for forcing a refresh.
  @visibleForTesting
  void invalidate() {
    _cached = null;
  }

  Future<ClientMetadata> _load() async {
    final info = await _safePackageInfo();
    return ClientMetadata(
      appVersion: info.version,
      appBuild: info.buildNumber,
      platform: _detectPlatform(),
      sessionId: _generateSessionId(),
    );
  }

  Future<PackageInfo> _safePackageInfo() async {
    try {
      return await _packageInfoLoader();
    } on Object {
      // Never let missing package info break the app.
      return PackageInfo(
        appName: 'unknown',
        packageName: 'unknown',
        version: '0.0.0',
        buildNumber: '0',
        buildSignature: '',
      );
    }
  }

  String _detectPlatform() {
    if (kIsWeb) return 'web';
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
      if (Platform.isMacOS) return 'macos';
      if (Platform.isWindows) return 'windows';
      if (Platform.isLinux) return 'linux';
      if (Platform.isFuchsia) return 'fuchsia';
    } on Object {
      // Platform.* can throw on some test harnesses; fall through.
    }
    return 'unknown';
  }

  String _generateSessionId() {
    // RFC 4122 v4 UUID generated without adding new dependencies.
    final now = DateTime.now().microsecondsSinceEpoch;
    final seed = (now ^ (now >> 16)) & 0xFFFFFFFF;
    final bytes = List<int>.generate(16, (i) {
      if (i == 6) {
        return (0x40 | ((seed >> (i * 2)) & 0x0F));
      }
      if (i == 8) {
        return (0x80 | ((seed >> (i * 2)) & 0x3F));
      }
      return (seed >> (i * 3)) & 0xFF;
    }, growable: false);
    final hex = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }
}
