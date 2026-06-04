import 'package:shared_preferences/shared_preferences.dart';

class AppPreferencesStorage {
  AppPreferencesStorage({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  Future<String?> readString(String key) {
    return _preferences.getString(key);
  }

  Future<void> writeString(String key, String value) {
    return _preferences.setString(key, value);
  }

  Future<void> remove(String key) {
    return _preferences.remove(key);
  }

  Future<Set<String>> readKeys() {
    return _preferences.getKeys();
  }

  Future<void> removeWhere(bool Function(String key) test) async {
    final keys = await readKeys();
    for (final key in keys.where(test)) {
      await remove(key);
    }
  }
}
