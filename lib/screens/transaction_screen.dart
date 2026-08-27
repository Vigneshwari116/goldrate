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
import '../models/party_suggestion.dart';
import '../widgets/party_search_field.dart';
import '../util/focus_chain.dart';
import '../theme/app_theme.dart';
import '../theme/field_sizes.dart';
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

class _MetalPanelRow {
  final String type;
  final TextEditingController weight;
  final TextEditingController touch;

  _MetalPanelRow(this.type)
      : weight = TextEditingController(text: '0.000'),
        touch = TextEditingController(text: '100.00');

  double get pureWt {
    final w = double.tryParse(weight.text.trim()) ?? 0;
    final t = double.tryParse(touch.text.trim()) ?? 0;
    return w * t / 100;
  }

  void clear() {
    weight.text = '0.000';
    touch.text = '100.00';
  }

  void dispose() {
    weight.dispose();
    touch.dispose();
  }
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

  final _partyController = TextEditingController();
  final _receiptCashController = TextEditingController(text: '0.00');
  final _issueWeightFocus = List.generate(4, (_) => FocusNode());
  final _receiptWeightFocus = List.generate(4, (_) => FocusNode());
  final _receiptCashFocus = FocusNode();

  late final Map<String, _MetalPanelRow> _issueRows = {
    for (final t in _itemTypes) t: _MetalPanelRow(t),
  };
  late final Map<String, _MetalPanelRow> _receiptRows = {
    for (final t in _itemTypes) t: _MetalPanelRow(t),
  };

  int _nextBillNo = 1;
  bool _loading = true;
  bool _saving = false;
  bool _sharingPdf = false;

  List<Map<String, dynamic>> _history = [];
  Map<String, double> _rates = {};
  List<PartySuggestion> _partySuggestions = [];
  Map<String, double>? _partyOutstanding;

  /// Purchase looks up Suppliers (stock coming in from them); Sales
  /// looks up Customers (stock going out to them).
  bool get _isCustomerParty => !_isPurchase;

  bool get _isPurchase => widget.kind == TransactionKind.purchase;

  String get _transactionType => _isPurchase ? 'PURCHASE' : 'SALES';

  String get _title => _isPurchase ? 'PURCHASE' : 'SALES';

  bool get _showPanels =>
      _partyController.text.trim().isNotEmpty || _hasIssueOrReceiptData;

  bool get _hasIssueOrReceiptData =>
      _issueRows.values.any((r) => (double.tryParse(r.weight.text) ?? 0) > 0) ||
      _receiptRows.values.any((r) => (double.tryParse(r.weight.text) ?? 0) > 0) ||
      (double.tryParse(_receiptCashController.text.trim()) ?? 0) > 0;

  List<_TransactionItem> get _issueItems {
    final items = <_TransactionItem>[];
    for (final type in _itemTypes) {
      final row = _issueRows[type]!;
      final weight = double.tryParse(row.weight.text.trim()) ?? 0;
      if (weight <= 0) continue;
      final touch = double.tryParse(row.touch.text.trim()) ?? 0;
      final rateName = kItemTypeToRateName[type];
      final rate = _rates[rateName] ?? 0;
      items.add(_TransactionItem(
        type: type,
        weight: weight,
        touch: touch,
        rate: rate,
      ));
    }
    return items;
  }

  double get _totalWt =>
      _issueItems.fold(0, (sum, item) => sum + item.weight);

  double get _totalPureWt =>
      _issueItems.fold(0, (sum, item) => sum + item.pureWt);

  double get _totalValue =>
      _issueItems.fold(0, (sum, item) => sum + item.value);

  double get _issueTotalPure =>
      _issueRows.values.fold(0, (sum, row) => sum + row.pureWt);

  double get _receiptMetalPure =>
      _receiptRows.values.fold(0, (sum, row) => sum + row.pureWt);

