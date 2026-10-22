import 'dart:html' as html;

void openUrlInNewTab(String url) {
  html.window.open(url, '_blank');
}
