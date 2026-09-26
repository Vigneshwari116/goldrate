import 'dart:typed_data';

import 'package:printing/printing.dart';

/// Opens the platform print UI for an existing PDF byte stream.
class PdfPrint {
  PdfPrint._();

  static Future<bool> showDialog({
    required Uint8List bytes,
    required String documentName,
  }) {
    return Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: documentName,
    );
  }
}
