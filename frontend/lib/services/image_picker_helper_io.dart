import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

class PickedFileData {
  final String name;
  final Uint8List bytes;
  PickedFileData({required this.name, required this.bytes});
}

class ImagePickerHelper {
  static Future<PickedFileData?> pickImage() async {
    final List<PlatformFile> files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (files.isEmpty) return null;
    final PlatformFile file = files.first;
    final Uint8List bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    return PickedFileData(name: file.name, bytes: bytes);
  }
}
