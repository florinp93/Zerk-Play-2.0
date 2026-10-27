import 'package:shared_preferences/shared_preferences.dart';

import 'local_store.dart';

final class SharedPreferencesStore implements LocalStore {
  SharedPreferences? _prefs;

  @override
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  SharedPreferences get _readyPrefs {
    final prefs = _prefs;
    if (prefs == null) {
      throw StateError('SharedPreferencesStore.init() was not called.');
    }
    return prefs;
  }

  @override
  Future<String?> getString(String key) async => _readyPrefs.getString(key);

  @override
  Future<void> setString(String key, String value) async {
    await _readyPrefs.setString(key, value);
  }

  @override
  Future<void> remove(String key) async {
    await _readyPrefs.remove(key);
  }
}

