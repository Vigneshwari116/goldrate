import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../database/database_helper.dart';
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

  const TransactionScreen({super.key, required this.kind});

  @override
  State<TransactionScreen> createState() => _TransactionScreenState();
}

class _TransactionScreenState extends State<TransactionScreen> {
  static const _itemTypes = ['GWT', 'FWT', 'KWT', 'SWT'];
  static const _paymentModes = ['CASH', 'UPI', 'GOLD'];

  static final RegExp _numberRegex = RegExp(r'^\d+(\.\d+)?$');

  final _partyController = TextEditingController();
  final _weightController = TextEditingController();
  final _touchController = TextEditingController();
  final _paymentAmountController = TextEditingController();

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

  double get _balance => _isGoldSettlement
      ? _totalPureWt - _paymentAmount
      : _totalValue - _paymentAmount;

  String get _balanceUnit => _isGoldSettlement ? 'GRAMS' : 'RUPEES';

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
      setState(() => _partyOutstanding = null);
      return;
    }

    // Only look up an outstanding balance for an exact existing name —
    // partial typing shouldn't flash a stale/misleading figure.
    final isKnownParty =
    _partyNames.any((n) => n.toLowerCase() == lower);
    if (!isKnownParty) {
      setState(() => _partyOutstanding = null);
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

  /// Turns a party's outstanding {rupees, grams} totals into one line
  /// like "Ramesh owes you ₹20,000 · 5.20g" — sign flips the wording
  /// to "you owe" when the shop is the one holding the balance.
  String _outstandingSummary(Map<String, double> outstanding) {
    final rupees = outstanding['rupees'] ?? 0;
    final grams = outstanding['grams'] ?? 0;
    final name = _partyController.text.trim();
    final parts = <String>[];

    if (rupees.abs() > 0.01) {
      parts.add(rupees > 0
          ? "owes you ₹${rupees.toStringAsFixed(2)}"
          : "you owe ₹${rupees.abs().toStringAsFixed(2)}");
    }
    if (grams.abs() > 0.01) {
      parts.add(grams > 0
          ? "owes you ${grams.toStringAsFixed(2)}g"
          : "you owe ${grams.abs().toStringAsFixed(2)}g");
    }

    return "$name currently ${parts.join(' and ')}";
  }

  void _addItem() {
    final weight = double.tryParse(_weightController.text.trim());
    final touch = double.tryParse(_touchController.text.trim());

    if (weight == null || !_numberRegex.hasMatch(_weightController.text.trim())) {
      _showMessage("Enter a valid weight");
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
      _weightController.clear();
      _touchController.clear();
    });
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _clearForm() {
    _partyController.clear();
    _weightController.clear();
    _touchController.clear();
    _paymentAmountController.clear();
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
      'balance': _balance.toStringAsFixed(_isGoldSettlement ? 3 : 2),
      'balanceUnit': _balanceUnit,
      'date': date,
      'time': time,
    };

    await DatabaseHelper.instance.insertTransaction(record);
    await _postToLedger(date, time);

    if (!mounted) return;

    setState(() => _saving = false);

    final billNoSaved = _nextBillNo;
    final partyName = _partyController.text.trim();
    _clearForm();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Bill #$billNoSaved saved and posted to $partyName's ledger")),
    );

    _load();
  }

  /// Posts this bill's balance to the matching party's ledger table —
  /// Purchase bills post to Suppliers, Sales bills post to Customers.
  /// A positive balance (party still owes the shop) goes in the DR
  /// column; a negative balance (shop owes the party) goes in CR —
  /// mirroring how the existing Customer/Supplier Master screens
  /// already use those two fields.
  Future<void> _postToLedger(String date, String time) async {
    final balance = _balance;
    final narration =
        "Bill #$_nextBillNo (${_isPurchase ? 'Purchase' : 'Sale'}) — "
        "Wt ${_totalWt.toStringAsFixed(2)}, Pure ${_totalPureWt.toStringAsFixed(3)}, "
        "Value ₹${_totalValue.toStringAsFixed(2)}, "
        "$_selectedPaymentMode ${_paymentAmount.toStringAsFixed(2)}";

    final baseEntry = {
      'name': _partyController.text.trim(),
      'mobile': '',
      'city': '',
      'cr': balance < 0 ? balance.abs().toStringAsFixed(2) : '0',
      'dr': balance > 0 ? balance.toStringAsFixed(2) : '0',
      'narration': narration,
      'balanceUnit': _balanceUnit,
      'billRef': 'Bill #$_nextBillNo',
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
            onPressed: () => _shareBill(row),
            child: const Text("SHARE"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CLOSE"),
          ),
        ],
      ),
    );
  }
  Future<Uint8List> _buildBillPdf(Map<String, dynamic> row) async {
    final items = (jsonDecode(row['items'] as String) as List)
        .map((e) => _TransactionItem.fromJson(e as Map<String, dynamic>))
        .toList();

    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Text(
                'JEWELLERY MANAGEMENT',
                style:
                pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Center(
              child: pw.Text(
                row['transactionType'] == 'PURCHASE'
                    ? 'PURCHASE BILL'
                    : 'SALES BILL',
                style: pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Bill No: ${row['billNo']}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text('${row['date'] ?? ''}  ${row['time'] ?? ''}'),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Text('Party: ${row['partyName'] ?? '-'}'),
            pw.SizedBox(height: 12),
            pw.Table.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration:
              const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.symmetric(
                  horizontal: 6, vertical: 4),
              headers: ['Type', 'Wt', 'Touch %', 'Pure Wt', 'Rate', 'Value (Rs.)'],
              data: items
                  .map((item) => [
                item.type,
                item.weight.toStringAsFixed(2),
                item.touch.toStringAsFixed(2),
                item.pureWt.toStringAsFixed(3),
                item.rate.toStringAsFixed(0),
                item.value.toStringAsFixed(2),
              ])
                  .toList(),
            ),
            pw.SizedBox(height: 10),
            pw.Divider(),
            _pdfRow('Total Wt', row['totalWt']),
            _pdfRow('Total Pure Wt', row['totalPureWt']),
            _pdfRow('Total Value (Rs.)', row['totalValue']),
            pw.SizedBox(height: 8),
            _pdfRow('Payment (${row['paymentMode'] ?? '-'})',
                row['paymentAmount']),
            _pdfRow('Balance (${row['balanceUnit'] ?? ''})', row['balance'],
                bold: true),
            pw.SizedBox(height: 16),
            pw.Center(
              child: pw.Text(
                'Thank you',
                style:
                pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
              ),
            ),
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

  Future<void> _shareBill(Map<String, dynamic> row) async {
    final bytes = await _buildBillPdf(row);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/bill_${row['billNo']}.pdf');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: "Bill #${row['billNo']} - ${row['partyName'] ?? ''}",
      text: '${_isPurchase ? 'Purchase' : 'Sales'} bill',
    );
  }

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
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
          TextFormField(
            controller: _partyController,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              label: Text(
                  _isCustomerParty ? "Customer Name" : "Supplier Name"),
              helperText: _isCustomerParty
                  ? "Existing customers show as you type"
                  : "Existing suppliers show as you type",
              helperStyle: const TextStyle(fontSize: 11),
            ),
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
                  title: Text(name,
                      style: const TextStyle(fontSize: 13)),
                  onTap: () => _selectParty(name),
                ))
                    .toList(),
              ),
            ),
          if (_partyOutstanding != null &&
              ((_partyOutstanding!['rupees'] ?? 0).abs() > 0.01 ||
                  (_partyOutstanding!['grams'] ?? 0).abs() > 0.01))
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.headerBand,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                _outstandingSummary(_partyOutstanding!),
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.navy),
              ),
            ),
          const SizedBox(height: 14),
          const Text(
            "ADD WEIGHT LINE",
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.mutedBlue),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  value: _selectedItemType,
                  decoration: const InputDecoration(label: Text("Type")),
                  items: _itemTypes
                      .map((t) =>
                      DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _selectedItemType = v!),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _weightController,
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 14),
                  decoration:
                  const InputDecoration(label: Text("Weight")),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _touchController,
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 14),
                  decoration:
                  const InputDecoration(label: Text("Touch %")),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.add_circle,
                    color: AppColors.navy, size: 28),
                onPressed: _addItem,
                tooltip: 'Add line',
              ),
            ],
          ),
          if (_items.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...List.generate(_items.length, (index) {
              final item = _items[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.headerBand,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        "${item.type}  •  Wt ${item.weight}  •  "
                            "Touch ${item.touch}%  •  Pure "
                            "${item.pureWt.toStringAsFixed(3)}  •  "
                            "₹${item.value.toStringAsFixed(2)}",
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close,
                          size: 16, color: Colors.redAccent),
                      onPressed: () => _removeItem(index),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              );
            }),
          ],
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
          _totalRow("BALANCE ($_balanceUnit)", _balance,
              highlight: true, decimals: _isGoldSettlement ? 3 : 2),
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
                          onPressed: () => _shareBill(row),
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: SplitLayout(
          primaryWidth: 420,
          primary: _buildFormCard(),
          secondary: _buildHistorySection(),
        ),
      ),
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




