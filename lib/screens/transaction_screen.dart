import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../database/database_helper.dart';
import '../logic/gold_ledger.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';

enum TransactionKind { purchase, sales }

const Map<String, String> kItemTypeToRateName = {
  'GWT': 'G.P RATE',
  'FWT': 'F.T RATE',
  'KWT': 'KACHA RATE',
  'SWT': 'S RATE',
};

class _TransactionItem {
  final String type;
  final double weight;
  final double touch;
  final double rate;

  _TransactionItem({
    required this.type,
    required this.weight,
    required this.touch,
    required this.rate,
  });

  double get pureWt => weight * touch / 100;

  double get value => pureWt * rate;

  Map<String, dynamic> toJson() => {
    'type': type,
    'weight': weight,
    'touch': touch,
    'pureWt': double.parse(pureWt.toStringAsFixed(3)),
    'rate': rate,
    'value': value,
  };

  factory _TransactionItem.fromJson(Map<String, dynamic> json) =>
      _TransactionItem(
        type: json['type'] as String,
        weight: (json['weight'] as num).toDouble(),
        touch: (json['touch'] as num).toDouble(),
        rate: (json['rate'] as num?)?.toDouble() ?? 0,
      );
}

class TransactionScreen extends StatefulWidget {
  final TransactionKind kind;
  final bool embedded;

  const TransactionScreen({
    super.key,
    required this.kind,
    this.embedded = false,
  });

  @override
  State<TransactionScreen> createState() => _TransactionScreenState();
}

class _TransactionScreenState extends State<TransactionScreen> {
  static const _itemTypes = ['GWT', 'FWT', 'KWT', 'SWT'];
  static const _paymentModes = ['CASH', 'UPI', 'GOLD'];

  static final RegExp _numberRegex = RegExp(r'^\d+(\.\d+)?$');

  final _partyController = TextEditingController();
  final _weightController = TextEditingController(text: '0.000');
  final _touchController = TextEditingController(text: '0.00');
  final _paymentAmountController = TextEditingController(text: '0.00');
  final _weightFocus = FocusNode();
  final _touchFocus = FocusNode();

  String _selectedItemType = _itemTypes.first;
  String _selectedPaymentMode = _paymentModes.first;

  final List<_TransactionItem> _items = [];

  int _nextBillNo = 1;
  bool _loading = true;
  bool _saving = false;

  List<Map<String, dynamic>> _history = [];
  Map<String, double> _rates = {};
  List<String> _partyNames = [];
  List<String> _partySuggestions = [];
  Map<String, double>? _partyOutstanding;

  /// Purchase looks up Suppliers (stock coming in from them); Sales
  /// looks up Customers (stock going out to them).
  bool get _isCustomerParty => !_isPurchase;

  bool get _isPurchase => widget.kind == TransactionKind.purchase;

  String get _transactionType => _isPurchase ? 'PURCHASE' : 'SALES';

  String get _title => _isPurchase ? 'PURCHASE' : 'SALES';

  double get _totalWt =>
      _items.fold(0, (sum, item) => sum + item.weight);

  double get _totalPureWt =>
      _items.fold(0, (sum, item) => sum + item.pureWt);

  double get _totalValue =>
      _items.fold(0, (sum, item) => sum + item.value);

  double get _paymentAmount =>
      double.tryParse(_paymentAmountController.text.trim()) ?? 0;

  /// A GOLD settlement is measured against the pure weight (grams);
  /// CASH/UPI is measured against the rupee value — mixing the two
  /// units is how balances quietly go wrong on paper books too.
  bool get _isGoldSettlement => _selectedPaymentMode == 'GOLD';

