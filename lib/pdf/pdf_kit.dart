import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

import '../util/file_share.dart';

/// Unicode PDF fonts (fixes Helvetica "no Unicode support") plus
/// desktop Save/Open so Windows can keep a file and print it.
class PdfKit {
  PdfKit._();

  static pw.ThemeData? _theme;

  static Future<pw.ThemeData> theme() async {
    if (_theme != null) return _theme!;
    final regular = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final bold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    final fallback = <pw.Font>[
      pw.Font.ttf(
          await rootBundle.load('assets/fonts/NotoSansTamil-Regular.ttf')),
      pw.Font.ttf(await rootBundle
          .load('assets/fonts/NotoSansDevanagari-Regular.ttf')),
    ];
    if (Platform.isWindows) {
      for (final path in [
        r'C:\Windows\Fonts\Nirmala.ttf',
        r'C:\Windows\Fonts\arial.ttf',
      ]) {
        final file = File(path);
        if (await file.exists()) {
          fallback.add(pw.Font.ttf(ByteData.view(file.readAsBytesSync().buffer)));
          break;
        }
      }
    }
    _theme = pw.ThemeData.withFont(
      base: regular,
      bold: bold,
      fontFallback: fallback,
    );
    return _theme!;
  }

  static Future<pw.Document> document() async {
    return pw.Document(theme: await theme());
  }

  static String safeFileName(String name) => FileShare.safeFileName(
        name.toLowerCase().endsWith('.pdf') ? name : '$name.pdf',
      );

  static Future<File> sharePdf({
    required Uint8List bytes,
    required String fileName,
    String? subject,
    String? text,
    bool openAfterSave = true,
  }) {
    return FileShare.shareOrSaveBytes(
      bytes: bytes,
      fileName: safeFileName(fileName),
      folderName: 'JewelleryPDFs',
      subject: subject,
      text: text,
      openAfterSave: openAfterSave,
    );
  }
}
