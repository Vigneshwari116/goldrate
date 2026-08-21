import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database/database_helper.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../utils/number_format.dart';

class OpeningWeightScreen extends StatefulWidget {
  const OpeningWeightScreen({super.key});

  @override
  State<OpeningWeightScreen> createState() => _OpeningWeightScreenState();
}

class _OpeningWeightScreenState extends State<OpeningWeightScreen> {
  final _formKey = GlobalKey<FormState>();

  final _gPureController = TextEditingController(text: '0.000');
  final _fineController = TextEditingController(text: '0.000');
  final _kachaController = TextEditingController(text: '0.000');
  final _silverController = TextEditingController(text: '0.000');
  final _cashController = TextEditingController(text: '0.000');

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
        'gPureWt': formatWeight(_gPureController.text),
        'fineWt': formatWeight(_fineController.text),
        'kachaWt': formatWeight(_kachaController.text),
        'silverWt': formatWeight(_silverController.text),
        'cash': formatWeight(_cashController.text),
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

  Widget _field(
      String label,
      TextEditingController controller, {
        String? Function(String?)? validator,
      }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(fontSize: 14),
        validator: validator ?? _validateWeight,
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
            formatWeight(value),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("OPENING WEIGHT"),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
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
                        _field("G.Pure Wt", _gPureController),
                        _field("Fine Wt", _fineController),
                        _field("Kacha Wt", _kachaController),
                        _field("Silver Wt", _silverController),
                        _field("Cash", _cashController),
                        SizedBox(
                          width: double.infinity,
                          height: 42,
                          child: ElevatedButton(
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
      ),
    );
  }
}