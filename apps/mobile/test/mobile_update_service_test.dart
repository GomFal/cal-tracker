import 'dart:convert';
import 'dart:io';

import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:cal_tracker_mobile/data/services/mobile_update_installer.dart';
import 'package:cal_tracker_mobile/data/services/mobile_update_service.dart';
import 'package:cal_tracker_mobile/domain/models/mobile_update_models.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _apkMimeType = 'application/vnd.android.package-archive';
final _apkBytes = utf8.encode('signed apk fixture');

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

Map<String, Object?> _manifestJson({
  String channel = 'dev',
  String packageName = 'app.bettercalories.dev',
  int versionCode = 2,
  String apkUrl = 'https://dev-api.bettercalories.app/apk/app-dev.apk',
  List<int>? apkBytes,
}) {
  final bytes = apkBytes ?? _apkBytes;
  return {
    'channel': channel,
    'packageName': packageName,
    'versionName': '0.1.1',
    'versionCode': versionCode,
    'apkUrl': apkUrl,
    'sha256': sha256.convert(bytes).toString(),
    'sizeBytes': bytes.length,
    'publishedAt': '2026-05-21T00:00:00Z',
  };
}

MobileUpdateManifest _manifest({
  int versionCode = 2,
  List<int>? apkBytes,
}) {
  return MobileUpdateManifest.fromJson(
    _manifestJson(versionCode: versionCode, apkBytes: apkBytes),
  );
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

class _FakeInstaller implements MobileUpdateInstaller {
  _FakeInstaller({
    this.supported = true,
    this.permissionGranted = true,
    this.installError,
  });

  bool supported;
  bool permissionGranted;
  Object? installError;
  int permissionSettingsOpenCount = 0;
  final installedPaths = <String>[];

  @override
  bool get isSupported => supported;

  @override
  Future<bool> canInstallPackages() async => permissionGranted;

  @override
  Future<void> openInstallPermissionSettings() async {
    permissionSettingsOpenCount += 1;
  }

  @override
  Future<void> installApk({
    required String filePath,
    required int expectedVersionCode,
    required String expectedSha256,
    required int expectedSizeBytes,
  }) async {
    final error = installError;
    if (error != null) throw error;
    expect(expectedVersionCode, 2);
    expect(expectedSha256, sha256.convert(_apkBytes).toString());
    expect(expectedSizeBytes, _apkBytes.length);
    installedPaths.add(filePath);
  }
}

class _StreamingClient extends http.BaseClient {
  _StreamingClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return handler(request);
  }
}

http.StreamedResponse _apkResponse(
  List<List<int>> chunks, {
  int statusCode = 200,
  String contentType = _apkMimeType,
  int? contentLength,
  Map<String, String> headers = const {},
}) {
  return http.StreamedResponse(
    Stream<List<int>>.fromIterable(chunks),
    statusCode,
    contentLength: contentLength,
    headers: {
      'content-type': contentType,
      ...headers,
    },
  );
}

