import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

Future<void> saveAndDownloadPdfImpl(Uint8List bytes, String filename) async {
  await Printing.sharePdf(bytes: bytes, filename: filename);
}

Future<void> printPdfBytesImpl(Uint8List bytes, String docName) async {
  await Printing.layoutPdf(
    format: PdfPageFormat.a4,
    name: docName,
    onLayout: (_) async => bytes,
  );
}

Future<void> openExternalUrlImpl(String url) async {
  // Stub for non-web tests/platforms
}
