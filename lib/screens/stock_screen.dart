import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../theme/app_theme.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  bool _loading = true;
  Map<String, double> _stock = {};
  Map<String, dynamic>? _opening;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stock = await DatabaseHelper.instance.getCurrentStock();
    final opening = await DatabaseHelper.instance.getOpeningWeight();
    if (!mounted) return;
    setState(() {
      _stock = stock;
      _opening = opening;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Live stock is opening weight + purchases − sales. It is not typed daily.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 16),
              _tile('G.Pure (GWT)', _stock['GWT'] ?? 0),
              _tile('Fine (FWT)', _stock['FWT'] ?? 0),
              _tile('Kacha (KWT)', _stock['KWT'] ?? 0),
              _tile('Silver (SWT)', _stock['SWT'] ?? 0),
              if (_opening != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Opening cash ${_opening!['cash'] ?? '0'}  ·  set ${_opening!['date'] ?? ''}',
                  style: const TextStyle(color: AppColors.mutedBlue),
                ),
              ],
            ],
          );

    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('STOCK')),
      body: content,
    );
  }

  Widget _tile(String label, double value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          Text('${value.toStringAsFixed(3)} g',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.navy)),
        ],
      ),
    );
  }
}