MobileUpdateService _service({
  required http.Client client,
  required _FakeInstaller installer,
  required Directory temporaryDirectory,
  PackageInfo? packageInfo,
  String apiBaseUrl = ApiConfig.developmentBaseUrl,
  Duration downloadInactivityTimeout = const Duration(seconds: 1),
}) {
  return MobileUpdateService(
    apiConfig: ApiConfig(baseUrl: apiBaseUrl),
    httpClient: client,
    packageInfoLoader: () async => packageInfo ?? _packageInfo(),
    installer: installer,
    downloadDirectoryLoader: () async => temporaryDirectory,
    downloadInactivityTimeout: downloadInactivityTimeout,
  );
}

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'bettercalories-update-test-',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  group('trusted manifest checks', () {
    test(
      'accepts a newer development manifest without following redirects',
      () async {
        Uri? requestedUrl;
        bool? followedRedirects;
        final service = _service(
          temporaryDirectory: temporaryDirectory,
          installer: _FakeInstaller(),
          client: MockClient((request) async {
            requestedUrl = request.url;
            followedRedirects = request.followRedirects;
            return _jsonResponse(_manifestJson());
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

    test('accepts a production manifest for the production package', () async {
      final service = _service(
        apiBaseUrl: ApiConfig.productionBaseUrl,
        temporaryDirectory: temporaryDirectory,
        installer: _FakeInstaller(),
        packageInfo: _packageInfo(
          packageName: 'app.bettercalories',
          buildNumber: '21',
        ),
        client: MockClient(
          (request) async => _jsonResponse(
            _manifestJson(
              channel: 'prod',
              packageName: 'app.bettercalories',
              versionCode: 22,
              apkUrl: 'https://api.bettercalories.app/apk/app-prod.apk',
            ),
          ),
        ),
      );

      final update = await service.checkForUpdate();

      expect(update.updateAvailable, isTrue);
      expect(update.manifest.channel, 'prod');
    });

    test('does not offer equal or lower version codes', () async {
      for (final installedVersionCode in [1, 2]) {
        final service = _service(
          temporaryDirectory: temporaryDirectory,
          installer: _FakeInstaller(),
          packageInfo: _packageInfo(buildNumber: '$installedVersionCode'),
          client: MockClient(
            (request) async => _jsonResponse(_manifestJson(versionCode: 1)),
          ),
        );

        expect((await service.checkForUpdate()).updateAvailable, isFalse);
      }
    });

    test('rejects manifest redirects', () async {
      final service = _service(
        temporaryDirectory: temporaryDirectory,
        installer: _FakeInstaller(),
        client: MockClient(
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
        _manifestJson(channel: 'prod'),
        _manifestJson(packageName: 'app.bettercalories'),
        _manifestJson(
          apkUrl: 'http://dev-api.bettercalories.app/apk/app-dev.apk',
        ),
        _manifestJson(apkUrl: 'https://api.bettercalories.app/apk/app-dev.apk'),
        _manifestJson(
          apkUrl: 'https://dev-api.bettercalories.app:444/apk/app-dev.apk',
        ),
      ];

      for (final manifest in rejected) {
        final service = _service(
          temporaryDirectory: temporaryDirectory,
          installer: _FakeInstaller(),
          client: MockClient((request) async => _jsonResponse(manifest)),
        );
        await expectLater(
          service.checkForUpdate(),
          _failsWith(MobileUpdateFailureCode.manifestRejected),
        );
      }
    });

    test(
      'requires integrity metadata and tolerates unknown future fields',
      () async {
        for (final manipulated in [
          _manifestJson()..remove('sha256'),
          _manifestJson()..remove('sizeBytes'),
          _manifestJson()..['sha256'] = 123,
          _manifestJson()..['sizeBytes'] = '18',
        ]) {
          final service = _service(
            temporaryDirectory: temporaryDirectory,
            installer: _FakeInstaller(),
            client: MockClient(
              (request) async => _jsonResponse(manipulated),
            ),
          );
          await expectLater(
            service.checkForUpdate(),
            _failsWith(MobileUpdateFailureCode.manifestRejected),
          );
        }

        final compatible = _manifestJson()..['releaseNotesUrl'] = '/future';
        final service = _service(
          temporaryDirectory: temporaryDirectory,
          installer: _FakeInstaller(),
          client: MockClient((request) async => _jsonResponse(compatible)),
        );
        expect((await service.checkForUpdate()).updateAvailable, isTrue);
      },
    );

    test('rejects an installed package that does not match the channel',
        () async {
      var requested = false;
      final service = _service(
        temporaryDirectory: temporaryDirectory,
        installer: _FakeInstaller(),
        packageInfo: _packageInfo(packageName: 'app.bettercalories'),
        client: MockClient((request) async {
          requested = true;
          return _jsonResponse(_manifestJson());
        }),
      );

      await expectLater(
        service.checkForUpdate(),
        _failsWith(MobileUpdateFailureCode.manifestRejected),
      );
      expect(requested, isFalse);
    });

    test('silently disables checks off Android or official API origins',
        () async {
      final unsupportedInstaller = _FakeInstaller(supported: false);
      final unsupportedService = _service(
        temporaryDirectory: temporaryDirectory,
        installer: unsupportedInstaller,
        client: MockClient((request) async => _jsonResponse(_manifestJson())),
      );
      await expectLater(
        unsupportedService.checkForUpdate(),
        _failsWith(MobileUpdateFailureCode.checkUnavailable),
      );

      final localService = _service(
        apiBaseUrl: 'http://10.0.2.2:3000',
        temporaryDirectory: temporaryDirectory,
        installer: _FakeInstaller(),
        client: MockClient((request) async => _jsonResponse(_manifestJson())),
      );
      expect(localService.manifestUrl, isNull);
      await expectLater(
        localService.checkForUpdate(),
        _failsWith(MobileUpdateFailureCode.checkUnavailable),
      );
    });
  });

  group('verified in-app download and installation', () {
    test('streams, verifies and sends only the private APK to Android',
        () async {
      final installer = _FakeInstaller();
      final requestMethods = <String>[];
      final progress = <double>[];
      final client = _StreamingClient((request) async {
        requestMethods.add(request.method);
        expect(request.followRedirects, isFalse);
        expect(request.url, Uri.parse(_manifest().apkUrl));
        return _apkResponse(
          [
            _apkBytes.sublist(0, 4),
            _apkBytes.sublist(4, 10),
            _apkBytes.sublist(10),
          ],
          contentLength: _apkBytes.length,
        );
      });
      final service = _service(
        client: client,
        installer: installer,
        temporaryDirectory: temporaryDirectory,
      );

      await service.downloadAndInstall(
        _manifest(),
        onProgress: progress.add,
      );

      expect(requestMethods, ['GET']);
      expect(progress, isNotEmpty);
      expect(progress.last, 1);
      expect(
        progress,
        orderedEquals([...progress]..sort()),
      );
      expect(installer.installedPaths, hasLength(1));
      final installedFile = File(installer.installedPaths.single);
      expect(
        installedFile.path,
        endsWith('mobile_updates/bettercalories-update-2.apk'),
      );
      expect(await installedFile.readAsBytes(), _apkBytes);
      expect(await File('${installedFile.path}.part').exists(), isFalse);
    });

    test('reuses a verified cached APK without a second network request',
        () async {
      var requests = 0;
      final installer = _FakeInstaller();
      final service = _service(
        temporaryDirectory: temporaryDirectory,
        installer: installer,
        client: _StreamingClient((request) async {
          requests += 1;
          return _apkResponse(
            [_apkBytes],
            contentLength: _apkBytes.length,
          );
        }),
      );

      await service.downloadAndInstall(_manifest());
      await service.downloadAndInstall(_manifest());

      expect(requests, 1);
      expect(installer.installedPaths, hasLength(2));
    });

    test('downloads first, requests permission, then resumes from cache',
        () async {
      var requests = 0;
      final installer = _FakeInstaller(permissionGranted: false);
      final service = _service(
        temporaryDirectory: temporaryDirectory,
        installer: installer,
        client: _StreamingClient((request) async {
          requests += 1;
          return _apkResponse(
            [_apkBytes],
            contentLength: _apkBytes.length,
          );
        }),
      );

      await expectLater(
        service.downloadAndInstall(_manifest()),
        _failsWith(MobileUpdateFailureCode.installPermissionRequired),
      );
      expect(installer.permissionSettingsOpenCount, 1);
      expect(installer.installedPaths, isEmpty);

      installer.permissionGranted = true;
      await service.downloadAndInstall(
        _manifest(),
        requestInstallPermission: false,
      );

      expect(requests, 1);
      expect(installer.installedPaths, hasLength(1));
    });

    test('does not reopen settings when permission remains denied', () async {
      final installer = _FakeInstaller(permissionGranted: false);
      final service = _service(
        temporaryDirectory: temporaryDirectory,
        installer: installer,
        client: _StreamingClient(
          (request) async => _apkResponse(
            [_apkBytes],
            contentLength: _apkBytes.length,
          ),
        ),
      );

      await expectLater(
        service.downloadAndInstall(
          _manifest(),
          requestInstallPermission: false,
        ),
        _failsWith(MobileUpdateFailureCode.installPermissionDenied),
      );
      expect(installer.permissionSettingsOpenCount, 0);
    });

    test('blocks redirects, unexpected MIME and declared size mismatch',
        () async {
      final rejectedResponses = [
        _apkResponse(
          const [],
          statusCode: 302,
          headers: {'location': 'https://downloads.example.test/app.apk'},
        ),
        _apkResponse(
          [_apkBytes],
          contentType: 'text/html',
          contentLength: _apkBytes.length,
        ),
        _apkResponse(
          [_apkBytes],
          contentLength: _apkBytes.length + 1,
        ),
      ];

      for (final response in rejectedResponses) {
        final installer = _FakeInstaller();
        final service = _service(
          temporaryDirectory: temporaryDirectory,
          installer: installer,
          client: _StreamingClient((request) async => response),
        );
        await expectLater(
          service.downloadAndInstall(_manifest()),
          _failsWith(MobileUpdateFailureCode.downloadRejected),
        );
        expect(installer.installedPaths, isEmpty);
      }
    });

    test('deletes partial files after body size or hash verification fails',
        () async {
      final sameSizeDifferentBytes = [..._apkBytes]..[0] ^= 0xff;
      final wrongHashManifest = MobileUpdateManifest.fromJson(
        _manifestJson(apkBytes: sameSizeDifferentBytes),
      );
      final rejected = <(MobileUpdateManifest, List<int>)>[
        (_manifest(), _apkBytes.sublist(0, _apkBytes.length - 1)),
        (wrongHashManifest, _apkBytes),
      ];

      for (final (manifest, bytes) in rejected) {
        final service = _service(
          temporaryDirectory: temporaryDirectory,
          installer: _FakeInstaller(),
          client: _StreamingClient(
            (request) async => _apkResponse([bytes]),
          ),
        );
        await expectLater(
          service.downloadAndInstall(manifest),
          _failsWith(MobileUpdateFailureCode.downloadRejected),
        );
        final updateDirectory = Directory(
          '${temporaryDirectory.path}/mobile_updates',
        );
        final files = await updateDirectory
            .list()
            .where((entity) => entity is File)
            .toList();
        expect(files, isEmpty);
      }
    });

    test('blocks stale versions before network or installer actions', () async {
      var requested = false;
      final installer = _FakeInstaller();
      final service = _service(
        temporaryDirectory: temporaryDirectory,
        installer: installer,
        packageInfo: _packageInfo(buildNumber: '2'),
        client: _StreamingClient((request) async {
          requested = true;
          return _apkResponse([_apkBytes]);
        }),
      );

      await expectLater(
        service.downloadAndInstall(_manifest()),
        _failsWith(MobileUpdateFailureCode.downloadRejected),
      );
      expect(requested, isFalse);
      expect(installer.installedPaths, isEmpty);
    });

    test('maps a native installer launch failure to a safe error', () async {
      final installer = _FakeInstaller(
        installError: const MobileUpdateInstallerException(
          'installer_unavailable',
        ),
      );
      final service = _service(
        temporaryDirectory: temporaryDirectory,
        installer: installer,
        client: _StreamingClient(
          (request) async => _apkResponse(
            [_apkBytes],
            contentLength: _apkBytes.length,
          ),
        ),
      );

      await expectLater(
        service.downloadAndInstall(_manifest()),
        _failsWith(MobileUpdateFailureCode.installFailed),
      );
    });
  });
}
