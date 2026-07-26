import 'dart:convert';
import 'dart:io';

import 'package:cal_tracker_mobile/app/app.dart';
import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:cal_tracker_mobile/data/services/mobile_update_installer.dart';
import 'package:cal_tracker_mobile/data/services/mobile_update_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _RecordingInstaller implements MobileUpdateInstaller {
  String? installedPath;

  @override
  bool get isSupported => true;

  @override
  Future<bool> canInstallPackages() async => true;

  @override
  Future<void> openInstallPermissionSettings() async {}

  @override
  Future<void> installApk({
    required String filePath,
    required int expectedVersionCode,
    required String expectedSha256,
    required int expectedSizeBytes,
  }) async {
    installedPath = filePath;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('downloads and hands a verified APK to the in-app installer',
      (tester) async {
    final apkBytes = utf8.encode('integration apk fixture');
    final apkSha256 = sha256.convert(apkBytes).toString();
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'bettercalories-update-integration-',
    );
    addTearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });
    final installer = _RecordingInstaller();
    final requestedUrls = <Uri>[];
    final updateService = MobileUpdateService(
      apiConfig: const ApiConfig(
        baseUrl: ApiConfig.developmentBaseUrl,
      ),
      packageInfoLoader: () async => PackageInfo(
        appName: 'BetterCalories',
        packageName: 'app.bettercalories.dev',
        version: '0.1.0',
        buildNumber: '1',
      ),
      installer: installer,
      downloadDirectoryLoader: () async => temporaryDirectory,
      httpClient: MockClient((request) async {
        requestedUrls.add(request.url);
        if (request.url.path.endsWith('.apk')) {
          return http.Response.bytes(
            apkBytes,
            200,
            headers: {
              'content-type': 'application/vnd.android.package-archive',
              'content-length': '${apkBytes.length}',
            },
          );
        }
        return http.Response(
          jsonEncode({
            'channel': 'dev',
            'packageName': 'app.bettercalories.dev',
            'versionName': '0.1.1',
            'versionCode': 2,
            'apkUrl': 'https://dev-api.bettercalories.app/apk/app-dev.apk',
            'sha256': apkSha256,
            'sizeBytes': apkBytes.length,
            'publishedAt': '2026-05-21T00:00:00Z',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await tester.pumpWidget(
      CalTrackerBootstrap(
        apiConfig: const ApiConfig(
          baseUrl: ApiConfig.developmentBaseUrl,
        ),
        mobileUpdateService: updateService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mobile_update_dialog')), findsOneWidget);
    expect(find.text('Please update'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('mobile_update_now_button')).hitTestable(),
    );
    await tester.pumpAndSettle();

    expect(
      requestedUrls,
      [
        Uri.parse(
          'https://dev-api.bettercalories.app/apk/latest.json',
        ),
        Uri.parse(
          'https://dev-api.bettercalories.app/apk/app-dev.apk',
        ),
      ],
    );
    expect(installer.installedPath, isNotNull);
    expect(
      await File(installer.installedPath!).readAsBytes(),
      apkBytes,
    );
  });
}
