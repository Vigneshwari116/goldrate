import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database/database_helper.dart';
import '../navigation/app_page.dart';
import '../util/file_share.dart';
import '../util/session_prefs.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;
  bool _resetting = false;

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

  Future<void> _resetAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset all data?'),
        content: const Text(
          'This deletes every customer, supplier, bill, voucher, rate, '
          'and opening weight entry. Your login is kept.\n\n'
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'RESET',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _resetting = true);
    try {
      await DatabaseHelper.instance.resetAllBusinessData();
      await SessionPrefs.setLastPage(AppPage.home);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'All data cleared. Open Home, then revisit Sales/Purchase to start fresh.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reset failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _resetting = false);
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
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          const Text(
            'Reset removes all business data entered in the app and returns '
            'masters, bills, and rates to a blank default state.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
            ),
            onPressed: _resetting ? null : _resetAllData,
            icon: _resetting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.red,
                    ),
                  )
                : const Icon(Icons.delete_forever),
            label: const Text('RESET ALL DATA'),
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
