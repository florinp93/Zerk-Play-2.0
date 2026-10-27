abstract interface class LocalStore {
  Future<void> init();

  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
  Future<void> remove(String key);
}

