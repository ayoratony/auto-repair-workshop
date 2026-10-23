// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class PlatformStorage {
  static Future<void> setString(String key, String value) async {
    try {
      html.window.localStorage[key] = value;
    } catch (_) {}
  }

  static Future<String?> getString(String key) async {
    try {
      return html.window.localStorage[key];
    } catch (_) {
      return null;
    }
  }

  static Future<void> remove(String key) async {
    try {
      html.window.localStorage.remove(key);
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      html.window.localStorage.clear();
    } catch (_) {}
  }
}