  SettlementResult get _settlement {
    return settleLedger(
      oldGrams: _partyOutstanding?['grams'] ?? 0,
      oldRupees: _partyOutstanding?['rupees'] ?? 0,
      billGrams: _totalPureWt,
      billRupees: _totalValue,
      paymentMode: _selectedPaymentMode,
      paymentAmount: _paymentAmount,
      ratePerGram: GoldLedger.goldRate(_rates),
      billSign: _isPurchase ? -1 : 1,
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
    _partyController.addListener(_onPartyTextChanged);
  }

  @override
  void dispose() {
    _partyController.dispose();
    _weightController.dispose();
    _touchController.dispose();
    _paymentAmountController.dispose();
    _weightFocus.dispose();
    _touchFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final billNo =
    await DatabaseHelper.instance.getNextBillNo(_transactionType);
    final history =
    await DatabaseHelper.instance.getTransactions(_transactionType);
    final rates = await DatabaseHelper.instance.getRatesMap();
    final partyNames = await DatabaseHelper.instance
        .getDistinctPartyNames(isCustomer: _isCustomerParty);
    if (!mounted) return;
    setState(() {
      _nextBillNo = billNo;
      _history = history;
      _rates = rates;
      _partyNames = partyNames;
      _loading = false;
    });
  }

  void _onPartyTextChanged() {
    final query = _partyController.text.trim();
    final lower = query.toLowerCase();

    setState(() {
      _partySuggestions = query.isEmpty
          ? []
          : _partyNames
              .where((n) =>
                  n.toLowerCase().contains(lower) && n.toLowerCase() != lower)
              .take(4)
              .toList();
    });

    if (query.isEmpty) {
      setState(() => _partyOutstanding = {'rupees': 0, 'grams': 0});
      return;
    }

    DatabaseHelper.instance
        .getPartyOutstanding(query, isCustomer: _isCustomerParty)
        .then((result) {
      if (!mounted) return;
      setState(() => _partyOutstanding = result);
    });
  }

  void _selectParty(String name) {
    _partyController.text = name;
    setState(() => _partySuggestions = []);
  }

  Widget _ledgerChip(String label, String value) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.headerBand,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.mutedBlue)),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navy)),
          ],
        ),
      ),
    );
  }

  Widget _partyLedgerRow() {
    final o = _partyOutstanding;
    if (_partyController.text.trim().isEmpty) return const SizedBox.shrink();
    if (o == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text('Looking up CR / DR / gold…',
            style: TextStyle(fontSize: 12, color: AppColors.mutedBlue)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          _ledgerChip(
            'CR',
            '₹${(o['crRupees'] ?? 0).toStringAsFixed(2)}  ·  '
            '${(o['crGrams'] ?? 0).toStringAsFixed(3)} g',
          ),
          _ledgerChip(
            'DR',
            '₹${(o['drRupees'] ?? 0).toStringAsFixed(2)}  ·  '
            '${(o['drGrams'] ?? 0).toStringAsFixed(3)} g',
          ),
          _ledgerChip(
            'GOLD',
            '${(o['grams'] ?? 0).toStringAsFixed(3)} g',
          ),
        ],
      ),
    );
  }

  void _resetWeightFields() {
    _weightController.text = '0.000';
    _touchController.text = '0.00';
    _weightFocus.requestFocus();
  }

  void _addItem() {
    final weight = double.tryParse(_weightController.text.trim());
    final touch = double.tryParse(_touchController.text.trim());

    if (weight == null ||
        !_numberRegex.hasMatch(_weightController.text.trim()) ||
        weight <= 0) {
      _showMessage("Enter a weight greater than 0.000");
      return;
    }
    if (touch == null || !_numberRegex.hasMatch(_touchController.text.trim())) {
      _showMessage("Enter a valid touch %");
      return;
    }

    final rateName = kItemTypeToRateName[_selectedItemType];
    final rate = _rates[rateName];
    if (rate == null) {
      _showMessage(
          "$rateName isn't set yet — update it on the Master screen first");
      return;
    }

    setState(() {
      _items.add(_TransactionItem(
        type: _selectedItemType,
        weight: weight,
        touch: touch,
        rate: rate,
      ));
    });
    _resetWeightFields();
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _clearForm() {
    _partyController.clear();
    _resetWeightFields();
    _paymentAmountController.text = '0.00';
    setState(() {
      _items.clear();
      _selectedItemType = _itemTypes.first;
      _selectedPaymentMode = _paymentModes.first;
      _partySuggestions = [];
      _partyOutstanding = null;
    });
  }

  Future<void> _saveTransaction() async {
    if (_partyController.text.trim().isEmpty) {
      _showMessage("Enter a name");
      return;
    }
    if (_items.isEmpty) {
      _showMessage("Add at least one weight line");
      return;
    }

    setState(() => _saving = true);

    final date = DateFormat("dd-MM-yyyy").format(DateTime.now());
    final time = DateFormat("hh:mm a").format(DateTime.now());

    final s = _settlement;
    final record = {
      'transactionType': _transactionType,
      'billNo': _nextBillNo,
      'partyName': _partyController.text.trim(),
      'items': jsonEncode(_items.map((i) => i.toJson()).toList()),
      'totalWt': _totalWt.toStringAsFixed(2),
      'totalPureWt': _totalPureWt.toStringAsFixed(3),
      'totalValue': _totalValue.toStringAsFixed(2),
      'paymentMode': _selectedPaymentMode,
      'paymentAmount': _paymentAmount.toStringAsFixed(2),
      'balance': s.newGrams.toStringAsFixed(3),
      'balanceUnit': 'GRAMS',
      'date': date,
      'time': time,
      'oldGrams': s.oldGrams.toStringAsFixed(3),
      'oldRupees': s.oldRupees.toStringAsFixed(2),
      'newGrams': s.newGrams.toStringAsFixed(3),
      'newRupees': s.newRupees.toStringAsFixed(2),
      'cashToGold': s.cashToGoldGrams.toStringAsFixed(3),
      'goldRateUsed': s.ratePerGram.toStringAsFixed(2),
    };

    await DatabaseHelper.instance.ensureParty(
      _partyController.text.trim(),
      isCustomer: _isCustomerParty,
    );
    await DatabaseHelper.instance.insertTransaction(record);
    await _postToLedger(date, time, s);

    if (!mounted) return;

    setState(() => _saving = false);

    final savedRow = Map<String, dynamic>.from(record);
    final billNoSaved = _nextBillNo;
    final partyName = _partyController.text.trim();
    _clearForm();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              "Bill #$billNoSaved saved and posted to $partyName's ledger")),
    );

    await _load();
    if (!mounted) return;
    await _offerPrints(savedRow);
  }

  Future<void> _offerPrints(Map<String, dynamic> row) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _isPurchase ? 'Purchase saved' : 'Sale saved',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Print the estimate (weight) and the accounts bill (money). '
          'Both use the same saved bill number. Nothing extra is stored.',
        ),
        actions: [
          TextButton(
            onPressed: () => _shareEstimate(row),
            child: const Text('PRINT ESTIMATE'),
          ),
          TextButton(
            onPressed: () => _shareAccountsBill(row),
            child: const Text('PRINT ACCOUNTS BILL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }

  /// Posts this bill's balance to the matching party's ledger table —
  /// Purchase bills post to Suppliers, Sales bills post to Customers.
  /// A positive balance (party still owes the shop) goes in the DR
  /// column; a negative balance (shop owes the party) goes in CR —
  /// mirroring how the existing Customer/Supplier Master screens
  /// already use those two fields.
  Future<void> _postToLedger(
      String date, String time, SettlementResult s) async {
    final deltaG = s.newGrams - s.oldGrams;
    final narration =
        "Bill #$_nextBillNo (${_isPurchase ? 'Purchase' : 'Sale'}) — "
        "GWT ${_totalWt.toStringAsFixed(2)}, Pure ${_totalPureWt.toStringAsFixed(3)}, "
        "Value ₹${_totalValue.toStringAsFixed(2)}, "
        "${s.paymentLabel}. Old ${s.oldGrams.toStringAsFixed(3)}g → "
        "New ${s.newGrams.toStringAsFixed(3)}g";

    final baseEntry = {
      'name': _partyController.text.trim(),
      'mobile': '',
      'city': '',
      'cr': deltaG < 0 ? deltaG.abs().toStringAsFixed(3) : '0',
      'dr': deltaG > 0 ? deltaG.toStringAsFixed(3) : '0',
      'narration': narration,
      'balanceUnit': 'GRAMS',
      'billRef': '${_isPurchase ? 'PUR' : 'SAL'}-$_nextBillNo',
      'date': date,
      'time': time,
    };

    if (_isPurchase) {
      await DatabaseHelper.instance.insertSupplier({
        ...baseEntry,
        'gross': _totalWt.toStringAsFixed(2),
        'net': _totalValue.toStringAsFixed(2),
      });
    } else {
      await DatabaseHelper.instance.insertCustomer({
        ...baseEntry,
        'drGross': _totalWt.toStringAsFixed(2),
        'drNet': _totalValue.toStringAsFixed(2),
      });
    }
  }

  Future<void> _confirmDelete(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Bill"),
        content: const Text("Are you sure you want to delete this record?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DatabaseHelper.instance.deleteTransaction(id);
      _load();
    }
  }

  void _showBillDetails(Map<String, dynamic> row) {
    final items = (jsonDecode(row['items'] as String) as List)
        .map((e) => _TransactionItem.fromJson(e as Map<String, dynamic>))
        .toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          "Bill #${row['billNo']}   ${row['partyName'] ?? ''}",
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    "${item.type} — Wt ${item.weight}  Touch ${item.touch}%  "
                        "Pure ${item.pureWt.toStringAsFixed(3)}  "
                        "@ ₹${item.rate.toStringAsFixed(0)}  "
                        "= ₹${item.value.toStringAsFixed(2)}",
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              const Divider(),
              _detailRow("Total Wt", row['totalWt']),
              _detailRow("Total Pure Wt", row['totalPureWt']),
              _detailRow("Total Value (₹)", row['totalValue']),
              _detailRow("Payment Mode", row['paymentMode']),
              _detailRow("Payment Amount", row['paymentAmount']),
              _detailRow(
                "Balance",
                "${row['balance'] ?? '-'} ${row['balanceUnit'] ?? ''}",
              ),
              _detailRow("Date", "${row['date'] ?? ''} ${row['time'] ?? ''}"),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _shareEstimate(row),
            child: const Text("ESTIMATE"),
          ),
          TextButton(
            onPressed: () => _shareAccountsBill(row),
            child: const Text("ACCOUNTS BILL"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CLOSE"),
          ),
        ],
      ),
    );
  }
  List<_TransactionItem> _itemsFromRow(Map<String, dynamic> row) {
    return (jsonDecode((row['items'] ?? '[]').toString()) as List)
        .map((e) => _TransactionItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Uint8List> _buildEstimatePdf(Map<String, dynamic> row) async {
    final items = _itemsFromRow(row);
    final phone = await DatabaseHelper.instance.getPartyPhone(
      (row['partyName'] ?? '').toString(),
      isCustomer: _isCustomerParty,
    );
    final totalWt =
        items.fold<double>(0, (sum, item) => sum + item.weight);
    final totalPure =
        items.fold<double>(0, (sum, item) => sum + item.pureWt);
    final closing = double.tryParse((row['newGrams'] ?? row['balance'] ?? '0').toString()) ?? 0;
    final closingLabel =
        closing.abs() < 0.0005 ? 'NIL' : '${closing.toStringAsFixed(3)} g';
    final kind = row['transactionType'] == 'PURCHASE' ? 'PUR' : 'SAL';

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(22),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('ESTIMATE ONLY',
                    style: pw.TextStyle(
                        fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.Text(
                  row['transactionType'] == 'PURCHASE'
                      ? 'PURCHASE'
                      : 'SALES',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.blueGrey),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Time: ${row['time'] ?? ''}'),
                  pw.Text('Date: ${row['date'] ?? ''}'),
                  pw.Text('Name: ${row['partyName'] ?? '-'}'),
                  if (phone.isNotEmpty) pw.Text('Phone: $phone'),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.blueGrey100),
              cellStyle: const pw.TextStyle(fontSize: 10),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerRight,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
              },
              headers: ['SNo', 'Weight', 'Touch', 'Pure'],
              data: [
                for (var i = 0; i < items.length; i++)
                  [
                    '${i + 1}',
                    items[i].weight.toStringAsFixed(3),
                    items[i].touch.toStringAsFixed(2),
                    items[i].pureWt.toStringAsFixed(3),
                  ],
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.SizedBox(
                  width: 220,
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Total Weight',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.Text(totalWt.toStringAsFixed(3),
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            _pdfRow('PURE GOLD', totalPure.toStringAsFixed(3), bold: true),
            _pdfRow('CLOSING BALANCE', closingLabel, bold: true),
            pw.Divider(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Bill No. $kind-${row['billNo']}'),
                pw.Text('${row['date'] ?? ''}'),
              ],
            ),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Name: ${row['partyName'] ?? '-'}'),
                pw.Text('Weight: ${totalWt.toStringAsFixed(3)}'),
              ],
            ),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text('${items.length}'),
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  Future<Uint8List> _buildAccountsPdf(Map<String, dynamic> row) async {
    final items = _itemsFromRow(row);
    final phone = await DatabaseHelper.instance.getPartyPhone(
      (row['partyName'] ?? '').toString(),
      isCustomer: _isCustomerParty,
    );
    final kind = row['transactionType'] == 'PURCHASE' ? 'PUR' : 'SAL';
    final cashToGold = (row['cashToGold'] ?? '').toString();

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(22),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Text(
                'JEWELLERY MANAGEMENT',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Center(
              child: pw.Text(
                row['transactionType'] == 'PURCHASE'
                    ? 'PURCHASE ACCOUNTS BILL'
                    : 'SALES ACCOUNTS BILL',
                style: const pw.TextStyle(fontSize: 11),
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Bill No: $kind-${row['billNo']}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text('${row['date'] ?? ''}  ${row['time'] ?? ''}'),
              ],
            ),
            pw.Text('Name: ${row['partyName'] ?? '-'}'),
            if (phone.isNotEmpty) pw.Text('Phone: $phone'),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headers: ['SNo', 'Type', 'Weight', 'Touch %', 'Pure', 'Rate', 'Value Rs.'],
              data: [
                for (var i = 0; i < items.length; i++)
                  [
                    '${i + 1}',
                    items[i].type,
                    items[i].weight.toStringAsFixed(3),
                    items[i].touch.toStringAsFixed(2),
                    items[i].pureWt.toStringAsFixed(3),
                    items[i].rate.toStringAsFixed(0),
                    items[i].value.toStringAsFixed(2),
                  ],
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Divider(),
            _pdfRow('Total Weight', (row['totalWt'] ?? '').toString()),
            _pdfRow('Total Pure Wt', (row['totalPureWt'] ?? '').toString()),
            _pdfRow('Total Value (Rs.)', row['totalValue']),
            pw.SizedBox(height: 6),
            _pdfRow('Payment (${row['paymentMode'] ?? '-'})', row['paymentAmount']),
            if (cashToGold.isNotEmpty && cashToGold != '0.000')
              _pdfRow('Cash to gold', '$cashToGold g'),
            _pdfRow('Old gold balance', '${row['oldGrams'] ?? '-'} g'),
            _pdfRow('New gold balance', '${row['newGrams'] ?? row['balance'] ?? '-'} g',
                bold: true),
          ],
        ),
      ),
    );
    return doc.save();
  }

  pw.Widget _pdfRow(String label, dynamic value, {bool bold = false}) {
    final style = pw.TextStyle(
      fontSize: bold ? 13 : 11,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: style),
          pw.Text('${value ?? '-'}', style: style),
        ],
      ),
    );
  }

  Future<void> _sharePdf(
    Map<String, dynamic> row, {
    required bool estimate,
  }) async {
    final bytes =
        estimate ? await _buildEstimatePdf(row) : await _buildAccountsPdf(row);
    final kind = _isPurchase ? 'purchase' : 'sales';
    final type = estimate ? 'estimate' : 'accounts';
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${kind}_${type}_${row['billNo']}.pdf');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles(
      [XFile(file.path)],
      subject:
          '${estimate ? 'Estimate' : 'Accounts bill'} #${row['billNo']} - ${row['partyName'] ?? ''}',
      text: '${_isPurchase ? 'Purchase' : 'Sales'} ${estimate ? 'estimate' : 'accounts bill'}',
    );
  }

  Future<void> _shareEstimate(Map<String, dynamic> row) =>
      _sharePdf(row, estimate: true);

  Future<void> _shareAccountsBill(Map<String, dynamic> row) =>
      _sharePdf(row, estimate: false);

  String _historyCsvEscape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  Future<void> _shareHistory() async {
    if (_history.isEmpty) {
      _showMessage("No bills to share yet");
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln(
      "Bill No,Party,Total Wt,Total Pure Wt,Total Value,Payment Mode,"
          "Payment Amount,Balance,Balance Unit,Date,Time",
    );

    for (final row in _history) {
      final line = [
        row['billNo'],
        row['partyName'],
        row['totalWt'],
        row['totalPureWt'],
        row['totalValue'],
        row['paymentMode'],
        row['paymentAmount'],
        row['balance'],
        row['balanceUnit'],
        row['date'],
        row['time'],
      ].map((v) => _historyCsvEscape(v?.toString() ?? '')).join(',');
      buffer.writeln(line);
    }

    final dir = await getTemporaryDirectory();
    final fileName =
        '${_isPurchase ? 'purchase' : 'sales'}_history.csv';
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(buffer.toString());

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: '${_isPurchase ? 'Purchase' : 'Sales'} History',
      text: '${_isPurchase ? 'Purchase' : 'Sales'} history export',
    );
  }

  Widget _detailRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 13, color: Colors.black87),
          children: [
            TextSpan(
              text: "$label: ",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: (value ?? '-').toString()),
          ],
        ),
      ),
    );
  }
  Widget _buildFormCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                "BILL NO",
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.mutedBlue),
              ),
              const SizedBox(width: 8),
              Text(
                "$_nextBillNo",
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                DateFormat("dd-MM-yyyy  hh:mm a").format(DateTime.now()),
                style: const TextStyle(
                    fontSize: 11.5, color: Colors.black54),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _partyController,
                  style: const TextStyle(fontSize: 14),
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    label: Text(_isCustomerParty
                        ? "Customer Name"
                        : "Supplier Name"),
                    helperText: "Type a saved name to load CR, DR and gold",
                    helperStyle: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
          if (_partySuggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: AppColors.cardWhite,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                children: _partySuggestions
                    .map((name) => ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          title: Text(name, style: const TextStyle(fontSize: 13)),
                          onTap: () => _selectParty(name),
                        ))
                    .toList(),
              ),
            ),
          _partyLedgerRow(),
          const SizedBox(height: 14),
          const Text(
            "WEIGHT LINES  ·  type weight and touch, then press Enter",
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.mutedBlue),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  value: _selectedItemType,
                  decoration: const InputDecoration(label: Text("Type")),
                  items: _itemTypes
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedItemType = v!),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _weightController,
                  focusNode: _weightFocus,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  textInputAction: TextInputAction.next,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(label: Text("Weight (g)")),
                  onTap: () => _weightController.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: _weightController.text.length,
                  ),
                  onFieldSubmitted: (_) => _touchFocus.requestFocus(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _touchController,
                  focusNode: _touchFocus,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  textInputAction: TextInputAction.done,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(label: Text("Touch %")),
                  onTap: () => _touchController.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: _touchController.text.length,
                  ),
                  onFieldSubmitted: (_) => _addItem(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _itemsTable(),
          const Divider(height: 24, color: AppColors.border),
          _totalRow("TOTAL WT", _totalWt),
          _totalRow("TOTAL PURE WT", _totalPureWt, decimals: 3),
          _totalRow("TOTAL VALUE (₹)", _totalValue),
          const SizedBox(height: 14),
          const Text(
            "MODE OF PAYMENT",
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.mutedBlue),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  value: _selectedPaymentMode,
                  decoration: const InputDecoration(label: Text("Mode")),
                  items: _paymentModes
                      .map((m) =>
                      DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _selectedPaymentMode = v!),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _paymentAmountController,
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 14),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    label: Text(
                        _isGoldSettlement ? "Amount (grams)" : "Amount (₹)"),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _conversionCard(),
          const SizedBox(height: 10),
          _totalRow("OLD BALANCE (g)", _settlement.oldGrams, decimals: 3),
          _totalRow("NEW BALANCE (g)", _settlement.newGrams,
              highlight: true, decimals: 3),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.navy,
                foregroundColor: Colors.white,
              ),
              onPressed: _saving ? null : _saveTransaction,
              child: _saving
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
                  : Text(_isPurchase ? "SAVE PURCHASE" : "SAVE SALE"),
            ),
          ),
        ],
      ),
    );
  }
  Widget _itemsTable() {
    final headerStyle = const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: AppColors.navy,
    );
    final cellStyle = const TextStyle(fontSize: 12.5);

    Widget head(String text, {int flex = 2, TextAlign align = TextAlign.left}) {
      return Expanded(
        flex: flex,
        child: Text(text, style: headerStyle, textAlign: align),
      );
    }

    Widget cell(String text, {int flex = 2, TextAlign align = TextAlign.left}) {
      return Expanded(
        flex: flex,
        child: Text(text, style: cellStyle, textAlign: align),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Container(
            color: AppColors.tableHeader,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                head('TYPE', flex: 2),
                head('WEIGHT', flex: 2, align: TextAlign.right),
                head('TOUCH %', flex: 2, align: TextAlign.right),
                head('PURE WT', flex: 2, align: TextAlign.right),
                head('RATE', flex: 2, align: TextAlign.right),
                head('VALUE ₹', flex: 3, align: TextAlign.right),
                const SizedBox(width: 28),
              ],
            ),
          ),
          if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'No lines yet — enter weight and touch, then press Enter',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            )
          else
            for (var i = 0; i < _items.length; i++)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: i.isEven ? Colors.white : AppColors.headerBand,
                  border: const Border(
                    top: BorderSide(color: AppColors.border),
                  ),
                ),
                child: Row(
                  children: [
                    cell(_items[i].type, flex: 2),
                    cell(_items[i].weight.toStringAsFixed(3),
                        flex: 2, align: TextAlign.right),
                    cell(_items[i].touch.toStringAsFixed(2),
                        flex: 2, align: TextAlign.right),
                    cell(_items[i].pureWt.toStringAsFixed(3),
                        flex: 2, align: TextAlign.right),
                    cell(_items[i].rate.toStringAsFixed(0),
                        flex: 2, align: TextAlign.right),
                    cell(_items[i].value.toStringAsFixed(2),
                        flex: 3, align: TextAlign.right),
                    SizedBox(
                      width: 28,
                      child: IconButton(
                        icon: const Icon(Icons.close,
                            size: 16, color: Colors.redAccent),
                        onPressed: () => _removeItem(i),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _conversionCard() {
    final s = _settlement;
    final rate = s.ratePerGram;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.headerBand,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isGoldSettlement
                ? "Gold payment ${s.paymentAmount.toStringAsFixed(3)} g"
                : rate <= 0
                    ? "Set today's G.P RATE to convert cash into gold"
                    : "Cash ₹${s.paymentAmount.toStringAsFixed(2)} → "
                        "${s.cashToGoldGrams.toStringAsFixed(3)} g  "
                        "(rate ₹${rate.toStringAsFixed(0)}/g)",
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Bill ${_isPurchase ? 'PUR' : 'SAL'}-$_nextBillNo  ·  "
            "GWT ${_totalWt.toStringAsFixed(2)}  ·  "
            "${s.paymentMode}  ·  "
            "Balance gold ${s.newGrams.toStringAsFixed(3)} g",
            style: const TextStyle(fontSize: 11.5, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            "${_isPurchase ? 'PURCHASE' : 'SALES'} HISTORY (${_history.length})",
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              letterSpacing: 0.4,
              color: AppColors.mutedBlue,
            ),
          ),
        ),
        if (_history.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                "No bills yet",
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardWhite,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: List.generate(_history.length, (index) {
                final row = _history[index];
                final isLast = index == _history.length - 1;

                return Container(
                  decoration: BoxDecoration(
                    border: isLast
                        ? null
                        : const Border(
                      bottom: BorderSide(color: AppColors.border),
                    ),
                  ),
                  child: ListTile(
                    dense: true,
                    onTap: () => _showBillDetails(row),
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.headerBand,
                      child: Text(
                        "${row['billNo']}",
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.navy),
                      ),
                    ),
                    title: Text(
                      "${row['partyName'] ?? ''}",
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    subtitle: Text(
                      "₹${row['totalValue'] ?? '-'}   "
                          "${row['paymentMode'] ?? ''} ${row['paymentAmount'] ?? ''}   "
                          "Bal ${row['balance'] ?? '-'} ${row['balanceUnit'] ?? ''}",
                      style: const TextStyle(
                          fontSize: 11.5, color: Colors.black54),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.share,
                              color: AppColors.mutedBlue, size: 18),
                          onPressed: () => _offerPrints(row),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete,
                              color: Colors.redAccent, size: 18),
                          onPressed: () => _confirmDelete(row['id'] as int),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : WorkbenchLayout(
            equalSplit: true,
            primary: _buildFormCard(),
            secondary: _buildHistorySection(),
          );

    if (widget.embedded) return content;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            icon: const Icon(Icons.share, size: 20),
            tooltip: 'Share ${_isPurchase ? 'purchase' : 'sales'} history',
            onPressed: _shareHistory,
          ),
        ],
      ),
      body: content,
    );
  }

  Widget _totalRow(String label, double value,
      {bool highlight = false, int decimals = 2}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: highlight ? AppColors.navy : AppColors.mutedBlue,
              ),
            ),
          ),
          Text(
            value.toStringAsFixed(decimals),
            style: TextStyle(
              fontSize: highlight ? 17 : 15,
              fontWeight: FontWeight.bold,
              color: highlight ? AppColors.navy : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}




