import 'dart:typed_data';

class PickedFileData {
  final String name;
  final Uint8List bytes;
  PickedFileData({required this.name, required this.bytes});
}

class ImagePickerHelper {
  static Future<PickedFileData?> pickImage() async => null;
}
