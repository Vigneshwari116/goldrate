import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/database/backup_store.dart';
import 'package:path/path.dart' as p;

void main() {
  test('backup file names are dated and recognizable later', () {
    final name = BackupStore.fileNameFor(DateTime(2026, 8, 21, 13, 45, 9));
    expect(name, 'jewellery_backup_2026-08-21_134509.db');
    expect(BackupStore.isBackupFileName(name), isTrue);
    expect(BackupStore.isBackupFileName('notes.txt'), isFalse);
    expect(BackupStore.isBackupFileName('jewellery.db'), isFalse);
  });

  test('lists only backup files in the chosen folder, newest first', () {
    final dir = Directory.systemTemp.createTempSync('backup_store_');
    addTearDown(() => dir.deleteSync(recursive: true));

    File(p.join(dir.path, 'notes.txt')).writeAsStringSync('ignore');
    File(p.join(dir.path, 'jewellery_backup_2026-08-20_100000.db'))
        .writeAsStringSync('old');
    File(p.join(dir.path, 'jewellery_backup_2026-08-21_090000.db'))
        .writeAsStringSync('new');

    final files = BackupStore.listBackupsIn(dir.path);
    expect(files.map((f) => p.basename(f.path)).toList(), [
      'jewellery_backup_2026-08-21_090000.db',
      'jewellery_backup_2026-08-20_100000.db',
    ]);
  });
}
