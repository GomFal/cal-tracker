import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final androidApp = Directory('android/app');

  test('main Android manifest denies cleartext traffic', () {
    final manifest = File(
      '${androidApp.path}/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final policy = File(
      '${androidApp.path}/src/main/res/xml/network_security_config.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:usesCleartextTraffic="false"'));
    expect(
      manifest,
      contains('android:networkSecurityConfig="@xml/network_security_config"'),
    );
    expect(policy, contains('cleartextTrafficPermitted="false"'));
    expect(policy, isNot(contains('cleartextTrafficPermitted="true"')));
  });

  test('only approved debug source sets declare cleartext exceptions', () {
    const debugSourceSets = [
      'devDebug',
      'localDebug',
      'local1Debug',
      'local2Debug',
    ];
    for (final sourceSet in debugSourceSets) {
      final manifest = File(
        '${androidApp.path}/src/$sourceSet/AndroidManifest.xml',
      ).readAsStringSync();
      final policy = File(
        '${androidApp.path}/src/$sourceSet/res/xml/network_security_config.xml',
      ).readAsStringSync();

      expect(manifest, contains('android:usesCleartextTraffic="true"'));
      expect(policy, contains('cleartextTrafficPermitted="false"'));
      expect(
        policy,
        contains('<domain-config cleartextTrafficPermitted="true">'),
      );
      expect(policy, contains('>10.0.2.2</domain>'));
      expect(policy, contains('>localhost</domain>'));
      expect(policy, contains('>127.0.0.1</domain>'));
      expect(policy, isNot(contains('includeSubdomains="true"')));
    }

    expect(
      File(
        '${androidApp.path}/src/prodDebug/AndroidManifest.xml',
      ).existsSync(),
      isFalse,
      reason: 'prodDebug must not override the deny-by-default manifest',
    );
    expect(
      File(
        '${androidApp.path}/src/devRelease/AndroidManifest.xml',
      ).existsSync(),
      isFalse,
      reason: 'devRelease must not override the deny-by-default manifest',
    );
  });
}
