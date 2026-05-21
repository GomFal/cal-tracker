import 'dart:convert';

import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:cal_tracker_mobile/data/services/mobile_update_service.dart';
import 'package:cal_tracker_mobile/domain/models/mobile_update_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

PackageInfo _packageInfo({
  String version = '0.1.0',
  String buildNumber = '1',
}) {
  return PackageInfo(
    appName: 'BetterCalories',
    packageName: 'app.bettercalories.dev',
    version: version,
    buildNumber: buildNumber,
  );
}

void main() {
  test('checkForUpdate marks newer APK manifests as available', () async {
    Uri? requestedUrl;
    final service = MobileUpdateService(
      apiConfig: const ApiConfig(baseUrl: 'https://dev-api.bettercalories.app'),
      packageInfoLoader: () async => _packageInfo(),
      httpClient: MockClient((request) async {
        requestedUrl = request.url;
        return http.Response(
          jsonEncode({
            'versionName': '0.1.1',
            'versionCode': 2,
            'apkUrl': 'https://dev-api.bettercalories.app/apk/app.apk',
            'sha256': 'abc123',
            'sizeBytes': 123,
            'publishedAt': '2026-05-21T00:00:00Z',
          }),
          200,
        );
      }),
    );

    final update = await service.checkForUpdate();

    expect(
      requestedUrl,
      Uri.parse('https://dev-api.bettercalories.app/apk/latest.json'),
    );
    expect(update.installedVersionCode, 1);
    expect(update.manifest.versionCode, 2);
    expect(update.updateAvailable, isTrue);
  });

  test('openDownload delegates to the configured URL opener', () async {
    Uri? openedUrl;
    final service = MobileUpdateService(
      apiConfig: const ApiConfig(baseUrl: 'https://api.bettercalories.app'),
      packageInfoLoader: () async => _packageInfo(),
      urlOpener: (uri) async {
        openedUrl = uri;
        return true;
      },
    );

    await service.openDownload(
      const MobileUpdateManifest(
        versionName: '0.1.1',
        versionCode: 2,
        apkUrl: 'https://api.bettercalories.app/apk/app.apk',
        publishedAt: '2026-05-21T00:00:00Z',
      ),
    );

    expect(openedUrl, Uri.parse('https://api.bettercalories.app/apk/app.apk'));
  });
}
