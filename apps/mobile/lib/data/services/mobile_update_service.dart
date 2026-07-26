import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/models/mobile_update_models.dart';
import 'api_config.dart';
import 'mobile_update_installer.dart';

typedef PackageInfoLoader = Future<PackageInfo> Function();
typedef DownloadDirectoryLoader = Future<Directory> Function();
typedef MobileUpdateProgressCallback = void Function(double progress);

enum MobileUpdateFailureCode {
  checkUnavailable,
  manifestRejected,
  downloadRejected,
  downloadFailed,
  installPermissionRequired,
  installPermissionDenied,
  installFailed,
}

extension MobileUpdateFailureCodePresentation on MobileUpdateFailureCode {
  bool get isUserVisible =>
      this != MobileUpdateFailureCode.checkUnavailable &&
      this != MobileUpdateFailureCode.installPermissionRequired;
}

class MobileUpdateException implements Exception {
  const MobileUpdateException(this.code);

  final MobileUpdateFailureCode code;

  @override
  String toString() => 'MobileUpdateException(${code.name})';
}

class MobileUpdateService {
  MobileUpdateService({
    required ApiConfig apiConfig,
    http.Client? httpClient,
    PackageInfoLoader? packageInfoLoader,
    MobileUpdateInstaller? installer,
    DownloadDirectoryLoader? downloadDirectoryLoader,
    Duration timeout = const Duration(seconds: 4),
    Duration downloadInactivityTimeout = const Duration(seconds: 30),
    Duration installerTimeout = const Duration(seconds: 30),
  })  : _policy = _MobileUpdateTrustPolicy.fromApiBase(apiConfig.baseUrl),
        _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform,
        _installer = installer ?? AndroidMobileUpdateInstaller(),
        _downloadDirectoryLoader =
            downloadDirectoryLoader ?? getTemporaryDirectory,
        _timeout = timeout,
        _downloadInactivityTimeout = downloadInactivityTimeout,
        _installerTimeout = installerTimeout;

  static const _maximumManifestBytes = 64 * 1024;
  static const _maximumApkBytes = 250 * 1024 * 1024;
  static const _updateDirectoryName = 'mobile_updates';

  final _MobileUpdateTrustPolicy? _policy;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final PackageInfoLoader _packageInfoLoader;
  final MobileUpdateInstaller _installer;
  final DownloadDirectoryLoader _downloadDirectoryLoader;
  final Duration _timeout;
  final Duration _downloadInactivityTimeout;
  final Duration _installerTimeout;

  String? get manifestUrl => _policy?.manifestUri.toString();

  Future<MobileUpdateCheck> checkForUpdate() async {
    final policy = _policy;
    if (policy == null || !_installer.isSupported) {
      throw const MobileUpdateException(
        MobileUpdateFailureCode.checkUnavailable,
      );
    }

    final packageInfo = await _loadPackageInfo(
      failureCode: MobileUpdateFailureCode.checkUnavailable,
    );
    if (packageInfo.packageName != policy.packageName) {
      throw const MobileUpdateException(
        MobileUpdateFailureCode.manifestRejected,
      );
    }

    final request = http.Request('GET', policy.manifestUri)
      ..headers[HttpHeaders.acceptHeader] = 'application/json';
    final response = await _sendWithoutRedirects(
      request,
      transportFailure: MobileUpdateFailureCode.checkUnavailable,
      redirectFailure: MobileUpdateFailureCode.manifestRejected,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.stream.drain<void>();
      throw const MobileUpdateException(
        MobileUpdateFailureCode.checkUnavailable,
      );
    }
    if (!_isJsonResponse(response)) {
      await response.stream.drain<void>();
      throw const MobileUpdateException(
        MobileUpdateFailureCode.manifestRejected,
      );
    }

    final body = await _readManifestBody(response);
    final manifest = _decodeManifest(body);
    _validateManifest(manifest, policy);

    final installedVersionCode = int.tryParse(packageInfo.buildNumber);
    if (installedVersionCode == null || installedVersionCode <= 0) {
      throw const MobileUpdateException(
        MobileUpdateFailureCode.checkUnavailable,
      );
    }

    return MobileUpdateCheck(
      installedVersionName: packageInfo.version,
      installedVersionCode: installedVersionCode,
      manifest: manifest,
    );
  }

