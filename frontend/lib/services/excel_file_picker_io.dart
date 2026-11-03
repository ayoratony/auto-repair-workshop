import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

class PickedSpreadsheetFile {
  final String name;
  final int size;
  final Uint8List bytes;
  PickedSpreadsheetFile({required this.name, required this.size, required this.bytes});
}

class ExcelFilePickerHelper {
  static Future<PickedSpreadsheetFile?> pickSpreadsheetFile() async {
    final List<PlatformFile> files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv'],
    );
    if (files.isEmpty) return null;
    final PlatformFile file = files.first;
    final Uint8List bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    return PickedSpreadsheetFile(name: file.name, size: file.size, bytes: bytes);
  }
}
