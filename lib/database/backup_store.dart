import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Remembers the folder the shop picked for database backups, and the
/// last time a copy was written there.
class BackupStore {
  BackupStore._();

  static const folderKey = 'backup_folder';
  static const lastPathKey = 'last_backup_path';
  static const lastTimeKey = 'last_backup_time';

  static const filePrefix = 'jewellery_backup_';
  static const fileExtension = '.db';

  static String fileNameFor(DateTime now) {
    final stamp = DateFormat('yyyy-MM-dd_HHmmss').format(now);
    return '$filePrefix$stamp$fileExtension';
  }

  static bool isBackupFileName(String name) {
    return name.startsWith(filePrefix) && name.endsWith(fileExtension);
  }

  static Future<String?> getFolder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(folderKey);
  }

  static Future<void> setFolder(String folder) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(folderKey, folder);
  }

  static Future<void> recordSuccessfulBackup(String path, DateTime when) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(lastPathKey, path);
    await prefs.setString(
      lastTimeKey,
      DateFormat('dd-MM-yyyy HH:mm:ss').format(when),
    );
  }

  static Future<String?> getLastBackupPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(lastPathKey);
  }

  static Future<String?> getLastBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(lastTimeKey);
  }

  /// Newest backup files first, from the chosen folder.
  static List<File> listBackupsIn(String folder) {
    final dir = Directory(folder);
    if (!dir.existsSync()) return [];
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => isBackupFileName(p.basename(f.path)))
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }
}