  Future<bool> canInstallPackages() async {
    if (!_installer.isSupported) return false;
    try {
      return await _installer.canInstallPackages().timeout(_timeout);
    } on Object {
      return false;
    }
  }

  Future<void> downloadAndInstall(
    MobileUpdateManifest manifest, {
    MobileUpdateProgressCallback? onProgress,
    bool requestInstallPermission = true,
  }) async {
    final policy = _policy;
    if (policy == null || !_installer.isSupported) {
      throw const MobileUpdateException(
        MobileUpdateFailureCode.downloadRejected,
      );
    }

    final packageInfo = await _loadPackageInfo(
      failureCode: MobileUpdateFailureCode.downloadFailed,
    );
    final installedVersionCode = int.tryParse(packageInfo.buildNumber);
    if (packageInfo.packageName != policy.packageName ||
        installedVersionCode == null ||
        installedVersionCode <= 0) {
      throw const MobileUpdateException(
        MobileUpdateFailureCode.downloadRejected,
      );
    }

    _validateManifest(manifest, policy);
    if (manifest.versionCode <= installedVersionCode) {
      throw const MobileUpdateException(
        MobileUpdateFailureCode.downloadRejected,
      );
    }

    final apkFile = await _downloadVerifiedApk(
      manifest,
      onProgress: onProgress,
    );
    await _ensureInstallPermission(requestInstallPermission);

    try {
      await _installer
          .installApk(
            filePath: apkFile.path,
            expectedVersionCode: manifest.versionCode,
            expectedSha256: manifest.sha256,
            expectedSizeBytes: manifest.sizeBytes,
          )
          .timeout(_installerTimeout);
    } on MobileUpdateInstallerException catch (error) {
      if (error.code == 'install_permission_required') {
        await _ensureInstallPermission(requestInstallPermission);
      }
      if (const {
        'invalid_arguments',
        'invalid_apk_path',
        'integrity_mismatch',
        'apk_invalid',
        'package_mismatch',
        'version_mismatch',
        'signature_mismatch',
      }.contains(error.code)) {
        throw const MobileUpdateException(
          MobileUpdateFailureCode.downloadRejected,
        );
      }
      throw const MobileUpdateException(
        MobileUpdateFailureCode.installFailed,
      );
    } on Object {
      throw const MobileUpdateException(
        MobileUpdateFailureCode.installFailed,
      );
    }
  }

  Future<void> _ensureInstallPermission(bool requestPermission) async {
    bool allowed;
    try {
      allowed = await _installer.canInstallPackages().timeout(_timeout);
    } on Object {
      throw const MobileUpdateException(
        MobileUpdateFailureCode.installFailed,
      );
    }
    if (allowed) return;
    if (!requestPermission) {
      throw const MobileUpdateException(
        MobileUpdateFailureCode.installPermissionDenied,
      );
    }
    try {
      await _installer.openInstallPermissionSettings().timeout(_timeout);
    } on Object {
      throw const MobileUpdateException(
        MobileUpdateFailureCode.installFailed,
      );
    }
    throw const MobileUpdateException(
      MobileUpdateFailureCode.installPermissionRequired,
    );
  }

