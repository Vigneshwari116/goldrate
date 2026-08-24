import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

/// Remembers the shop's preferred printer. Listing uses the OS — no
/// custom printer driver is required.
class PrinterPrefs {
  PrinterPrefs._();

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}preferred_printer.txt');
  }

  static Future<String?> getSelected() async {
    final file = await _file();
    if (!await file.exists()) return null;
    final name = (await file.readAsString()).trim();
    return name.isEmpty ? null : name;
  }

  static Future<void> setSelected(String name) async {
    final file = await _file();
    await file.writeAsString(name.trim(), flush: true);
  }

  static Future<List<String>> listPrinterNames() async {
    final names = <String>{};
    try {
      final printers = await Printing.listPrinters();
      for (final p in printers) {
        final n = p.name.trim();
        if (n.isNotEmpty) names.add(n);
      }
    } catch (_) {}
    if (Platform.isWindows) {
      try {
        final result = await Process.run(
          'powershell',
          [
            '-NoProfile',
            '-Command',
            'Get-Printer | Select-Object -ExpandProperty Name',
          ],
        );
        if (result.exitCode == 0) {
          for (final line in result.stdout.toString().split(RegExp(r'\r?\n'))) {
            final n = line.trim();
            if (n.isNotEmpty) names.add(n);
          }
        }
      } catch (_) {}
    }
    final list = names.toList()..sort();
    return list;
  }
}
