import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/models/mobile_update_models.dart';
import 'api_config.dart';

typedef PackageInfoLoader = Future<PackageInfo> Function();
typedef UrlOpener = Future<bool> Function(Uri uri);

class MobileUpdateException implements Exception {
  const MobileUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MobileUpdateService {
  MobileUpdateService({
    required ApiConfig apiConfig,
    http.Client? httpClient,
    PackageInfoLoader? packageInfoLoader,
    UrlOpener? urlOpener,
    Duration timeout = const Duration(seconds: 4),
  })  : manifestUrl = _manifestUrlFromApiBase(apiConfig.baseUrl),
        _httpClient = httpClient ?? http.Client(),
        _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform,
        _urlOpener = urlOpener ??
            ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication)),
        _timeout = timeout;

  final String manifestUrl;
  final http.Client _httpClient;
  final PackageInfoLoader _packageInfoLoader;
  final UrlOpener _urlOpener;
  final Duration _timeout;

  Future<MobileUpdateCheck> checkForUpdate() async {
    final response = await _httpClient.get(
      Uri.parse(manifestUrl),
      headers: {HttpHeaders.acceptHeader: 'application/json'},
    ).timeout(
      _timeout,
      onTimeout: () => throw const MobileUpdateException(
        'The update check took too long.',
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MobileUpdateException(
        'Could not check for updates (${response.statusCode}).',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const MobileUpdateException('The update manifest is invalid.');
    }
    final packageInfo = await _packageInfoLoader();
    return MobileUpdateCheck(
      installedVersionName: packageInfo.version,
      installedVersionCode: int.tryParse(packageInfo.buildNumber) ?? 0,
      manifest: MobileUpdateManifest.fromJson(decoded),
    );
  }

  Future<void> openDownload(MobileUpdateManifest manifest) async {
    final uri = Uri.tryParse(manifest.apkUrl);
    if (uri == null || !uri.hasScheme) {
      throw const MobileUpdateException('The APK download URL is invalid.');
    }
    final opened = await _urlOpener(uri);
    if (!opened) {
      throw const MobileUpdateException('Could not open the APK download.');
    }
  }

  static String _manifestUrlFromApiBase(String baseUrl) {
    final uri = Uri.parse(baseUrl);
    return uri
        .replace(path: '/apk/latest.json', query: null, fragment: null)
        .toString();
  }
}