  double get _receiptCashAmount =>
      double.tryParse(_receiptCashController.text.trim()) ?? 0;

  double get _goldRate => GoldLedger.goldRate(_rates);

  double get _receiptCashGold =>
      GoldLedger.cashToGold(_receiptCashAmount, _goldRate);

  double get _receiptTotalPure => _receiptMetalPure + _receiptCashGold;

  double get _balancePure => _issueTotalPure - _receiptTotalPure;

  bool get _receiptIsCashOnly =>
      _receiptCashAmount > 0 && _receiptMetalPure <= 0;

  double get _paymentAmount => _receiptIsCashOnly
      ? _receiptCashAmount
      : _receiptTotalPure;

  SettlementResult get _settlement {
    return settleLedger(
      oldGrams: _partyOutstanding?['grams'] ?? 0,
      oldRupees: _partyOutstanding?['rupees'] ?? 0,
      billGrams: _totalPureWt,
      billRupees: _totalValue,
      paymentMode: _receiptIsCashOnly ? 'CASH' : 'GOLD',
      paymentAmount: _paymentAmount,
      ratePerGram: _goldRate,
      billSign: _isPurchase ? -1 : 1,
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
    _partyController.addListener(() => _onPartyTextChanged());
    for (final row in {..._issueRows.values, ..._receiptRows.values}) {
      row.weight.addListener(_onPanelChanged);
      row.touch.addListener(_onPanelChanged);
    }
    _receiptCashController.addListener(_onPanelChanged);
  }

  void _onPanelChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _partyController.dispose();
    _receiptCashController.dispose();
    for (final node in _issueWeightFocus) {
      node.dispose();
    }
    for (final node in _receiptWeightFocus) {
      node.dispose();
    }
    _receiptCashFocus.dispose();
    for (final row in {..._issueRows.values, ..._receiptRows.values}) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final billNo =
    await DatabaseHelper.instance.getNextBillNo(_transactionType);
    final history =
    await DatabaseHelper.instance.getTransactions(_transactionType);
    final rates = await DatabaseHelper.instance.getRatesMap();
    final partyRows = _isCustomerParty
        ? await DatabaseHelper.instance.getCustomers()
        : await DatabaseHelper.instance.getSuppliers();
    if (!mounted) return;
    setState(() {
      _nextBillNo = billNo;
      _history = history;
      _rates = rates;
      _partySuggestions = PartySuggestion.fromLedgerRows(partyRows);
      _loading = false;
    });
  }

