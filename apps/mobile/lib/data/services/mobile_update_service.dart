import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/models/mobile_update_models.dart';
import 'api_config.dart';

typedef PackageInfoLoader = Future<PackageInfo> Function();
typedef UrlOpener = Future<bool> Function(Uri uri);

enum MobileUpdateFailureCode {
  checkUnavailable,
  manifestRejected,
  downloadRejected,
  downloadOpenFailed,
}

extension MobileUpdateFailureCodePresentation on MobileUpdateFailureCode {
  bool get isUserVisible => this != MobileUpdateFailureCode.checkUnavailable;
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
    UrlOpener? urlOpener,
    Duration timeout = const Duration(seconds: 4),
  }) : _policy = _MobileUpdateTrustPolicy.fromApiBase(apiConfig.baseUrl),
       _httpClient = httpClient ?? http.Client(),
       _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform,
       _urlOpener =
           urlOpener ??
           ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication)),
       _timeout = timeout;

  static const _maximumManifestBytes = 64 * 1024;

  final _MobileUpdateTrustPolicy? _policy;
  final http.Client _httpClient;
  final PackageInfoLoader _packageInfoLoader;
  final UrlOpener _urlOpener;
  final Duration _timeout;

  String? get manifestUrl => _policy?.manifestUri.toString();

  Future<MobileUpdateCheck> checkForUpdate() async {
    final policy = _policy;
    if (policy == null) {
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

  Future<void> openDownload(MobileUpdateManifest manifest) async {
    final policy = _policy;
    if (policy == null) {
      throw const MobileUpdateException(
        MobileUpdateFailureCode.downloadRejected,
      );
    }

    final packageInfo = await _loadPackageInfo(
      failureCode: MobileUpdateFailureCode.downloadOpenFailed,
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

    final uri = Uri.parse(manifest.apkUrl);
    final request = http.Request('HEAD', uri)
      ..headers[HttpHeaders.acceptHeader] =
          'application/vnd.android.package-archive';
    final response = await _sendWithoutRedirects(
      request,
      transportFailure: MobileUpdateFailureCode.downloadOpenFailed,
      redirectFailure: MobileUpdateFailureCode.downloadRejected,
    );
    await response.stream.drain<void>();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const MobileUpdateException(
        MobileUpdateFailureCode.downloadOpenFailed,
      );
    }

    bool opened;
    try {
      opened = await _urlOpener(uri).timeout(_timeout);
    } on Object {
      throw const MobileUpdateException(
        MobileUpdateFailureCode.downloadOpenFailed,
      );
    }
    if (!opened) {
      throw const MobileUpdateException(
        MobileUpdateFailureCode.downloadOpenFailed,
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
