import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../database/database_helper.dart';
import '../theme/app_theme.dart';
import '../utils/number_format.dart';
import '../utils/stock_ledger.dart';
import '../widgets/app_shell.dart';

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
  final _cashController = TextEditingController(text: '0');

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
        'cash': orZero(_cashController.text),
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

  Widget _lockedRow(String label, dynamic value, {bool isWeight = true}) {
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
            isWeight ? formatWeight(value) : orZero(value?.toString()),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: shellMenuButton(context),
          title: const Text("STOCK"),
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'OPENING'),
              Tab(text: 'CURRENT STOCK'),
              Tab(text: 'STOCK LEDGER'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildOpeningTab(),
            const _CurrentStockTab(),
            const _StockLedgerTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildOpeningTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
        padding: const EdgeInsets.all(12),
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
                      _lockedRow("Cash", _saved!['cash'], isWeight: false),
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
    );
  }
}

class _CurrentStockTab extends StatefulWidget {
  const _CurrentStockTab();

  @override
  State<_CurrentStockTab> createState() => _CurrentStockTabState();
}

class _CurrentStockTabState extends State<_CurrentStockTab> {
  List<StockSummaryRow> _rows = [];
  String _cash = '0';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await DatabaseHelper.instance.getStockSummary();
    final opening = await DatabaseHelper.instance.getOpeningWeight();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _cash = orZero(opening?['cash']?.toString());
      _loading = false;
    });
  }

  Future<void> _share() async {
    if (_rows.isEmpty) return;
    final buffer = StringBuffer();
    buffer.writeln('Metal,Opening,Purchase,Sales,Current');
    for (final r in _rows) {
      buffer.writeln(
        '${r.label},${formatWeight(r.opening)},${formatWeight(r.purchased)},'
        '${formatWeight(r.sold)},${formatWeight(r.current)}',
      );
    }
    buffer.writeln('Cash opening,$_cash,,,');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/current_stock.csv');
    await file.writeAsString(buffer.toString());
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Current Stock',
      text: 'Current stock',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Opening + Purchase − Sales  =  stock in the shop now',
                  style: TextStyle(fontSize: 12.5, color: AppColors.mutedBlue),
                ),
              ),
              IconButton(
                tooltip: 'Share Excel',
                onPressed: _share,
                icon: const Icon(Icons.share, color: AppColors.navy),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: MediaQuery.of(context).size.width - 24,
              ),
              child: DataTable(
                headingRowColor:
                    WidgetStateProperty.all(AppColors.tableHeader),
                headingTextStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ),
                columns: const [
                  DataColumn(label: Text('Metal')),
                  DataColumn(label: Text('Opening'), numeric: true),
                  DataColumn(label: Text('Purchase'), numeric: true),
                  DataColumn(label: Text('Sales'), numeric: true),
                  DataColumn(label: Text('Current'), numeric: true),
                ],
                rows: [
                  for (final r in _rows)
                    DataRow(cells: [
                      DataCell(Text('${r.label}  (${r.type})')),
                      DataCell(Text(formatWeight(r.opening))),
                      DataCell(Text(formatWeight(r.purchased))),
                      DataCell(Text(formatWeight(r.sold))),
                      DataCell(Text(
                        formatWeight(r.current),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      )),
                    ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFDCE8F5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Opening cash  ₹$_cash',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StockLedgerTab extends StatefulWidget {
  const _StockLedgerTab();

  @override
  State<_StockLedgerTab> createState() => _StockLedgerTabState();
}

class _StockLedgerTabState extends State<_StockLedgerTab> {
  String _type = kMetalTypes.first;
  List<StockLedgerRow> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await DatabaseHelper.instance.getStockLedger(_type);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _share() async {
    if (_rows.isEmpty) return;
    final buffer = StringBuffer();
    buffer.writeln('Date,Time,Type,Particulars,In,Out,Balance');
    for (final r in _rows) {
      buffer.writeln(
        '${r.date},${r.time},${r.refType},${r.particulars},'
        '${formatWeight(r.qtyIn)},${formatWeight(r.qtyOut)},'
        '${formatWeight(r.balance)}',
      );
    }
    final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/stock_ledger_$_type.csv');
    await file.writeAsString(buffer.toString());
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Stock Ledger ${kMetalLabels[_type]}',
      text: 'Stock ledger',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _type,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Metal'),
                  items: [
                    for (final t in kMetalTypes)
                      DropdownMenuItem(
                        value: t,
                        child: Text('${kMetalLabels[t]}  ($t)'),
                      ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _type = v);
                    _load();
                  },
                ),
              ),
              IconButton(
                tooltip: 'Share Excel',
                onPressed: _share,
                icon: const Icon(Icons.share, color: AppColors.navy),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Text(
            'Same as a shop stock book: opening, then every purchase in and sale out, with running balance.',
            style: TextStyle(fontSize: 12.5, color: AppColors.mutedBlue),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _rows.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final e = _rows[i];
                      final opening = e.refType == 'OPENING';
                      final isIn = e.refType != 'SALES';
                      return Material(
                        color: AppColors.cardWhite,
                        child: ListTile(
                          leading: Icon(
                            opening
                                ? Icons.flag_outlined
                                : isIn
                                    ? Icons.arrow_downward
                                    : Icons.arrow_upward,
                            color: opening
                                ? AppColors.navy
                                : isIn
                                    ? Colors.green
                                    : Colors.red,
                          ),
                          title: Text(
                            opening
                                ? 'OPENING  +${formatWeight(e.qtyIn)}'
                                : '${e.refType}  •  ${isIn ? '+${formatWeight(e.qtyIn)}' : '-${formatWeight(e.qtyOut)}'}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          subtitle: Text(
                            '${e.particulars}\n${e.date}  ${e.time}',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          isThreeLine: true,
                          trailing: Text(
                            'Bal ${formatWeight(e.balance)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.navy,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}