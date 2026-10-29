// ignore: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

class PickedFileData {
  final String name;
  final Uint8List bytes;
  PickedFileData({required this.name, required this.bytes});
}

class ImagePickerHelper {
  static Future<PickedFileData?> pickImage() async {
    final completer = Completer<PickedFileData?>();
    final uploadInput = html.FileUploadInputElement()
      ..accept = 'image/jpeg,image/png,image/webp,image/jpg';
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
              completer.complete(PickedFileData(name: file.name, bytes: bytes));
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
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!fileSelected && !completer.isCompleted) {
          uploadInput.remove();
          completer.complete(null);
        }
      });
    }

    html.window.addEventListener('focus', onFocus, true);
    completer.future.whenComplete(() {
      html.window.removeEventListener('focus', onFocus, true);
    });

    uploadInput.click();
    return completer.future;
  }
}
