import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../database/database_helper.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;

  Future<void> _shareDb() async {
    setState(() => _busy = true);
    try {
      final path = await DatabaseHelper.instance.getDatabasePath();
      final file = File(path);
      if (!await file.exists()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Database file not found yet')),
        );
        return;
      }
      final dir = await getTemporaryDirectory();
      final copy = File('${dir.path}/jewellery_backup.db');
      await file.copy(copy.path);
      await Share.shareXFiles(
        [XFile(copy.path)],
        subject: 'Jewellery backup',
        text: 'SQLite backup of sales, purchase, masters and reports',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Share a copy of the shop database. Keep this file safe — it holds bills, balances and masters.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _busy ? null : _shareDb,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.backup),
            label: const Text('SHARE DATABASE BACKUP'),
          ),
        ],
      ),
    );

    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('BACKUP')),
      body: content,
    );
  }
}
