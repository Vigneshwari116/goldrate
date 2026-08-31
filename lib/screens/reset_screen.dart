import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../theme/app_theme.dart';
import '../util/focus_chain.dart';

/// Clears sales, purchase, and voucher records plus in-memory form state.
class ResetScreen extends StatefulWidget {
  const ResetScreen({
    super.key,
    this.embedded = false,
    this.onSessionReset,
  });

  final bool embedded;
  final Future<void> Function()? onSessionReset;

  @override
  State<ResetScreen> createState() => _ResetScreenState();
}

class _ResetScreenState extends State<ResetScreen> {
  static const _unlockCode = 'ramsai';

  final _codeController = TextEditingController();
  final _codeFocus = FocusNode();
  final _resetFocus = FocusNode();
  bool _resetting = false;

  bool get _showResetButton => _codeController.text == _unlockCode;

  @override
  void dispose() {
    _codeFocus.dispose();
    _resetFocus.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _onCodeChanged(String value) {
    setState(() {});
  }

  Future<void> _runReset() async {
    if (!_showResetButton || _resetting) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset sales, purchase & records?'),
        content: const Text(
          'This deletes all saved Sales bills, Purchase bills, and '
          'Receipt/Payment records.\n\n'
          'Customers, suppliers, rates, and opening weight are kept.',
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
      await DatabaseHelper.instance.clearSalesPurchaseAndRecords();
      await widget.onSessionReset?.call();
      _codeController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sales, purchase, and records cleared. Forms reset to empty.',
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
            'Deletes all Sales bills, Purchase bills, and Receipt/Payment '
            'records, then clears every open form. Customer and supplier '
            'masters, rates, and opening weight are not deleted.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _codeController,
            focusNode: _codeFocus,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Enter code to enable reset',
            ),
            onChanged: _onCodeChanged,
            onSubmitted: (_) {
              if (_showResetButton) {
                FocusChain.focus(_resetFocus);
              }
            },
          ),
          if (_showResetButton) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 42,
              child: OutlinedButton.icon(
                focusNode: _resetFocus,
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
