import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/database/backup_store.dart';

void main() {
  test('backup folders are dated like the food app backups', () {
    final name = BackupNaming.folderNameFor(DateTime(2026, 8, 21, 13, 45));
    expect(name, 'jewellery_backup_20260821_1345');
    expect(BackupNaming.isBackupFolderName(name), isTrue);
    expect(BackupNaming.isBackupFolderName('notes'), isFalse);
  });
}
