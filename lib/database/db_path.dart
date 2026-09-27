import 'package:sqflite/sqflite.dart';

import 'db_path_io.dart' if (dart.library.html) 'db_path_web.dart';

/// Resolves a writable SQLite path on mobile, desktop, and web.
Future<String> resolveJewelleryDatabasePath() async {
  return resolveJewelleryDatabasePathImpl(
    getDatabasesPath: getDatabasesPath,
  );
}
