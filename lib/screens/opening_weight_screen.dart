import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../util/focus_chain.dart';
import '../util/field_advance.dart';
import '../database/database_helper.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';

class OpeningWeightScreen extends StatefulWidget {
  const OpeningWeightScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<OpeningWeightScreen> createState() => _OpeningWeightScreenState();
}

class _OpeningWeightScreenState extends State<OpeningWeightScreen>
    with FocusAdvanceMixin {
  final _formKey = GlobalKey<FormState>();

  final _gPureController = TextEditingController(text: '0.000');
  final _fineController = TextEditingController(text: '0.000');
  final _kachaController = TextEditingController(text: '0.000');
  final _silverController = TextEditingController(text: '0.000');
  final _cashController = TextEditingController(text: '0');

  final _gPureFocus = FocusNode();
  final _fineFocus = FocusNode();
  final _kachaFocus = FocusNode();
  final _silverFocus = FocusNode();
  final _cashFocus = FocusNode();
  final _saveFocus = FocusNode();

  static final RegExp _numberRegex = RegExp(r'^\d+(\.\d+)?$');

  bool _loading = true;
  bool _saving = false;
  Map<String, dynamic>? _saved;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _gPureFocus.dispose();
    _fineFocus.dispose();
    _kachaFocus.dispose();
    _silverFocus.dispose();
    _cashFocus.dispose();
    _saveFocus.dispose();
    _gPureController.dispose();
    _fineController.dispose();
    _kachaController.dispose();
    _silverController.dispose();
    _cashController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final existing = await DatabaseHelper.instance.getOpeningWeight();
    if (!mounted) return;
    setState(() {
      _saved = existing;
      _loading = false;
    });
  }

  String? _validateWeight(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return "Required";
    if (!_numberRegex.hasMatch(value)) return "Numbers only";
    return null;
  }

  Future<void> _confirmAndSave() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Save Opening Weight"),
        content: const Text(
          "This can only be saved once. Once saved, these values cannot "
              "be changed or edited from the app. Continue?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Save"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _saving = true);

    final date = DateFormat("dd-MM-yyyy").format(DateTime.now());
    final time = DateFormat("hh:mm a").format(DateTime.now());

    try {
      await DatabaseHelper.instance.insertOpeningWeight({
        'gPureWt': _gPureController.text.trim(),
        'fineWt': _fineController.text.trim(),
        'kachaWt': _kachaController.text.trim(),
        'silverWt': _silverController.text.trim(),
        'cash': _cashController.text.trim(),
        'date': date,
        'time': time,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Opening weight saved and locked")),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Could not save: $e")),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _onWeightChanged(
    String value,
    FocusNode from,
    FocusNode to,
    TextEditingController toController,
  ) {
    advanceWhenComplete(
      value: value,
      from: from,
      isComplete: FieldComplete.masterWeight,
      to: to,
      toController: toController,
    );
    advanceWhenIdle(
      value: value,
      from: from,
      when: FieldComplete.weightWholeIdle,
      to: to,
      toController: toController,
    );
  }

  void _onCashChanged(String value) {
    advanceWhenComplete(
      value: value,
      from: _cashFocus,
      isComplete: FieldComplete.cash,
      to: _saveFocus,
    );
    advanceWhenIdle(
      value: value,
      from: _cashFocus,
      when: FieldComplete.weightWholeIdle,
      to: _saveFocus,
    );
  }

  Widget _field(
      String label,
      TextEditingController controller, {
        FocusNode? focusNode,
        VoidCallback? onFieldSubmitted,
        ValueChanged<String>? onChanged,
        String? Function(String?)? validator,
      }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(fontSize: 14),
        textInputAction: TextInputAction.next,
        validator: validator ?? _validateWeight,
        onFieldSubmitted: (_) => onFieldSubmitted?.call(),
        onChanged: onChanged,
        decoration: InputDecoration(label: Text(label)),
      ),
    );
  }

  Widget _lockedRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.mutedBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            (value ?? '-').toString(),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : Padding(
        padding: const EdgeInsets.all(12),
        child: CenteredMaxWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_saved != null) ...[
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.cardWhite,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.lock, size: 16, color: AppColors.mutedBlue),
                          SizedBox(width: 6),
                          Text(
                            "LOCKED — SET ONCE",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.mutedBlue,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20, color: AppColors.border),
                      _lockedRow("G.Pure Wt", _saved!['gPureWt']),
                      _lockedRow("Fine Wt", _saved!['fineWt']),
                      _lockedRow("Kacha Wt", _saved!['kachaWt']),
                      _lockedRow("Silver Wt", _saved!['silverWt']),
                      _lockedRow("Cash", _saved!['cash']),
                      const Divider(height: 20, color: AppColors.border),
                      Text(
                        "Saved on ${_saved!['date'] ?? ''} ${_saved!['time'] ?? ''}",
                        style: const TextStyle(
                            fontSize: 11.5, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.cardWhite,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "Enter starting stock weight (one-time only)",
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.mutedBlue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _field("G.Pure Wt", _gPureController,
                            focusNode: _gPureFocus,
                            onChanged: (v) => _onWeightChanged(
                                  v,
                                  _gPureFocus,
                                  _fineFocus,
                                  _fineController,
                                ),
                            onFieldSubmitted: () => FocusChain.focus(
                                _fineFocus, controller: _fineController)),
                        _field("Fine Wt", _fineController,
                            focusNode: _fineFocus,
                            onChanged: (v) => _onWeightChanged(
                                  v,
                                  _fineFocus,
                                  _kachaFocus,
                                  _kachaController,
                                ),
                            onFieldSubmitted: () => FocusChain.focus(
                                _kachaFocus, controller: _kachaController)),
                        _field("Kacha Wt", _kachaController,
                            focusNode: _kachaFocus,
                            onChanged: (v) => _onWeightChanged(
                                  v,
                                  _kachaFocus,
                                  _silverFocus,
                                  _silverController,
                                ),
                            onFieldSubmitted: () => FocusChain.focus(
                                _silverFocus, controller: _silverController)),
                        _field("Silver Wt", _silverController,
                            focusNode: _silverFocus,
                            onChanged: (v) => _onWeightChanged(
                                  v,
                                  _silverFocus,
                                  _cashFocus,
                                  _cashController,
                                ),
                            onFieldSubmitted: () => FocusChain.focus(
                                _cashFocus, controller: _cashController)),
                        _field("Cash", _cashController,
                            focusNode: _cashFocus,
                            onChanged: _onCashChanged),
                        SizedBox(
                          width: double.infinity,
                          height: 42,
                          child: ElevatedButton(
                            focusNode: _saveFocus,
                            onPressed: _saving ? null : _confirmAndSave,
                            child: _saving
                                ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                                : const Text("SAVE"),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );

    if (widget.embedded) return body;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text("OPENING WEIGHT")),
      body: body,
    );
  }
}
