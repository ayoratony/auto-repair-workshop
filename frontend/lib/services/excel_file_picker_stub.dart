import 'dart:typed_data';

class PickedSpreadsheetFile {
  final String name;
  final int size;
  final Uint8List bytes;
  PickedSpreadsheetFile({required this.name, required this.size, required this.bytes});
}

class ExcelFilePickerHelper {
  static Future<PickedSpreadsheetFile?> pickSpreadsheetFile() async {
    throw UnsupportedError('Cannot pick file on this platform');
  }
}