  Future<File> _downloadVerifiedApk(
    MobileUpdateManifest manifest, {
    MobileUpdateProgressCallback? onProgress,
  }) async {
    late final Directory updateDirectory;
    try {
      final cacheDirectory = await _downloadDirectoryLoader().timeout(_timeout);
      updateDirectory = Directory(
        '${cacheDirectory.path}${Platform.pathSeparator}$_updateDirectoryName',
      );
      await updateDirectory.create(recursive: true);
    } on Object {
      throw const MobileUpdateException(
        MobileUpdateFailureCode.downloadFailed,
      );
    }

    final apkFile = File(
      '${updateDirectory.path}${Platform.pathSeparator}'
      'bettercalories-update-${manifest.versionCode}.apk',
    );
    if (await _isVerifiedApk(apkFile, manifest, onProgress: onProgress)) {
      return apkFile;
    }

    final partialFile = File('${apkFile.path}.part');
    await _deleteIfPresent(apkFile);
    await _deleteIfPresent(partialFile);

    final request = http.Request('GET', Uri.parse(manifest.apkUrl))
      ..headers[HttpHeaders.acceptHeader] =
          'application/vnd.android.package-archive';
    final response = await _sendWithoutRedirects(
      request,
      transportFailure: MobileUpdateFailureCode.downloadFailed,
      redirectFailure: MobileUpdateFailureCode.downloadRejected,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.stream.drain<void>();
      throw const MobileUpdateException(
        MobileUpdateFailureCode.downloadFailed,
      );
    }
    if (!_isApkResponse(response)) {
      await response.stream.drain<void>();
      throw const MobileUpdateException(
        MobileUpdateFailureCode.downloadRejected,
      );
    }
    final contentLength = response.contentLength;
    if (contentLength != null && contentLength != manifest.sizeBytes) {
      await response.stream.drain<void>();
      throw const MobileUpdateException(
        MobileUpdateFailureCode.downloadRejected,
      );
    }

    RandomAccessFile? output;
    Digest? calculatedDigest;
    final digestOutput = ChunkedConversionSink<Digest>.withCallback((digests) {
      if (digests.length != 1) {
        throw const MobileUpdateException(
          MobileUpdateFailureCode.downloadRejected,
        );
      }
      calculatedDigest = digests.single;
    });
    final digestInput = sha256.startChunkedConversion(digestOutput);
    var receivedBytes = 0;
    try {
      output = await partialFile.open(mode: FileMode.write);
      final chunks = response.stream.timeout(_downloadInactivityTimeout);
      await for (final chunk in chunks) {
        receivedBytes += chunk.length;
        if (receivedBytes > manifest.sizeBytes) {
          throw const MobileUpdateException(
            MobileUpdateFailureCode.downloadRejected,
          );
        }
        digestInput.add(chunk);
        await output.writeFrom(chunk);
        onProgress?.call(receivedBytes / manifest.sizeBytes);
      }
      digestInput.close();
      await output.close();
      output = null;

      if (receivedBytes != manifest.sizeBytes ||
          calculatedDigest?.toString() != manifest.sha256) {
        throw const MobileUpdateException(
          MobileUpdateFailureCode.downloadRejected,
        );
      }
      await partialFile.rename(apkFile.path);
      onProgress?.call(1);
      await _deleteOtherUpdateFiles(updateDirectory, keep: apkFile);
      return apkFile;
    } on MobileUpdateException {
      await output?.close();
      await _deleteIfPresent(partialFile);
      rethrow;
    } on Object {
      await output?.close();
      await _deleteIfPresent(partialFile);
      throw const MobileUpdateException(
        MobileUpdateFailureCode.downloadFailed,
      );
    }
  }

