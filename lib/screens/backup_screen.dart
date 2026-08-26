import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database/database_helper.dart';
import '../util/file_share.dart';

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
      final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final saved = await FileShare.shareOrSaveCopy(
        source: file,
        fileName: 'jewellery_backup_$stamp.db',
        folderName: 'JewelleryBackup',
        subject: 'Jewellery backup',
        text: 'SQLite backup of sales, purchase, masters and reports',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup saved: ${saved.path}')),
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
            'On Windows the backup is saved under Downloads\\JewelleryBackup (or Documents). On the phone it opens the share sheet so you can send it to WhatsApp or Files.',
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
            label: const Text('SAVE / SHARE DATABASE BACKUP'),
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
