import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Phone uses the share sheet (WhatsApp). Windows/macOS/Linux save a
/// real file under Downloads or Documents and open it.
class FileShare {
  FileShare._();

  static String safeFileName(String name) {
    var base = name.trim().isEmpty ? 'file' : name.trim();
    return base.replaceAll(RegExp(r'[<>:"/\\|?*]+'), '_');
  }

  static Future<Directory> desktopFolder(String folderName) async {
    Directory? dir = await getDownloadsDirectory();
    dir ??= await getApplicationDocumentsDirectory();
    final out =
        Directory('${dir.path}${Platform.pathSeparator}$folderName');
    if (!await out.exists()) {
      await out.create(recursive: true);
    }
    return out;
  }

  static Future<void> openPath(String path) async {
    final uri = Uri.file(path);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}
    if (Platform.isWindows) {
      await Process.run('explorer.exe', ['/select,', path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', ['-R', path]);
    } else {
      await Process.run('xdg-open', [File(path).parent.path]);
    }
  }

  static Future<File> shareOrSaveBytes({
    required Uint8List bytes,
    required String fileName,
    String folderName = 'JewelleryPDFs',
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
    final dir = await desktopFolder(folderName);
    final file = File('${dir.path}${Platform.pathSeparator}$safe');
    await file.writeAsBytes(bytes, flush: true);
    await openPath(file.path);
    return file;
  }

  static Future<File> shareOrSaveCopy({
    required File source,
    required String fileName,
    String folderName = 'JewelleryBackup',
    String? subject,
    String? text,
  }) async {
    final bytes = await source.readAsBytes();
    return shareOrSaveBytes(
      bytes: bytes,
      fileName: fileName,
      folderName: folderName,
      subject: subject,
      text: text,
    );
  }
}
