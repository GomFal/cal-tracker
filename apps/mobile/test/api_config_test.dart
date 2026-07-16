import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApiConfig secure network policy', () {
    test('compile-time configuration has no localhost fallback', () {
      const config = ApiConfig.fromEnvironment();

      expect(config.baseUrl, isEmpty);
    });

    test('accepts only the canonical production origin', () {
      const ApiConfig(
        baseUrl: ApiConfig.productionBaseUrl,
      ).validate(flavor: ApiConfig.productionFlavor, isRelease: true);

      expect(
        () => const ApiConfig(
          baseUrl: 'http://api.bettercalories.app',
        ).validate(flavor: ApiConfig.productionFlavor, isRelease: true),
        throwsA(_configError('unapproved_production_api_origin')),
      );
      expect(
        () => const ApiConfig(
          baseUrl: 'https://example.com',
        ).validate(flavor: ApiConfig.productionFlavor, isRelease: true),
        throwsA(_configError('unapproved_production_api_origin')),
      );
    });

    test(
      'accepts only the canonical deployed development origin in release',
      () {
        const ApiConfig(
          baseUrl: ApiConfig.developmentBaseUrl,
        ).validate(flavor: ApiConfig.developmentFlavor, isRelease: true);

        expect(
          () => const ApiConfig(
            baseUrl: 'http://10.0.2.2:3000',
          ).validate(flavor: ApiConfig.developmentFlavor, isRelease: true),
          throwsA(_configError('unapproved_development_api_origin')),
        );
      },
    );

    test(
      'allows explicit local origins only in debug dev and local flavors',
      () {
        for (final baseUrl in const [
          'http://10.0.2.2:3000',
          'http://localhost:3000',
          'http://127.0.0.1:3000',
        ]) {
          ApiConfig(
            baseUrl: baseUrl,
          ).validate(flavor: ApiConfig.developmentFlavor, isRelease: false);
          ApiConfig(
            baseUrl: baseUrl,
          ).validate(flavor: ApiConfig.localFlavor, isRelease: false);
        }

        expect(
          () => const ApiConfig(
            baseUrl: 'http://192.168.1.10:3000',
          ).validate(flavor: ApiConfig.localFlavor, isRelease: false),
          throwsA(_configError('unapproved_local_api_origin')),
        );
        expect(
          () => const ApiConfig(
            baseUrl: 'http://10.0.2.2:3000',
          ).validate(flavor: ApiConfig.productionFlavor, isRelease: false),
          throwsA(_configError('unapproved_production_api_origin')),
        );
      },
    );

    test('local release and malformed configurations fail closed', () {
      expect(
        () => const ApiConfig(
          baseUrl: 'http://10.0.2.2:3000',
        ).validate(flavor: ApiConfig.localFlavor, isRelease: true),
        throwsA(_configError('local_release_is_not_supported')),
      );
      expect(
        () => const ApiConfig(
          baseUrl: '',
        ).validate(flavor: ApiConfig.developmentFlavor, isRelease: true),
        throwsA(_configError('missing_api_base_url')),
      );
      expect(
        () => const ApiConfig(
          baseUrl: 'https://user:secret@dev-api.bettercalories.app',
        ).validate(flavor: ApiConfig.developmentFlavor, isRelease: true),
        throwsA(_configError('invalid_api_base_url')),
      );
      expect(
        () => const ApiConfig(
          baseUrl: 'https://dev-api.bettercalories.app/v1',
        ).validate(flavor: ApiConfig.developmentFlavor, isRelease: true),
        throwsA(_configError('invalid_api_base_url')),
      );
    });
  });
}

Matcher _configError(String code) =>
    isA<ApiConfigException>().having((error) => error.code, 'code', code);
