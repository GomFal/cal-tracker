import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final validator = File(
    '../../scripts/mobile/validate-api-base-url.sh',
  ).absolute.path;

  test('release validator accepts only canonical HTTPS origins', () async {
    await _expectValidation(
        validator,
        [
          'dev',
          ApiConfigOrigins.dev,
          'release',
        ],
        succeeds: true);
    await _expectValidation(
        validator,
        [
          'prod',
          ApiConfigOrigins.prod,
          'release',
        ],
        succeeds: true);

    for (final arguments in [
      ['dev', 'http://10.0.2.2:3000', 'release'],
      ['dev', 'https://api.bettercalories.app', 'release'],
      ['prod', 'http://api.bettercalories.app', 'release'],
      ['prod', 'https://example.com', 'release'],
      ['prod', 'https://api.bettercalories.app:444', 'release'],
      ['prod', 'https://api.bettercalories.app/v1', 'release'],
      ['prod', 'HTTPS://api.bettercalories.app', 'release'],
    ]) {
      await _expectValidation(validator, arguments, succeeds: false);
    }
  });

  test('debug validator limits HTTP to explicit local origins', () async {
    for (final flavor in ['dev', 'local', 'local1', 'local2']) {
      for (final baseUrl in [
        'http://10.0.2.2:3000',
        'http://localhost:3000',
        'http://127.0.0.1:3000',
      ]) {
        await _expectValidation(
            validator,
            [
              flavor,
              baseUrl,
              'debug',
            ],
            succeeds: true);
      }
    }

    for (final arguments in [
      ['local', 'http://192.168.1.2:3000', 'debug'],
      ['local', 'http://10.0.2.2:4000', 'debug'],
      ['local', 'https://example.com', 'debug'],
      ['prod', 'http://10.0.2.2:3000', 'debug'],
      ['local', 'http://user:secret@10.0.2.2:3000', 'debug'],
      ['local1', 'http://10.0.2.2:3000', 'release'],
      ['local2', 'http://10.0.2.2:3000', 'release'],
    ]) {
      await _expectValidation(validator, arguments, succeeds: false);
    }
  });

  test('CI and Android build invoke the shared validator', () {
    final root = Directory('../..');
    final workflow = File(
      '${root.path}/.github/workflows/mobile-apk-deploy.yml',
    ).readAsStringSync();
    final buildScript = File(
      '${root.path}/scripts/mobile/build-android.sh',
    ).readAsStringSync();
    final gradleBuild = File(
      'android/app/build.gradle.kts',
    ).readAsStringSync();

    expect(
      workflow,
      contains(
        'scripts/mobile/validate-api-base-url.sh "\$flavor" "\$api_base_url" release',
      ),
    );
    expect(buildScript, contains('validate-api-base-url.sh'));
    expect(buildScript, contains('"\$flavor" "\$api_base_url" "\$BUILD_MODE"'));
    expect(gradleBuild, contains('compileFlutterBuildDevRelease'));
    expect(gradleBuild, contains('compileFlutterBuildProdRelease'));
    expect(gradleBuild, contains('decodedDartDefine("API_BASE_URL")'));
    expect(gradleBuild, contains('validate-api-base-url.sh'));
  });
}

abstract final class ApiConfigOrigins {
  static const dev = 'https://dev-api.bettercalories.app';
  static const prod = 'https://api.bettercalories.app';
}

Future<void> _expectValidation(
  String validator,
  List<String> arguments, {
  required bool succeeds,
}) async {
  final result = await Process.run('bash', [validator, ...arguments]);
  expect(
    result.exitCode,
    succeeds ? 0 : isNot(0),
    reason: 'validator ${arguments.join(' ')}\n${result.stderr}',
  );
}