  Future<void> _refreshParties() async {
    final partyRows = _isCustomerParty
        ? await DatabaseHelper.instance.getCustomers()
        : await DatabaseHelper.instance.getSuppliers();
    if (!mounted) return;
    setState(() {
      _partySuggestions = PartySuggestion.fromLedgerRows(partyRows);
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

  void _selectParty(PartySuggestion party) {
    _partyController.text = party.name;
    _onPartyTextChanged(party.name);
    FocusChain.focusNextFrame(
      _issueWeightFocus.first,
      controller: _issueRows[_itemTypes.first]!.weight,
    );
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

  void _clearPanels() {
    for (final row in _issueRows.values) {
      row.clear();
    }
    for (final row in _receiptRows.values) {
      row.clear();
    }
    _receiptCashController.text = '0.00';
  }

  void _clearForm() {
    _partyController.clear();
    _clearPanels();
    setState(() => _partyOutstanding = null);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  bool _validateIssueRates() {
    for (final item in _issueItems) {
      final rateName = kItemTypeToRateName[item.type];
      if ((_rates[rateName] ?? 0) <= 0) {
        _showMessage(
            "$rateName isn't set yet — update it on the Master screen first");
        return false;
      }
    }
    return true;
  }

  Future<void> _saveTransaction() async {
    if (_partyController.text.trim().isEmpty) {
      _showMessage("Enter a name");
      return;
    }
    if (_issueItems.isEmpty) {
      _showMessage("Enter at least one issue weight");
      return;
    }
    if (!_validateIssueRates()) return;

    setState(() => _saving = true);

    final date = DateFormat("dd-MM-yyyy").format(DateTime.now());
    final time = DateFormat("hh:mm a").format(DateTime.now());

    final items = _issueItems;
    final s = _settlement;
    final paymentMode = _receiptIsCashOnly ? 'CASH' : 'GOLD';
    final record = {
      'transactionType': _transactionType,
      'billNo': _nextBillNo,
      'partyName': _partyController.text.trim(),
      'items': jsonEncode(items.map((i) => i.toJson()).toList()),
      'totalWt': _totalWt.toStringAsFixed(2),
      'totalPureWt': _totalPureWt.toStringAsFixed(3),
      'totalValue': _totalValue.toStringAsFixed(2),
      'paymentMode': paymentMode,
      'paymentAmount': _paymentAmount.toStringAsFixed(
          _receiptIsCashOnly ? 2 : 3),
      'balance': s.newGrams.toStringAsFixed(3),
      'balanceUnit': 'GRAMS',
      'date': date,
      'time': time,
      'oldGrams': s.oldGrams.toStringAsFixed(3),
      'oldRupees': s.oldRupees.toStringAsFixed(2),
      'newGrams': s.newGrams.toStringAsFixed(3),
      'newRupees': s.newRupees.toStringAsFixed(2),
      'cashToGold': (_receiptCashGold > 0
              ? _receiptCashGold
              : s.cashToGoldGrams)
          .toStringAsFixed(3),
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
          SizedBox(
            width: FieldSizes.name,
            child: PartySearchField(
              label: _isCustomerParty
                  ? 'Customer Name'
                  : 'Supplier Name',
              controller: _partyController,
              parties: _partySuggestions,
              helperText: 'Search saved name, mobile, or city',
              onFocus: _refreshParties,
              onSelected: _selectParty,
              onFieldSubmitted: () => FocusChain.focusNextFrame(
                _issueWeightFocus.first,
                controller: _issueRows[_itemTypes.first]!.weight,
              ),
              onChanged: (v) {
                _onPartyTextChanged(v);
                setState(() {});
              },
            ),
          ),
          _partyLedgerRow(),
          if (_showPanels) ...[
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 720;
                if (stacked) {
                  return Column(
                    children: [
                      _issuePanel(),
                      const SizedBox(height: 10),
                      _receiptPanel(),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _issuePanel()),
                    const SizedBox(width: 10),
                    Expanded(child: _receiptPanel()),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            _balanceBar(),
          ],
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
  Widget _compactField({
    required double width,
    required Widget child,
  }) {
    return SizedBox(width: width, child: child);
  }

  Widget _panelShell({
    required String title,
    required List<Widget> rows,
    required String totalLabel,
    required double totalPure,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.headerBand,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          ...rows,
          const Divider(height: 16),
          Row(
            children: [
              Text(
                totalLabel,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.mutedBlue,
                ),
              ),
              const Spacer(),
              Text(
                '${totalPure.toStringAsFixed(3)} g',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metalPanelRow({
    required String prefix,
    required String type,
    required _MetalPanelRow row,
    FocusNode? weightFocus,
    bool readOnlyTouch = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          _compactField(
            width: FieldSizes.typeDropdown,
            child: InputDecorator(
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              ),
              child: Text(
                type,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _compactField(
            width: FieldSizes.weight,
            child: TextFormField(
              controller: row.weight,
              focusNode: weightFocus,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                labelText: '$prefix.Weight',
                isDense: true,
              ),
              onTap: () => row.weight.selection = TextSelection(
                baseOffset: 0,
                extentOffset: row.weight.text.length,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _compactField(
            width: FieldSizes.touch,
            child: TextFormField(
              controller: row.touch,
              readOnly: readOnlyTouch,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                labelText: '$prefix.Touch %',
                isDense: true,
              ),
              onTap: readOnlyTouch
                  ? null
                  : () => row.touch.selection = TextSelection(
                        baseOffset: 0,
                        extentOffset: row.touch.text.length,
                      ),
            ),
          ),
          const SizedBox(width: 6),
          _compactField(
            width: FieldSizes.pure,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: '$prefix.Pure Wt',
                isDense: true,
              ),
              child: Text(
                row.pureWt.toStringAsFixed(3),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _issuePanel() {
    return _panelShell(
      title: 'ISSUE',
      totalLabel: 'Issue total pure wt',
      totalPure: _issueTotalPure,
      rows: [
        for (var i = 0; i < _itemTypes.length; i++)
          _metalPanelRow(
            prefix: 'I',
            type: _itemTypes[i],
            row: _issueRows[_itemTypes[i]]!,
            weightFocus: _issueWeightFocus[i],
          ),
      ],
    );
  }

  Widget _receiptPanel() {
    final cashGold = _receiptCashGold;
    return _panelShell(
      title: 'RECEIPT',
      totalLabel: 'Receipt total pure wt',
      totalPure: _receiptTotalPure,
      rows: [
        for (var i = 0; i < _itemTypes.length; i++)
          _metalPanelRow(
            prefix: 'R',
            type: _itemTypes[i],
            row: _receiptRows[_itemTypes[i]]!,
            weightFocus: _receiptWeightFocus[i],
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              _compactField(
                width: FieldSizes.typeDropdown,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  ),
                  child: const Text(
                    'CASH',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _compactField(
                width: FieldSizes.cash,
                child: TextFormField(
                  controller: _receiptCashController,
                  focusNode: _receiptCashFocus,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: '₹ Amount',
                    isDense: true,
                  ),
                  onTap: () => _receiptCashController.selection =
                      TextSelection(
                    baseOffset: 0,
                    extentOffset: _receiptCashController.text.length,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _compactField(
                width: FieldSizes.weight,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'R.Weight',
                    isDense: true,
                  ),
                  child: Text(
                    cashGold.toStringAsFixed(3),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _compactField(
                width: FieldSizes.touch,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'R.Touch %',
                    isDense: true,
                  ),
                  child: const Text(
                    '100.00',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _compactField(
                width: FieldSizes.pure,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'R.Pure Wt',
                    isDense: true,
                  ),
                  child: Text(
                    cashGold.toStringAsFixed(3),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_goldRate <= 0 && _receiptCashAmount > 0)
          const Text(
            'Set G.P RATE on Master to convert cash to gold.',
            style: TextStyle(fontSize: 10.5, color: Colors.black54),
          )
        else if (_receiptCashAmount > 0)
          Text(
            'Cash ₹${_receiptCashAmount.toStringAsFixed(2)} → '
            '${cashGold.toStringAsFixed(3)} g @ ₹${_goldRate.toStringAsFixed(0)}/g',
            style: const TextStyle(fontSize: 10.5, color: Colors.black54),
          ),
      ],
    );
  }

  Widget _balanceBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const Text(
            'BALANCE',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Issue ${_issueTotalPure.toStringAsFixed(3)} g  −  '
              'Receipt ${_receiptTotalPure.toStringAsFixed(3)} g',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
          Text(
            '${_balancePure.toStringAsFixed(3)} g',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
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
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            "${_isPurchase ? 'PURCHASE' : 'SALES'} HISTORY (${_history.length})",
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              letterSpacing: 0.3,
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
                          fontWeight: FontWeight.w600, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '#${row['billNo']}  ·  '
                          '₹${row['totalValue'] ?? '-'}  ·  '
                          '${row['totalPureWt'] ?? '-'} g',
                      style: const TextStyle(
                          fontSize: 10.5, color: Colors.black54),
                      overflow: TextOverflow.ellipsis,
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
            secondaryWidth: 300,
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
}
