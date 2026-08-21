import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await _useWritableDatabaseFolder();
  }

  runApp(const JewelleryApp());
}

/// Installed Windows copies live under Program Files, which is read-only.
/// Put jewellery.db in the user's AppData folder instead, and copy any
/// older file that was created next to the exe.
Future<void> _useWritableDatabaseFolder() async {
  final support = await getApplicationSupportDirectory();
  await Directory(support.path).create(recursive: true);
  final dest = File(p.join(support.path, 'jewellery.db'));

  if (!await dest.exists()) {
    final oldCopies = <File>[
      File(p.join(
        Directory.current.path,
        '.dart_tool',
        'sqflite_common_ffi',
        'databases',
        'jewellery.db',
      )),
      File(p.join(await getDatabasesPath(), 'jewellery.db')),
    ];
    for (final old in oldCopies) {
      if (await old.exists()) {
        try {
          await old.copy(dest.path);
          break;
        } catch (_) {}
      }
    }
  }

  await databaseFactory.setDatabasesPath(support.path);
}

class JewelleryApp extends StatelessWidget {
  const JewelleryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jewellery Management',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const LoginScreen(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.noScaling,
          ),
          child: child!,
        );
      },
    );
  }
}
