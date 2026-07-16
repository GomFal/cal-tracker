import 'dart:convert';
import 'dart:io';

import 'package:cal_tracker_mobile/data/services/app_preferences_storage.dart';
import 'package:cal_tracker_mobile/data/services/private_cache_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory cacheDirectory;

  setUp(() async {
    cacheDirectory = await Directory.systemTemp.createTemp(
      'bettercalories-private-cache-test-',
    );
  });

  tearDown(() async {
    if (await cacheDirectory.exists()) {
      await cacheDirectory.delete(recursive: true);
    }
  });

  test('persists values in the application cache directory', () async {
    final storage = _storage(cacheDirectory);
    await storage.writeString('nutrition_cache:v1:user:daily', 'sensitive');

    final reloaded = _storage(cacheDirectory);
    expect(
      await reloaded.readString('nutrition_cache:v1:user:daily'),
      'sensitive',
    );
    expect(await reloaded.readKeys(), {'nutrition_cache:v1:user:daily'});
  });

  test('discards a corrupt cache file and remains usable', () async {
    final cacheFile = File(
      '${cacheDirectory.path}/bettercalories_private_cache_v1.json',
    );
    await cacheFile.writeAsString('{broken');

    final storage = _storage(cacheDirectory);
    expect(await storage.readKeys(), isEmpty);
    await storage.writeString('agent_chat_cache:v1:user:summaries', '[]');

    expect(
      await storage.readString('agent_chat_cache:v1:user:summaries'),
      '[]',
    );
    expect(jsonDecode(await cacheFile.readAsString()), isA<Map>());
  });

  test(
    'migrates legacy preferences once and removes the plaintext source',
    () async {
      final legacy = _MemoryStorage()
        ..values.addAll({
          'nutrition_cache:v1:user:daily': 'nutrition text',
          'agent_chat_cache:v1:user:summaries': 'conversation text',
          'agent_chat_session:v1:user:active': 'session text',
          'theme_mode': 'dark',
        });
      final storage = _storage(cacheDirectory, legacyStorage: legacy);

      expect(
        await storage.readString('nutrition_cache:v1:user:daily'),
        'nutrition text',
      );
      expect(
        await storage.readString('agent_chat_cache:v1:user:summaries'),
        'conversation text',
      );
      expect(
        legacy.values,
        {'theme_mode': 'dark'},
        reason: 'Only sensitive legacy cache keys are migrated and deleted.',
      );

      legacy.values['nutrition_cache:v1:user:daily'] = 'stale duplicate';
      final reloaded = _storage(cacheDirectory, legacyStorage: legacy);
      expect(
        await reloaded.readString('nutrition_cache:v1:user:daily'),
        'nutrition text',
        reason: 'An interrupted cleanup cannot overwrite the durable value.',
      );
      expect(legacy.values, {'theme_mode': 'dark'});
    },
  );

  test('removeWhere is idempotent', () async {
    final storage = _storage(cacheDirectory);
    await storage.writeString('nutrition_cache:v1:user-a:daily', 'a');
    await storage.writeString('nutrition_cache:v1:user-b:daily', 'b');

    await storage.removeWhere((key) => key.contains('user-a'));
    await storage.removeWhere((key) => key.contains('user-a'));

    expect(await storage.readKeys(), {'nutrition_cache:v1:user-b:daily'});
  });

  test('retries an interrupted legacy cleanup without losing data', () async {
    final legacy = _FailsFirstRemoveStorage()
      ..values['agent_chat_cache:v1:user:summaries'] = 'conversation text';
    final storage = _storage(cacheDirectory, legacyStorage: legacy);

    await expectLater(
      storage.readString('agent_chat_cache:v1:user:summaries'),
      throwsStateError,
    );
    expect(
      await storage.readString('agent_chat_cache:v1:user:summaries'),
      'conversation text',
    );
    expect(legacy.values, isEmpty);
  });
}

PrivateCacheStorage _storage(
  Directory directory, {
  StringKeyValueStorage? legacyStorage,
}) {
  return PrivateCacheStorage(
    cacheDirectoryProvider: () async => directory,
    legacyStorage: legacyStorage,
  );
}

class _MemoryStorage implements StringKeyValueStorage {
  final values = <String, String>{};

  @override
  Future<String?> readString(String key) async => values[key];

  @override
  Future<void> writeString(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<Set<String>> readKeys() async => values.keys.toSet();

  @override
  Future<void> removeWhere(bool Function(String key) test) async {
    values.removeWhere((key, _) => test(key));
  }
}

class _FailsFirstRemoveStorage extends _MemoryStorage {
  bool _shouldFail = true;

  @override
  Future<void> remove(String key) async {
    if (_shouldFail) {
      _shouldFail = false;
      throw StateError('simulated interrupted migration cleanup');
    }
    await super.remove(key);
  }
}
