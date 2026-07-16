import 'dart:convert';

import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:cal_tracker_mobile/data/services/mobile_update_service.dart';
import 'package:cal_tracker_mobile/domain/models/mobile_update_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

PackageInfo _packageInfo({
  String packageName = 'app.bettercalories.dev',
  String version = '0.1.0',
  String buildNumber = '1',
}) {
  return PackageInfo(
    appName: 'BetterCalories',
    packageName: packageName,
    version: version,
    buildNumber: buildNumber,
  );
}

Map<String, Object?> _manifest({
  String channel = 'dev',
  String packageName = 'app.bettercalories.dev',
  int versionCode = 2,
  String apkUrl = 'https://dev-api.bettercalories.app/apk/app-dev.apk',
}) {
  return {
    'channel': channel,
    'packageName': packageName,
    'versionName': '0.1.1',
    'versionCode': versionCode,
    'apkUrl': apkUrl,
    'sha256': 'a' * 64,
    'sizeBytes': 123,
    'publishedAt': '2026-05-21T00:00:00Z',
  };
}

http.Response _jsonResponse(Map<String, Object?> body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

Matcher _failsWith(MobileUpdateFailureCode code) {
  return throwsA(
    isA<MobileUpdateException>().having((error) => error.code, 'code', code),
  );
}

void main() {
  group('trusted manifest checks', () {
    test(
      'accepts a newer development manifest without following redirects',
      () async {
        Uri? requestedUrl;
        bool? followedRedirects;
        final service = MobileUpdateService(
          apiConfig: const ApiConfig(baseUrl: ApiConfig.developmentBaseUrl),
          packageInfoLoader: () async => _packageInfo(),
          httpClient: MockClient((request) async {
            requestedUrl = request.url;
            followedRedirects = request.followRedirects;
            return _jsonResponse(_manifest());
          }),
        );

        final update = await service.checkForUpdate();

        expect(
          requestedUrl,
          Uri.parse('https://dev-api.bettercalories.app/apk/latest.json'),
        );
        expect(followedRedirects, isFalse);
        expect(update.installedVersionCode, 1);
        expect(update.manifest.versionCode, 2);
        expect(update.updateAvailable, isTrue);
      },
    );

    test(
      'accepts a newer production manifest for the production package',
      () async {
        final service = MobileUpdateService(
          apiConfig: const ApiConfig(baseUrl: ApiConfig.productionBaseUrl),
          packageInfoLoader: () async => _packageInfo(
            packageName: 'app.bettercalories',
            buildNumber: '21',
          ),
          httpClient: MockClient(
            (request) async => _jsonResponse(
              _manifest(
                channel: 'prod',
                packageName: 'app.bettercalories',
                versionCode: 22,
                apkUrl: 'https://api.bettercalories.app/apk/app-production.apk',
              ),
            ),
          ),
        );

        final update = await service.checkForUpdate();

        expect(update.updateAvailable, isTrue);
        expect(update.manifest.channel, 'prod');
      },
    );

    test('does not offer equal or lower version codes', () async {
      for (final installedVersionCode in [1, 2]) {
        final service = MobileUpdateService(
          apiConfig: const ApiConfig(baseUrl: ApiConfig.developmentBaseUrl),
          packageInfoLoader: () async =>
              _packageInfo(buildNumber: '$installedVersionCode'),
          httpClient: MockClient(
            (request) async => _jsonResponse(_manifest(versionCode: 1)),
          ),
        );

        final update = await service.checkForUpdate();
        expect(update.updateAvailable, isFalse);
      }
    });

    test('rejects manifest redirects', () async {
      final service = MobileUpdateService(
        apiConfig: const ApiConfig(baseUrl: ApiConfig.developmentBaseUrl),
        packageInfoLoader: () async => _packageInfo(),
        httpClient: MockClient(
          (request) async => http.Response(
            '',
            302,
            headers: {'location': 'https://downloads.example.test/latest.json'},
          ),
        ),
      );

      await expectLater(
        service.checkForUpdate(),
        _failsWith(MobileUpdateFailureCode.manifestRejected),
      );
    });

    test('rejects channel, package, scheme, host and port crossings', () async {
      final rejected = <Map<String, Object?>>[
        _manifest(channel: 'prod'),
        _manifest(packageName: 'app.bettercalories'),
        _manifest(apkUrl: 'http://dev-api.bettercalories.app/apk/app-dev.apk'),
        _manifest(apkUrl: 'https://api.bettercalories.app/apk/app-dev.apk'),
        _manifest(
          apkUrl: 'https://dev-api.bettercalories.app:444/apk/app-dev.apk',
        ),
      ];

      for (final manifest in rejected) {
        final service = MobileUpdateService(
          apiConfig: const ApiConfig(baseUrl: ApiConfig.developmentBaseUrl),
          packageInfoLoader: () async => _packageInfo(),
          httpClient: MockClient((request) async => _jsonResponse(manifest)),
        );
        await expectLater(
          service.checkForUpdate(),
          _failsWith(MobileUpdateFailureCode.manifestRejected),
        );
      }
    });

    test(
      'rejects manipulated required fields but accepts future fields',
      () async {
        for (final manipulated in [
          _manifest()..['versionCode'] = '2',
          _manifest()..['sha256'] = 123,
        ]) {
          final rejectingService = MobileUpdateService(
            apiConfig: const ApiConfig(baseUrl: ApiConfig.developmentBaseUrl),
            packageInfoLoader: () async => _packageInfo(),
            httpClient: MockClient(
              (request) async => _jsonResponse(manipulated),
            ),
          );
          await expectLater(
            rejectingService.checkForUpdate(),
            _failsWith(MobileUpdateFailureCode.manifestRejected),
          );
        }

        final compatible = _manifest()..['releaseNotesUrl'] = '/future';
        final compatibleService = MobileUpdateService(
          apiConfig: const ApiConfig(baseUrl: ApiConfig.developmentBaseUrl),
          packageInfoLoader: () async => _packageInfo(),
          httpClient: MockClient((request) async => _jsonResponse(compatible)),
        );
        expect(
          (await compatibleService.checkForUpdate()).updateAvailable,
          isTrue,
        );
      },
    );

    test(
      'rejects an installed package that does not match the API channel',
      () async {
        var requested = false;
        final service = MobileUpdateService(
          apiConfig: const ApiConfig(baseUrl: ApiConfig.developmentBaseUrl),
          packageInfoLoader: () async =>
              _packageInfo(packageName: 'app.bettercalories'),
          httpClient: MockClient((request) async {
            requested = true;
            return _jsonResponse(_manifest());
          }),
        );

        await expectLater(
          service.checkForUpdate(),
          _failsWith(MobileUpdateFailureCode.manifestRejected),
        );
        expect(requested, isFalse);
      },
    );

    test(
      'silently disables checks for non-official local API origins',
      () async {
        final service = MobileUpdateService(
          apiConfig: const ApiConfig(baseUrl: 'http://10.0.2.2:3000'),
          packageInfoLoader: () async => _packageInfo(),
        );

        expect(service.manifestUrl, isNull);
        await expectLater(
          service.checkForUpdate(),
          _failsWith(MobileUpdateFailureCode.checkUnavailable),
        );
      },
    );
  });

  group('trusted browser handoff', () {
    const manifest = MobileUpdateManifest(
      channel: 'dev',
      packageName: 'app.bettercalories.dev',
      versionName: '0.1.1',
      versionCode: 2,
      apkUrl: 'https://dev-api.bettercalories.app/apk/app-dev.apk',
      publishedAt: '2026-05-21T00:00:00Z',
    );

    test('HEAD-checks the final endpoint and opens it externally', () async {
      Uri? openedUrl;
      String? requestMethod;
      bool? followedRedirects;
      final service = MobileUpdateService(
        apiConfig: const ApiConfig(baseUrl: ApiConfig.developmentBaseUrl),
        packageInfoLoader: () async => _packageInfo(),
        urlOpener: (uri) async {
          openedUrl = uri;
          return true;
        },
        httpClient: MockClient((request) async {
          requestMethod = request.method;
          followedRedirects = request.followRedirects;
          return http.Response('', 200);
        }),
      );

      await service.openDownload(manifest);

      expect(requestMethod, 'HEAD');
      expect(followedRedirects, isFalse);
      expect(
        openedUrl,
        Uri.parse('https://dev-api.bettercalories.app/apk/app-dev.apk'),
      );
    });

    test('blocks a redirect without launching the browser', () async {
      var opened = false;
      final service = MobileUpdateService(
        apiConfig: const ApiConfig(baseUrl: ApiConfig.developmentBaseUrl),
        packageInfoLoader: () async => _packageInfo(),
        urlOpener: (uri) async {
          opened = true;
          return true;
        },
        httpClient: MockClient(
          (request) async => http.Response(
            '',
            302,
            headers: {'location': 'https://downloads.example.test/app.apk'},
          ),
        ),
      );

      await expectLater(
        service.openDownload(manifest),
        _failsWith(MobileUpdateFailureCode.downloadRejected),
      );
      expect(opened, isFalse);
    });

    test(
      'blocks stale versions before any network or browser action',
      () async {
        var requested = false;
        var opened = false;
        final service = MobileUpdateService(
          apiConfig: const ApiConfig(baseUrl: ApiConfig.developmentBaseUrl),
          packageInfoLoader: () async => _packageInfo(buildNumber: '2'),
          httpClient: MockClient((request) async {
            requested = true;
            return http.Response('', 200);
          }),
          urlOpener: (uri) async {
            opened = true;
            return true;
          },
        );

        await expectLater(
          service.openDownload(manifest),
          _failsWith(MobileUpdateFailureCode.downloadRejected),
        );
        expect(requested, isFalse);
        expect(opened, isFalse);
      },
    );

    test(
      'blocks invalid channel, package and host before network or browser action',
      () async {
        const rejectedManifests = [
          MobileUpdateManifest(
            channel: 'prod',
            packageName: 'app.bettercalories.dev',
            versionName: '0.1.1',
            versionCode: 2,
            apkUrl: 'https://dev-api.bettercalories.app/apk/app-dev.apk',
            publishedAt: '2026-05-21T00:00:00Z',
          ),
          MobileUpdateManifest(
            channel: 'dev',
            packageName: 'app.bettercalories',
            versionName: '0.1.1',
            versionCode: 2,
            apkUrl: 'https://dev-api.bettercalories.app/apk/app-dev.apk',
            publishedAt: '2026-05-21T00:00:00Z',
          ),
          MobileUpdateManifest(
            channel: 'dev',
            packageName: 'app.bettercalories.dev',
            versionName: '0.1.1',
            versionCode: 2,
            apkUrl: 'https://api.bettercalories.app/apk/app-dev.apk',
            publishedAt: '2026-05-21T00:00:00Z',
          ),
        ];

        for (final rejectedManifest in rejectedManifests) {
          var requested = false;
          var opened = false;
          final service = MobileUpdateService(
            apiConfig: const ApiConfig(baseUrl: ApiConfig.developmentBaseUrl),
            packageInfoLoader: () async => _packageInfo(),
            httpClient: MockClient((request) async {
              requested = true;
              return http.Response('', 200);
            }),
            urlOpener: (uri) async {
              opened = true;
              return true;
            },
          );

          await expectLater(
            service.openDownload(rejectedManifest),
            _failsWith(MobileUpdateFailureCode.manifestRejected),
          );
          expect(requested, isFalse);
          expect(opened, isFalse);
        }
      },
    );
  });
}