  Future<bool> _isVerifiedApk(
    File apkFile,
    MobileUpdateManifest manifest, {
    MobileUpdateProgressCallback? onProgress,
  }) async {
    try {
      if (!await apkFile.exists() ||
          await apkFile.length() != manifest.sizeBytes) {
        return false;
      }
      final digest = await sha256.bind(apkFile.openRead()).first;
      if (digest.toString() != manifest.sha256) return false;
      onProgress?.call(1);
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> _deleteOtherUpdateFiles(
    Directory directory, {
    required File keep,
  }) async {
    try {
      await for (final entity in directory.list()) {
        if (entity is File && entity.path != keep.path) {
          await entity.delete();
        }
      }
    } on Object {
      // Cache cleanup is best effort and does not invalidate a verified APK.
    }
  }

  Future<void> _deleteIfPresent(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on Object {
      throw const MobileUpdateException(
        MobileUpdateFailureCode.downloadFailed,
      );
    }
  }

  Future<PackageInfo> _loadPackageInfo({
    required MobileUpdateFailureCode failureCode,
  }) async {
    try {
      return await _packageInfoLoader().timeout(_timeout);
    } on Object {
      throw MobileUpdateException(failureCode);
    }
  }

  Future<http.StreamedResponse> _sendWithoutRedirects(
    http.Request request, {
    required MobileUpdateFailureCode transportFailure,
    required MobileUpdateFailureCode redirectFailure,
  }) async {
    request
      ..followRedirects = false
      ..maxRedirects = 0;

    late final http.StreamedResponse response;
    try {
      response = await _httpClient.send(request).timeout(_timeout);
    } on Object {
      throw MobileUpdateException(transportFailure);
    }

    if (response.isRedirect ||
        response.headers.containsKey(HttpHeaders.locationHeader)) {
      await response.stream.drain<void>();
      throw MobileUpdateException(redirectFailure);
    }
    return response;
  }

  Future<String> _readManifestBody(http.StreamedResponse response) async {
    final contentLength = response.contentLength;
    if (contentLength != null && contentLength > _maximumManifestBytes) {
      await response.stream.drain<void>();
      throw const MobileUpdateException(
        MobileUpdateFailureCode.manifestRejected,
      );
    }

    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      bytes.add(chunk);
      if (bytes.length > _maximumManifestBytes) {
        throw const MobileUpdateException(
          MobileUpdateFailureCode.manifestRejected,
        );
      }
    }
    try {
      return utf8.decode(bytes.takeBytes());
    } on FormatException {
      throw const MobileUpdateException(
        MobileUpdateFailureCode.manifestRejected,
      );
    }
  }

  MobileUpdateManifest _decodeManifest(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Manifest root must be an object');
      }
      return MobileUpdateManifest.fromJson(decoded);
    } on FormatException {
      throw const MobileUpdateException(
        MobileUpdateFailureCode.manifestRejected,
      );
    }
  }

  void _validateManifest(
    MobileUpdateManifest manifest,
    _MobileUpdateTrustPolicy policy,
  ) {
    final apkUri = Uri.tryParse(manifest.apkUrl);
    if (manifest.channel != policy.channel ||
        manifest.packageName != policy.packageName ||
        manifest.sizeBytes > _maximumApkBytes ||
        apkUri == null ||
        !_isApprovedApkUri(apkUri, policy)) {
      throw const MobileUpdateException(
        MobileUpdateFailureCode.manifestRejected,
      );
    }
  }

  bool _isApprovedApkUri(Uri uri, _MobileUpdateTrustPolicy policy) {
    return uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        !uri.hasPort &&
        uri.origin == policy.origin &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        uri.pathSegments.length == 2 &&
        uri.pathSegments.first == 'apk' &&
        RegExp(r'^[A-Za-z0-9._-]+\.apk$').hasMatch(uri.pathSegments.last);
  }

  bool _isJsonResponse(http.StreamedResponse response) {
    final contentType = response.headers[HttpHeaders.contentTypeHeader];
    if (contentType == null) return false;
    return contentType.split(';').first.trim().toLowerCase() ==
        'application/json';
  }

  bool _isApkResponse(http.StreamedResponse response) {
    final contentEncoding = response.headers[HttpHeaders.contentEncodingHeader]
        ?.trim()
        .toLowerCase();
    if (contentEncoding != null &&
        contentEncoding.isNotEmpty &&
        contentEncoding != 'identity') {
      return false;
    }
    final contentType = response.headers[HttpHeaders.contentTypeHeader];
    if (contentType == null) return false;
    return switch (contentType.split(';').first.trim().toLowerCase()) {
      'application/vnd.android.package-archive' ||
      'application/octet-stream' =>
        true,
      _ => false,
    };
  }

  void dispose() {
    if (_ownsHttpClient) _httpClient.close();
  }
}

class _MobileUpdateTrustPolicy {
  const _MobileUpdateTrustPolicy({
    required this.channel,
    required this.packageName,
    required this.origin,
  });

  static const production = _MobileUpdateTrustPolicy(
    channel: ApiConfig.productionFlavor,
    packageName: 'app.bettercalories',
    origin: ApiConfig.productionBaseUrl,
  );
  static const development = _MobileUpdateTrustPolicy(
    channel: ApiConfig.developmentFlavor,
    packageName: 'app.bettercalories.dev',
    origin: ApiConfig.developmentBaseUrl,
  );

  final String channel;
  final String packageName;
  final String origin;

  Uri get manifestUri => Uri.parse('$origin/apk/latest.json');

  static _MobileUpdateTrustPolicy? fromApiBase(String apiBase) {
    return switch (apiBase) {
      ApiConfig.productionBaseUrl => production,
      ApiConfig.developmentBaseUrl => development,
      _ => null,
    };
  }
}
