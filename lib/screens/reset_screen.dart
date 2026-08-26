import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Clears in-progress form/session state without deleting saved database records.
class ResetScreen extends StatefulWidget {
  const ResetScreen({
    super.key,
    this.embedded = false,
    this.onSessionReset,
  });

  final bool embedded;
  final VoidCallback? onSessionReset;

  @override
  State<ResetScreen> createState() => _ResetScreenState();
}

class _ResetScreenState extends State<ResetScreen> {
  static const _unlockCode = 'ramsai';

  final _codeController = TextEditingController();
  bool _resetting = false;

  bool get _showResetButton => _codeController.text == _unlockCode;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _runReset() async {
    if (!_showResetButton || _resetting) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset session?'),
        content: const Text(
          'Clear all open forms and in-progress entries?\n\n'
          'Saved customers, suppliers, bills, and history are kept.',
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
    widget.onSessionReset?.call();
    _codeController.clear();
    if (!mounted) return;
    setState(() => _resetting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Session cleared. All forms reset — saved records were not deleted.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Clears unsaved form entries and returns every screen to a '
            'fresh empty state. Customer, supplier, and bill history in '
            'the database are not deleted.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _codeController,
            decoration: const InputDecoration(
              labelText: 'Enter code to enable reset',
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_showResetButton) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 42,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
                onPressed: _resetting ? null : _runReset,
                icon: _resetting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.red,
                        ),
                      )
                    : const Icon(Icons.restart_alt),
                label: const Text('RESET'),
              ),
            ),
          ],
        ],
      ),
    );

    if (widget.embedded) return content;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('RESET')),
      body: content,
    );
  }
}
