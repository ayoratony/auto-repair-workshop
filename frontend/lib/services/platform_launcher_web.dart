// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class PlatformLauncher {
  static void openUrl(String url) {
    try {
      html.window.open(url, '_blank');
    } catch (_) {}
  }
}
