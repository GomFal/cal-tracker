import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Android disables backup and excludes every application data domain',
    () async {
      final manifest = await File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsString();
      final fullBackupRules = await File(
        'android/app/src/main/res/xml/backup_rules.xml',
      ).readAsString();
      final extractionRules = await File(
        'android/app/src/main/res/xml/data_extraction_rules.xml',
      ).readAsString();

      expect(manifest, contains('android:allowBackup="false"'));
      expect(
        manifest,
        contains('android:fullBackupContent="@xml/backup_rules"'),
      );
      expect(
        manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );
      for (final domain in [
        'root',
        'file',
        'database',
        'sharedpref',
        'external',
        'device_root',
        'device_file',
        'device_database',
        'device_sharedpref',
      ]) {
        expect(fullBackupRules, contains('domain="$domain"'));
        expect(extractionRules, contains('domain="$domain"'));
      }
      expect(extractionRules, contains('<cloud-backup>'));
      expect(extractionRules, contains('<device-transfer>'));
    },
  );

  test('iOS excludes legacy preferences from backup', () async {
    final appDelegate = await File(
      'ios/Runner/AppDelegate.swift',
    ).readAsString();

    expect(appDelegate, contains('excludePreferencesFromBackup()'));
    expect(
      appDelegate,
      contains('resourceValues.isExcludedFromBackup = true'),
    );
  });

  test('tokens remain isolated in native secure storage', () async {
    final tokenStorage = await File(
      'lib/data/services/secure_token_storage.dart',
    ).readAsString();
    final privateCache = await File(
      'lib/data/services/private_cache_storage.dart',
    ).readAsString();

    expect(tokenStorage, contains('FlutterSecureStorage'));
    expect(tokenStorage, contains("'access_token'"));
    expect(tokenStorage, contains("'refresh_token'"));
    expect(
      tokenStorage,
      contains('KeychainAccessibility.first_unlock_this_device'),
    );
    expect(tokenStorage, contains('KeychainAccessibility.unlocked'));
    expect(tokenStorage, contains('synchronizable: false'));
    expect(
      RegExp(r'iOptions: _iosOptions').allMatches(tokenStorage),
      hasLength(7),
      reason: 'The constructor and every token read/write/delete pin options.',
    );
    expect(
      RegExp(r'iOptions: _legacyIosOptions').allMatches(tokenStorage),
      hasLength(2),
      reason: 'Logout also deletes both legacy access and refresh tokens.',
    );
    expect(tokenStorage, contains('await _migrateLegacyTokenAccessibility'));
    expect(tokenStorage, contains('final migration = write(tokens)'));
    expect(privateCache, contains('getApplicationCacheDirectory'));
    expect(privateCache, isNot(contains('access_token')));
    expect(privateCache, isNot(contains('refresh_token')));
  });
}
