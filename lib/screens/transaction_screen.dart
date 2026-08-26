import 'dart:async';
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
import '../pdf/estimate_receipt_pdf.dart';
import '../pdf/pdf_kit.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../widgets/material_tile_card.dart';

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
  final _typeFocus = FocusNode();
  final _paymentFocus = FocusNode();

  bool _promptingAddLine = false;
  bool _sharingPdf = false;
  bool _advancingFocus = false;
  Timer? _touchPromptTimer;

  String _selectedItemType = _itemTypes.first;
  String _selectedPaymentMode = _paymentModes.first;

  final List<_TransactionItem> _items = [];

  int _nextBillNo = 1;
  bool _loading = true;
  bool _saving = false;

  List<Map<String, dynamic>> _history = [];
  Map<String, double> _rates = {};
  List<String> _partyNames = [];
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
    _partyController.addListener(() => _onPartyTextChanged());
    _touchFocus.addListener(_onTouchFocusChange);
  }

  bool _isTouchComplete(String trimmed) {
    if (trimmed.isEmpty) return false;
    if (trimmed == '0' || trimmed == '0.0' || trimmed == '0.00') return false;
    final touch = double.tryParse(trimmed);
    if (touch == null) return false;
    if (RegExp(r'^\d+\.\d{2}$').hasMatch(trimmed)) return true;
    if (RegExp(r'^\d+\.\d$').hasMatch(trimmed)) return true;
    if (RegExp(r'^\d+$').hasMatch(trimmed) && touch > 0) return true;
    return false;
  }

  void _scheduleTouchPrompt() {
    _touchPromptTimer?.cancel();
    final captured = _touchController.text.trim();
    if (!_isTouchComplete(captured)) return;
    _touchPromptTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted || _promptingAddLine) return;
      if (_touchController.text.trim() == captured) {
        _promptAddAnotherLine();
      }
    });
  }

  void _onTouchFocusChange() {
    if (_touchFocus.hasFocus || _advancingFocus || _promptingAddLine) return;
    Future.microtask(() {
      if (!mounted || _touchFocus.hasFocus || _weightFocus.hasFocus) return;
      final trimmed = _touchController.text.trim();
      if (!_isTouchComplete(trimmed)) return;
      _promptAddAnotherLine();
    });
  }

  void _onWeightChanged(String value) {
    final trimmed = value.trim();
    final weight = double.tryParse(trimmed);
    if (weight == null || weight <= 0) return;
    if (!RegExp(r'^\d+\.\d{3}$').hasMatch(trimmed)) return;
    _advancingFocus = true;
    _touchFocus.requestFocus();
    _touchController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _touchController.text.length,
    );
    _advancingFocus = false;
  }

  void _onTouchChanged(String value) {
    final trimmed = value.trim();
    if (!_isTouchComplete(trimmed)) return;
    _scheduleTouchPrompt();
  }

  @override
  void dispose() {
    _touchPromptTimer?.cancel();
    _partyController.dispose();
    _weightController.dispose();
    _touchController.dispose();
    _paymentAmountController.dispose();
    _weightFocus.dispose();
    _touchFocus.dispose();
    _typeFocus.dispose();
    _paymentFocus.dispose();
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

  void _onPartyTextChanged([String? value]) {
    final query = (value ?? _partyController.text).trim();

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
    _onPartyTextChanged(name);
    _weightFocus.requestFocus();
    _weightController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _weightController.text.length,
    );
  }

  void _focusPaymentField() {
    _paymentFocus.requestFocus();
    _paymentAmountController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _paymentAmountController.text.length,
    );
  }

  Iterable<String> _partyOptions(String query) {
    final lower = query.trim().toLowerCase();
    if (lower.isEmpty) return _partyNames.take(12);
    return _partyNames
        .where((n) => n.toLowerCase().contains(lower))
        .take(12);
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

  void _resetWeightFields({bool focusWeight = true}) {
    _weightController.text = '0.000';
    _touchController.text = '0.00';
    if (focusWeight) {
      _weightFocus.requestFocus();
    }
  }

  _TransactionItem? _validatedLine() {
    final weight = double.tryParse(_weightController.text.trim());
    final touch = double.tryParse(_touchController.text.trim());

    if (weight == null ||
        !_numberRegex.hasMatch(_weightController.text.trim()) ||
        weight <= 0) {
      return null;
    }
    if (touch == null || !_numberRegex.hasMatch(_touchController.text.trim())) {
      return null;
    }

    final rateName = kItemTypeToRateName[_selectedItemType];
    final rate = _rates[rateName];
    if (rate == null) return null;

    return _TransactionItem(
      type: _selectedItemType,
      weight: weight,
      touch: touch,
      rate: rate,
    );
  }

  bool _commitCurrentLine() {
    final line = _validatedLine();
    if (line == null) {
      final rateName = kItemTypeToRateName[_selectedItemType];
      if (_rates[rateName] == null) {
        _showMessage(
            "$rateName isn't set yet — update it on the Master screen first");
      } else {
        _showMessage('Enter weight and touch before continuing');
      }
      return false;
    }

    setState(() => _items.add(line));
    return true;
  }

  Future<void> _promptAddAnotherLine() async {
    if (_promptingAddLine) return;
    final line = _validatedLine();
    if (line == null) return;

    _promptingAddLine = true;
    final addAnother = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add this weight line?'),
        content: Text(
          '${line.type}  ${line.weight.toStringAsFixed(3)} g  ·  '
          'touch ${line.touch.toStringAsFixed(2)}%\n\n'
          'Add another weight line after this?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('NO'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('YES'),
          ),
        ],
      ),
    );
    _promptingAddLine = false;
    if (!mounted || addAnother == null) return;

    if (!_commitCurrentLine()) return;

    if (addAnother) {
      _resetWeightFields(focusWeight: false);
      _typeFocus.requestFocus();
    } else {
      _resetWeightFields(focusWeight: false);
      _focusPaymentField();
    }
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
    await _shareEstimate(savedRow);
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
      builder: (dialogContext) => AlertDialog(
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
            onPressed: _sharingPdf
                ? null
                : () async {
                    Navigator.pop(dialogContext);
                    await _sharePdf(row, estimate: true, openAfterSave: false);
                  },
            child: const Text("ESTIMATE"),
          ),
          TextButton(
            onPressed: _sharingPdf
                ? null
                : () async {
                    Navigator.pop(dialogContext);
                    await _sharePdf(row, estimate: false, openAfterSave: false);
                  },
            child: const Text("ACCOUNTS BILL"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
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
    final avgTouch = totalWt > 0
        ? items.fold<double>(0, (s, i) => s + i.weight * i.touch) / totalWt
        : 0.0;
    final ratePerGram = (totalPure > 0
            ? items.fold<double>(0, (s, i) => s + i.value) / totalPure
            : GoldLedger.goldRate(_rates))
        .toDouble();
    final closing = double.tryParse(
            (row['newGrams'] ?? row['balance'] ?? '0').toString()) ??
        0;
    final closingLabel =
        closing.abs() < 0.0005 ? 'NIL' : '${closing.toStringAsFixed(3)} g';
    final kind = row['transactionType'] == 'PURCHASE' ? 'PUR' : 'SAL';
    final paymentMode = (row['paymentMode'] ?? '').toString();
    final cashReceived = paymentMode == 'CASH'
        ? (double.tryParse((row['paymentAmount'] ?? '0').toString()) ?? 0.0)
        : 0.0;

    final doc = await PdfKit.document();
    doc.addPage(
      EstimateReceiptPdf.buildPage(
        transactionLabel:
            row['transactionType'] == 'PURCHASE' ? 'PURCHASE' : 'SALES',
        billKind: kind,
        row: row,
        phone: phone,
        items: [
          for (final item in items)
            ReceiptLineItem(
              token: item.type,
              weight: item.weight,
              touch: item.touch,
              pureWt: item.pureWt,
            ),
        ],
        totalWt: totalWt,
        totalPure: totalPure,
        avgTouch: avgTouch,
        ratePerGram: ratePerGram,
        closingLabel: closingLabel,
        cashReceived: cashReceived,
        paymentMode: paymentMode,
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

    final doc = await PdfKit.document();
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
            if ((row['paymentMode'] ?? '') == 'CASH')
              _pdfRow(
                'Cash Received',
                '₹${row['paymentAmount'] ?? '0'}',
                bold: true,
              ),
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
    bool openAfterSave = true,
  }) async {
    if (_sharingPdf) return;
    _sharingPdf = true;
    try {
      final bytes =
          estimate ? await _buildEstimatePdf(row) : await _buildAccountsPdf(row);
      final kind = _isPurchase ? 'purchase' : 'sales';
      final type = estimate ? 'estimate' : 'accounts';
      final file = await PdfKit.sharePdf(
        bytes: bytes,
        fileName: '${kind}_${type}_${row['billNo']}.pdf',
        subject:
            '${estimate ? 'Estimate' : 'Accounts bill'} #${row['billNo']} - ${row['partyName'] ?? ''}',
        text:
            '${_isPurchase ? 'Purchase' : 'Sales'} ${estimate ? 'estimate' : 'accounts bill'}. '
            'Share this PDF, then print from the share app or the opened PDF window.',
        openAfterSave: openAfterSave,
      );
      if (!mounted) return;
      if (!(Platform.isAndroid || Platform.isIOS)) {
        _showMessage('PDF saved: ${file.path}');
      }
    } finally {
      _sharingPdf = false;
    }
  }

  Future<void> _shareEstimate(Map<String, dynamic> row) =>
      _sharePdf(row, estimate: true, openAfterSave: false);

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
                child: Autocomplete<String>(
                  optionsBuilder: (value) => _partyOptions(value.text),
                  onSelected: _selectParty,
                  fieldViewBuilder:
                      (context, controller, focusNode, onFieldSubmitted) {
                    if (controller.text != _partyController.text) {
                      controller.text = _partyController.text;
                    }
                    return TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      style: const TextStyle(fontSize: 14),
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) {
                        _weightFocus.requestFocus();
                        _weightController.selection = TextSelection(
                          baseOffset: 0,
                          extentOffset: _weightController.text.length,
                        );
                      },
                      onChanged: (v) {
                        _partyController.text = v;
                        _onPartyTextChanged(v);
                      },
                      decoration: InputDecoration(
                        label: Text(_isCustomerParty
                            ? "Customer Name"
                            : "Supplier Name"),
                        helperText: 'Search saved name or type new',
                        helperStyle: const TextStyle(fontSize: 11),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          _partyLedgerRow(),
          const SizedBox(height: 6),
          const Text(
            "WEIGHT LINE",
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.mutedBlue),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Focus(
                  focusNode: _typeFocus,
                  child: DropdownButtonFormField<String>(
                    value: _selectedItemType,
                    decoration: const InputDecoration(
                      label: Text("Type"),
                      isDense: true,
                    ),
                    items: _itemTypes
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) {
                      setState(() => _selectedItemType = v!);
                      _weightFocus.requestFocus();
                    },
                  ),
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
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    label: Text("Weight (g)"),
                    isDense: true,
                  ),
                  onTap: () => _weightController.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: _weightController.text.length,
                  ),
                  onChanged: _onWeightChanged,
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
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    label: Text("Touch %"),
                    isDense: true,
                  ),
                  onTap: () => _touchController.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: _touchController.text.length,
                  ),
                  onChanged: _onTouchChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _itemsTable(),
          const Divider(height: 14, color: AppColors.border),
          Row(
            children: [
              _totalCell("TOTAL WT", _totalWt),
              _totalCell("PURE WT", _totalPureWt, decimals: 3),
              _totalCell("VALUE ₹", _totalValue),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            "PAYMENT",
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.mutedBlue),
          ),
          const SizedBox(height: 6),
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
                  focusNode: _paymentFocus,
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 14),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    label: Text(
                      _isGoldSettlement
                          ? "Amount (grams)"
                          : _selectedPaymentMode == 'CASH'
                              ? "Cash Received (₹)"
                              : "Amount (₹)"),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _conversionCard(),
          const SizedBox(height: 6),
          Row(
            children: [
              _totalCell("OLD BAL (g)", _settlement.oldGrams, decimals: 3),
              _totalCell("NEW BAL (g)", _settlement.newGrams,
                  highlight: true, decimals: 3),
            ],
          ),
          const SizedBox(height: 10),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
          MaterialTileCard(
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
                          onPressed: () => _shareEstimate(row),
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
            disableScroll: true,
            primary: LayoutBuilder(
              builder: (context, constraints) {
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    child: _buildFormCard(),
                  ),
                );
              },
            ),
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

  Widget _totalCell(String label, double value,
      {bool highlight = false, int decimals = 2}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: highlight ? AppColors.navy : AppColors.mutedBlue,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value.toStringAsFixed(decimals),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: highlight ? 14 : 12,
                fontWeight: FontWeight.bold,
                color: highlight ? AppColors.navy : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}




