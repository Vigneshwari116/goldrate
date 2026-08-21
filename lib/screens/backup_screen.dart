import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../database/backup_store.dart';
import '../database/database_helper.dart';
import '../theme/app_theme.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  String? _folder;
  String? _lastPath;
  String? _lastTime;
  List<File> _backups = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final folder = await BackupStore.getFolder();
    final lastPath = await BackupStore.getLastBackupPath();
    final lastTime = await BackupStore.getLastBackupTime();
    final backups = folder == null ? <File>[] : BackupStore.listBackupsIn(folder);
    if (!mounted) return;
    setState(() {
      _folder = folder;
      _lastPath = lastPath;
      _lastTime = lastTime;
      _backups = backups;
      _loading = false;
    });
  }

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : AppColors.navy,
      ),
    );
  }

  Future<void> _pickFolder() async {
    final selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose a folder for database backups',
    );
    if (selected == null || selected.isEmpty) return;

    await BackupStore.setFolder(selected);
    await _reload();
    if (!mounted) return;
    _toast('Backup folder saved. New backups will be written here.');
  }

  Future<void> _backupNow() async {
    if (_folder == null) {
      _toast('Choose a folder first.', error: true);
      return;
    }

    setState(() => _busy = true);
    try {
      final now = DateTime.now();
      final dest = p.join(_folder!, BackupStore.fileNameFor(now));
      await DatabaseHelper.instance.copyDatabaseTo(dest);
      await BackupStore.recordSuccessfulBackup(dest, now);
      await _reload();
      if (!mounted) return;
      _toast('Database saved to the selected folder.');
    } catch (e) {
      if (!mounted) return;
      _toast('Could not save backup: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(File file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace current data?'),
        content: Text(
          'This will replace the live database with\n${p.basename(file.path)}.\n\n'
          'Everything currently in the app (bills, customers, rates, stock) '
          'will be overwritten. Make a backup first if you are unsure.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('RESTORE'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await DatabaseHelper.instance.restoreDatabaseFrom(file.path);
      if (!mounted) return;
      _toast('Database restored. Go back to Home to see the restored data.');
    } catch (e) {
      if (!mounted) return;
      _toast('Could not restore: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _meaningCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFDCE8F5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What backup means',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Backup copies the whole shop database (bills, customers, '
            'suppliers, rates, opening weight, and stock) into a file.\n\n'
            '1. Choose a folder once — a USB drive, Documents, or any folder '
            'you can find later.\n'
            '2. Tap BACKUP NOW. A dated file is saved in that folder.\n'
            '3. Later you can open this screen to see the folder, the last '
            'backup time, and every backup file. Tap a file to restore it '
            'if this computer is lost or the data is damaged.',
            style: TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.navy),
          ),
        ],
      ),
    );
  }

  Widget _folderCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'BACKUP FOLDER',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: AppColors.mutedBlue,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _folder ?? 'No folder selected yet',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _folder == null ? Colors.black54 : AppColors.navy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _lastTime == null
                ? 'No backup has been saved yet.'
                : 'Last backup: $_lastTime'
                    '${_lastPath == null ? '' : '\n${p.basename(_lastPath!)}'}',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _pickFolder,
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: Text(_folder == null ? 'CHOOSE FOLDER' : 'CHANGE FOLDER'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _busy || _folder == null ? null : _backupNow,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save, size: 18),
                  label: const Text('BACKUP NOW'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _backupList() {
    if (_folder == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'Choose a folder to see backup files saved there.',
          style: TextStyle(fontSize: 12.5, color: Colors.black54),
        ),
      );
    }

    if (_backups.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'No backup files in this folder yet. Tap BACKUP NOW to create one.',
          style: TextStyle(fontSize: 12.5, color: Colors.black54),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 8, bottom: 8),
          child: Text(
            'BACKUPS IN THIS FOLDER',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: AppColors.mutedBlue,
            ),
          ),
        ),
        ..._backups.map((file) {
          final stat = file.statSync();
          final kb = (stat.size / 1024).toStringAsFixed(1);
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppColors.cardWhite,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: ListTile(
              leading: const Icon(Icons.storage, color: AppColors.navy, size: 20),
              title: Text(p.basename(file.path)),
              subtitle: Text('$kb KB  ·  tap to restore'),
              trailing: const Icon(Icons.restore, color: AppColors.mutedBlue, size: 20),
              onTap: _busy ? null : () => _restore(file),
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('BACKUP')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _meaningCard(),
                      const SizedBox(height: 12),
                      _folderCard(),
                      _backupList(),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
