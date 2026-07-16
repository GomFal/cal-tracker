import 'package:shared_preferences/shared_preferences.dart';

abstract interface class StringKeyValueStorage {
  Future<String?> readString(String key);
  Future<void> writeString(String key, String value);
  Future<void> remove(String key);
  Future<Set<String>> readKeys();
  Future<void> removeWhere(bool Function(String key) test);
}

class AppPreferencesStorage implements StringKeyValueStorage {
  AppPreferencesStorage({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> readString(String key) {
    return _preferences.getString(key);
  }

  @override
  Future<void> writeString(String key, String value) {
    return _preferences.setString(key, value);
  }

  @override
  Future<void> remove(String key) {
    return _preferences.remove(key);
  }

  @override
  Future<Set<String>> readKeys() {
    return _preferences.getKeys();
  }

  @override
  Future<void> removeWhere(bool Function(String key) test) async {
    final keys = await readKeys();
    for (final key in keys.where(test)) {
      await remove(key);
    }
  }
}
