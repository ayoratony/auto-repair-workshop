import 'session_storage_stub.dart'
    if (dart.library.html) 'session_storage_web.dart'
    if (dart.library.io) 'session_storage_io.dart';

class SessionStorage {
  static Future<void> setString(String key, String value) => PlatformStorage.setString(key, value);
  static Future<String?> getString(String key) => PlatformStorage.getString(key);
  static Future<void> remove(String key) => PlatformStorage.remove(key);
  static Future<void> clear() => PlatformStorage.clear();
}
