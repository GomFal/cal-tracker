import 'dart:convert';

import 'package:cal_tracker_mobile/app/app.dart';
import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:cal_tracker_mobile/data/services/mobile_update_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows update dialog and opens the APK URL', (tester) async {
    Uri? openedUrl;
    final updateService = MobileUpdateService(
      apiConfig: const ApiConfig(baseUrl: 'https://dev-api.bettercalories.app'),
      packageInfoLoader: () async => PackageInfo(
        appName: 'BetterCalories',
        packageName: 'app.bettercalories.dev',
        version: '0.1.0',
        buildNumber: '1',
      ),
      urlOpener: (uri) async {
        openedUrl = uri;
        return true;
      },
      httpClient: MockClient((request) async {
        if (request.method == 'HEAD') {
          return http.Response('', 200);
        }
        return http.Response(
          jsonEncode({
            'channel': 'dev',
            'packageName': 'app.bettercalories.dev',
            'versionName': '0.1.1',
            'versionCode': 2,
            'apkUrl': 'https://dev-api.bettercalories.app/apk/app-dev.apk',
            'publishedAt': '2026-05-21T00:00:00Z',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await tester.pumpWidget(
      CalTrackerBootstrap(
        apiConfig:
            const ApiConfig(baseUrl: 'https://dev-api.bettercalories.app'),
        mobileUpdateService: updateService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mobile_update_dialog')), findsOneWidget);
    expect(find.text('Please update'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mobile_update_now_button')));
    await tester.pumpAndSettle();

    expect(
      openedUrl,
      Uri.parse('https://dev-api.bettercalories.app/apk/app-dev.apk'),
    );
  });
}
