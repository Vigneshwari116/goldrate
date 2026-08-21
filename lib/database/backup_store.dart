import 'package:intl/intl.dart';

/// Dated backup folder name, matching the food-app backup style:
/// `jewellery_backup_yyyyMMdd_HHmm`.
class BackupNaming {
  BackupNaming._();

  static String folderNameFor(DateTime now) {
    final stamp = DateFormat('yyyyMMdd_HHmm').format(now);
    return 'jewellery_backup_$stamp';
  }

  static bool isBackupFolderName(String name) {
    return name.startsWith('jewellery_backup_');
  }
}
