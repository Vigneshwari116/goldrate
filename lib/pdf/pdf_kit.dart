import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

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

  static String safeFileName(String name) {
    var base = name.trim().isEmpty ? 'document' : name.trim();
    if (!base.toLowerCase().endsWith('.pdf')) base = '$base.pdf';
    return base.replaceAll(RegExp(r'[<>:"/\\|?*]+'), '_');
  }

  /// Phone: WhatsApp / share sheet. Windows: save under Documents or
  /// Downloads then open the PDF so it can be printed or saved again.
  static Future<File> sharePdf({
    required Uint8List bytes,
    required String fileName,
    String? subject,
    String? text,
  }) async {
    final safe = safeFileName(fileName);
    if (Platform.isAndroid || Platform.isIOS) {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$safe');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: subject,
        text: text,
      );
      return file;
    }

    final dir = await _desktopDir();
    final file = File('${dir.path}/$safe');
    await file.writeAsBytes(bytes, flush: true);
    await _openDesktopFile(file);
    return file;
  }

  static Future<Directory> _desktopDir() async {
    Directory? dir = await getDownloadsDirectory();
    dir ??= await getApplicationDocumentsDirectory();
    final out = Directory('${dir.path}${Platform.pathSeparator}JewelleryPDFs');
    if (!await out.exists()) {
      await out.create(recursive: true);
    }
    return out;
  }

  static Future<void> _openDesktopFile(File file) async {
    final uri = Uri.file(file.path);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}
    if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', file.path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [file.path]);
    } else {
      await Process.run('xdg-open', [file.path]);
    }
  }
}
