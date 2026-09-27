import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

Future<String> resolveJewelleryDatabasePathImpl({
  required Future<String> Function() getDatabasesPath,
}) async {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    final supportDir = await getApplicationSupportDirectory();
    final dbDir = Directory(join(supportDir.path, 'databases'));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }

    final newPath = join(dbDir.path, 'jewellery.db');
    final legacyPath = join(await getDatabasesPath(), 'jewellery.db');
    final legacyFile = File(legacyPath);
    final newFile = File(newPath);
    if (await legacyFile.exists() && !await newFile.exists()) {
      await legacyFile.copy(newPath);
    }
    return newPath;
  }

  return join(await getDatabasesPath(), 'jewellery.db');
}
