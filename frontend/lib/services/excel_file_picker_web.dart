// ignore: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

class PickedSpreadsheetFile {
  final String name;
  final int size;
  final Uint8List bytes;
  PickedSpreadsheetFile({required this.name, required this.size, required this.bytes});
}

class ExcelFilePickerHelper {
  static Future<PickedSpreadsheetFile?> pickSpreadsheetFile() async {
    final completer = Completer<PickedSpreadsheetFile?>();
    final uploadInput = html.FileUploadInputElement()
      ..accept = '.xlsx,.xls,.csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,application/vnd.ms-excel,text/csv';
    uploadInput.style.display = 'none';
    html.document.body?.append(uploadInput);

    bool fileSelected = false;

    uploadInput.onChange.listen((e) {
      final files = uploadInput.files;
      if (files != null && files.isNotEmpty) {
        fileSelected = true;
        final file = files.first;
        final reader = html.FileReader();
        reader.onLoadEnd.listen((e) {
          uploadInput.remove();
          if (reader.result != null) {
            final bytes = Uint8List.fromList(reader.result as List<int>);
            if (!completer.isCompleted) {
              completer.complete(PickedSpreadsheetFile(name: file.name, size: file.size, bytes: bytes));
            }
          } else {
            if (!completer.isCompleted) completer.complete(null);
          }
        });
        reader.onError.listen((e) {
          uploadInput.remove();
          if (!completer.isCompleted) completer.complete(null);
        });
        reader.readAsArrayBuffer(file);
      } else {
        uploadInput.remove();
        if (!completer.isCompleted) completer.complete(null);
      }
    });

    void onFocus(html.Event e) {
      html.window.removeEventListener('focus', onFocus);
      Timer(const Duration(milliseconds: 600), () {
        if (!fileSelected && !completer.isCompleted) {
          uploadInput.remove();
          completer.complete(null);
        }
      });
    }

    html.window.addEventListener('focus', onFocus);
    uploadInput.click();
    return completer.future;
  }
}
