import 'package:cal_tracker_mobile/data/services/client_metadata_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  group('ClientMetadataProvider', () {
    test('exposes app version, build, platform, and session id', () async {
      final provider = ClientMetadataProvider(
        packageInfoLoader: () async => PackageInfo(
          appName: 'BetterCalories',
          packageName: 'app.bettercalories.dev',
          version: '0.1.9',
          buildNumber: '15',
          buildSignature: '',
        ),
      );

      final metadata = await provider.read();

      expect(metadata.appVersion, '0.1.9');
      expect(metadata.appBuild, '15');
      expect(metadata.sessionId, isNotEmpty);
      // Session id is a v4 UUID-like identifier; sanity check the structure.
      expect(metadata.sessionId.length, 36);
      expect(metadata.sessionId[14], '4');
    });

    test('reuses the same session id across reads', () async {
      final provider = ClientMetadataProvider(
        packageInfoLoader: () async => PackageInfo(
          appName: 'BetterCalories',
          packageName: 'app.bettercalories.dev',
          version: '0.1.9',
          buildNumber: '15',
          buildSignature: '',
        ),
      );

      final first = await provider.read();
      final second = await provider.read();

      expect(first.sessionId, second.sessionId);
    });

    test('falls back to safe defaults when package info loading fails',
        () async {
      final provider = ClientMetadataProvider(
        packageInfoLoader: () async => throw Exception('package missing'),
      );

      final metadata = await provider.read();

      expect(metadata.appVersion, '0.0.0');
      expect(metadata.appBuild, '0');
      expect(metadata.sessionId, isNotEmpty);
    });

    test('toHeaderMap returns the expected telemetry headers', () async {
      const metadata = ClientMetadata(
        appVersion: '1.2.3',
        appBuild: '7',
        platform: 'android',
        sessionId: '01234567-89ab-4cde-9012-3456789abcde',
      );

      final headers = metadata.toHeaderMap();

      expect(headers['X-App-Version'], '1.2.3');
      expect(headers['X-App-Build'], '7');
      expect(headers['X-Client-Platform'], 'android');
      expect(headers['X-Client-Session-Id'],
          '01234567-89ab-4cde-9012-3456789abcde');
    });

    test('invalidate forces a fresh read on next call', () async {
      var reads = 0;
      final provider = ClientMetadataProvider(
        packageInfoLoader: () async {
          reads += 1;
          return PackageInfo(
            appName: 'BetterCalories',
            packageName: 'app.bettercalories.dev',
            version: '0.1.9',
            buildNumber: '15',
            buildSignature: '',
          );
        },
      );

      await provider.read();
      expect(reads, 1);
      provider.invalidate();
      await provider.read();
      expect(reads, 2);
    });
  });
}
