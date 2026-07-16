import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'app_preferences_storage.dart';

typedef CacheDirectoryProvider = Future<Directory> Function();

/// File-backed storage for cache data that must not be included in OS backups.
///
/// The application cache directory is sandboxed and excluded from backup by
/// Android and iOS. This is deliberately not an application-level encryption
/// layer: at-rest protection continues to rely on the device and OS sandbox.
class PrivateCacheStorage implements StringKeyValueStorage {
  PrivateCacheStorage({
    CacheDirectoryProvider? cacheDirectoryProvider,
    StringKeyValueStorage? legacyStorage,
  })  : _cacheDirectoryProvider =
            cacheDirectoryProvider ?? getApplicationCacheDirectory,
        _legacyStorage = legacyStorage;

  static const _fileName = 'bettercalories_private_cache_v1.json';
  static const _schemaVersion = 1;
  static const _legacyPrefixes = {
    'nutrition_cache:v1:',
    'agent_chat_cache:v1:',
    'agent_chat_session:v1:',
  };

  final CacheDirectoryProvider _cacheDirectoryProvider;
  final StringKeyValueStorage? _legacyStorage;
  Future<void> _tail = Future.value();
  Map<String, String>? _values;
  File? _file;
  bool _initialized = false;

  @override
  Future<String?> readString(String key) {
    return _serialized(() async {
      await _initialize();
      return _values![key];
    });
  }

  @override
  Future<void> writeString(String key, String value) {
    return _serialized(() async {
      await _initialize();
      _values![key] = value;
      await _persist();
    });
  }

  @override
  Future<void> remove(String key) {
    return _serialized(() async {
      await _initialize();
      if (_values!.remove(key) != null) await _persist();
    });
  }

  @override
  Future<Set<String>> readKeys() {
    return _serialized(() async {
      await _initialize();
      return Set.unmodifiable(_values!.keys);
    });
  }

  @override
  Future<void> removeWhere(bool Function(String key) test) {
    return _serialized(() async {
      await _initialize();
      final keys = _values!.keys.where(test).toList(growable: false);
      if (keys.isEmpty) return;
      for (final key in keys) {
        _values!.remove(key);
      }
      await _persist();
    });
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _initialize() async {
    if (_initialized) return;

    if (_values == null) {
      final directory = await _cacheDirectoryProvider();
      await directory.create(recursive: true);
      final file = File('${directory.path}/$_fileName');
      _file = file;
      _values = await _readFile(file);
    }
    await _migrateLegacyValues();
    _initialized = true;
  }

  Future<Map<String, String>> _readFile(File file) async {
    if (!await file.exists()) return {};
    try {
      final envelope = _objectMap(jsonDecode(await file.readAsString()));
      if (envelope['schemaVersion'] != _schemaVersion) {
        throw const FormatException('Unsupported private cache schema');
      }
      final values = _objectMap(envelope['values']);
      return values.map((key, value) {
        if (value is! String) {
          throw const FormatException('Private cache value is not a string');
        }
        return MapEntry(key, value);
      });
    } on Object {
      await file.delete().catchError((_) => file);
      return {};
    }
  }

  Future<void> _migrateLegacyValues() async {
    final legacyStorage = _legacyStorage;
    if (legacyStorage == null) return;

    final legacyKeys = (await legacyStorage.readKeys())
        .where(_isLegacyCacheKey)
        .toList(growable: false);
    if (legacyKeys.isEmpty) return;

    var changed = false;
    for (final key in legacyKeys) {
      if (_values!.containsKey(key)) continue;
      final value = await legacyStorage.readString(key);
      if (value == null) continue;
      _values![key] = value;
      changed = true;
    }
    if (changed) await _persist();

    // Delete only after the destination is durable. If deletion is interrupted,
    // the next initialization keeps the destination and retries this cleanup.
    for (final key in legacyKeys) {
      if (_values!.containsKey(key)) await legacyStorage.remove(key);
    }
  }

  bool _isLegacyCacheKey(String key) {
    return _legacyPrefixes.any(key.startsWith);
  }

  Future<void> _persist() async {
    final file = _file!;
    final temporaryFile = File('${file.path}.tmp');
    await temporaryFile.writeAsString(
      jsonEncode({'schemaVersion': _schemaVersion, 'values': _values}),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temporaryFile.rename(file.path);
  }
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is! Map) throw const FormatException('Expected JSON object');
  return value.map((key, nested) => MapEntry(key.toString(), nested));
}
