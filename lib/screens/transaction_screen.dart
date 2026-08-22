import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../database/database_helper.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../utils/number_format.dart';
import '../services/estimate_bill_pdf.dart';
import '../widgets/app_shell.dart';
import 'customer_master_screen.dart';
import 'supplier_master_screen.dart';

enum TransactionKind { purchase, sales }

const Map<String, String> kItemTypeToRateName = {
  'GWT': 'G.P RATE',
  'FWT': 'F.T RATE',
  'KWT': 'KACHA RATE',
  'SWT': 'S RATE',
};

class _TransactionItem {
  final String type;
  final String token;
  final double weight;
  final double touch;
  final double rate;

  _TransactionItem({
    required this.type,
    this.token = '',
    required this.weight,
    required this.touch,
    required this.rate,
  });

  double get pureWt => weight * touch / 100;

  double get value => pureWt * rate;

  Map<String, dynamic> toJson() => {
    'type': type,
    'token': token,
    'weight': weight,
    'touch': touch,
    'pureWt': double.parse(pureWt.toStringAsFixed(3)),
    'rate': rate,
    'value': value,
  };

  factory _TransactionItem.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse('$v') ?? 0;
    }
    return _TransactionItem(
      type: (json['type'] ?? 'GWT').toString(),
      token: (json['token'] ?? '').toString(),
      weight: n(json['weight']),
      touch: n(json['touch']),
      rate: n(json['rate']),
    );
  }
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
  final _tokenController = TextEditingController();
  final _weightController = TextEditingController();
  final _touchController = TextEditingController();
  final _paymentAmountController = TextEditingController();

  final _partyFocus = FocusNode();
  final _tokenFocus = FocusNode();
  final _weightFocus = FocusNode();
  final _touchFocus = FocusNode();
  final _paymentFocus = FocusNode();

  String _selectedItemType = _itemTypes.first;
  String _selectedPaymentMode = _paymentModes.first;

  final List<_TransactionItem> _items = [];

  int _nextBillNo = 1;
  int? _editingId;
  int? _editingBillNo;
  String? _editingDate;
  String? _editingTime;
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

  int get _billNoOnForm => _editingBillNo ?? _nextBillNo;

  bool get _isEditing => _editingId != null;

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
    _tokenController.dispose();
    _weightController.dispose();
    _touchController.dispose();
    _paymentAmountController.dispose();
    _partyFocus.dispose();
    _tokenFocus.dispose();
    _weightFocus.dispose();
    _touchFocus.dispose();
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

  bool _isKnownParty(String name) {
    final lower = name.trim().toLowerCase();
    if (lower.isEmpty) return false;
    return _partyNames.any((n) => n.toLowerCase() == lower);
  }

  /// New walk-in names go to Customer/Supplier Master first (mobile,
  /// city, opening CR/DR), then return here with the saved name.
  Future<bool> _ensureKnownParty() async {
    final name = _partyController.text.trim();
    if (name.isEmpty) {
      _showMessage("Enter a name");
      return false;
    }
    if (_isKnownParty(name)) return true;

    final saved = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => _isPurchase
            ? SupplierMasterScreen(initialName: name, popAfterSave: true)
            : CustomerMasterScreen(initialName: name, popAfterSave: true),
      ),
    );
    if (!mounted) return false;
    await _load();
    if (saved == null || saved.trim().isEmpty) return false;
    _selectParty(saved.trim());
    return true;
  }

  Future<void> _onPartySubmitted() async {
    final ok = await _ensureKnownParty();
    if (ok && mounted) _tokenFocus.requestFocus();
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
        token: _tokenController.text.trim(),
        weight: weight,
        touch: touch,
        rate: rate,
      ));
      _tokenController.clear();
      _weightController.clear();
      _touchController.clear();
    });
    _tokenFocus.requestFocus();
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  void _editLine(int index) {
    final item = _items[index];
    setState(() {
      _selectedItemType = _itemTypes.contains(item.type) ? item.type : _itemTypes.first;
      _tokenController.text = item.token;
      _weightController.text = formatWeight(item.weight);
      _touchController.text = formatWeight(item.touch);
      _items.removeAt(index);
    });
    _weightFocus.requestFocus();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _clearForm({bool keepBillCounter = false}) {
    _partyController.clear();
    _tokenController.clear();
    _weightController.clear();
    _touchController.clear();
    _paymentAmountController.clear();
    setState(() {
      _items.clear();
      _selectedItemType = _itemTypes.first;
      _selectedPaymentMode = _paymentModes.first;
      _partySuggestions = [];
      _partyOutstanding = null;
      if (!keepBillCounter) {
        _editingId = null;
        _editingBillNo = null;
        _editingDate = null;
        _editingTime = null;
      }
    });
  }

  Future<void> _saveTransaction() async {
    if (!await _ensureKnownParty()) return;
    if (_items.isEmpty) {
      _showMessage("Add at least one weight line");
      return;
    }

    setState(() => _saving = true);

    final date = _editingDate ??
        DateFormat("dd-MM-yyyy").format(DateTime.now());
    final time = _isEditing
        ? (_editingTime ?? DateFormat("hh:mm:ss a").format(DateTime.now()))
        : DateFormat("hh:mm:ss a").format(DateTime.now());
    final billNo = _billNoOnForm;

    final record = {
      'transactionType': _transactionType,
      'billNo': billNo,
      'partyName': _partyController.text.trim(),
      'items': jsonEncode(_items.map((i) => i.toJson()).toList()),
      'totalWt': formatWeight(_totalWt),
      'totalPureWt': formatWeight(_totalPureWt),
      'totalValue': _totalValue.toStringAsFixed(2),
      'paymentMode': _selectedPaymentMode,
      'paymentAmount': _paymentAmount.toStringAsFixed(2),
      'balance': _balance.toStringAsFixed(_isGoldSettlement ? 3 : 2),
      'balanceUnit': _balanceUnit,
      'date': date,
      'time': time,
    };

    if (_isEditing) {
      await DatabaseHelper.instance.updateTransaction(_editingId!, record);
      await DatabaseHelper.instance.deleteLedgerForBill(
        billRef: 'Bill #$billNo',
        isCustomer: _isCustomerParty,
      );
    } else {
      await DatabaseHelper.instance.insertTransaction(record);
    }
    await _postToLedger(date, time, billNo);

    if (!mounted) return;

    setState(() => _saving = false);

    final billNoSaved = billNo;
    final partyName = _partyController.text.trim();
    final savedRecord = Map<String, dynamic>.from(record);
    final wasEdit = _isEditing;
    _clearForm();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          wasEdit
              ? "Bill #$billNoSaved updated — weights recalculated"
              : "Bill #$billNoSaved saved and posted to $partyName's ledger",
        ),
      ),
    );

    await _shareBill(savedRecord);

    _load();
  }

  /// Posts this bill's balance to the matching party's ledger table —
  /// Purchase bills post to Suppliers, Sales bills post to Customers.
  /// A positive balance (party still owes the shop) goes in the DR
  /// column; a negative balance (shop owes the party) goes in CR —
  /// mirroring how the existing Customer/Supplier Master screens
  /// already use those two fields.
  Future<void> _postToLedger(String date, String time, int billNo) async {
    final balance = _balance;
    final narration =
        "Bill #$billNo (${_isPurchase ? 'Purchase' : 'Sale'}) — "
        "Wt ${formatWeight(_totalWt)}, Pure ${formatWeight(_totalPureWt)}, "
        "Value ₹${_totalValue.toStringAsFixed(2)}, "
        "$_selectedPaymentMode ${_paymentAmount.toStringAsFixed(2)}";

    final baseEntry = {
      'name': _partyController.text.trim(),
      'mobile': '',
      'city': '',
      'cr': balance < 0 ? formatAmount(balance.abs()) : '0.00',
      'dr': balance > 0 ? formatAmount(balance) : '0.00',
      'narration': narration,
      'balanceUnit': _balanceUnit,
      'billRef': 'Bill #$billNo',
      'date': date,
      'time': time,
    };

    if (_isPurchase) {
      await DatabaseHelper.instance.insertSupplier({
        ...baseEntry,
        'gross': formatWeight(_totalWt),
        'net': formatAmount(_totalValue),
      });
    } else {
      await DatabaseHelper.instance.insertCustomer({
        ...baseEntry,
        'drGross': formatWeight(_totalWt),
        'drNet': formatAmount(_totalValue),
      });
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> row) async {
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
      final billNo = row['billNo'];
      await DatabaseHelper.instance.deleteLedgerForBill(
        billRef: 'Bill #$billNo',
        isCustomer: _isCustomerParty,
      );
      await DatabaseHelper.instance.deleteTransaction(row['id'] as int);
      if (_editingId == row['id']) _clearForm();
      _load();
    }
  }

  void _beginEdit(Map<String, dynamic> row) {
    final items = (jsonDecode(row['items'] as String) as List)
        .map((e) => _TransactionItem.fromJson(e as Map<String, dynamic>))
        .toList();
    _partyController.text = (row['partyName'] ?? '').toString();
    _paymentAmountController.text = (row['paymentAmount'] ?? '').toString();
    final mode = (row['paymentMode'] ?? 'CASH').toString();
    setState(() {
      _editingId = row['id'] as int;
      final rawNo = row['billNo'];
      _editingBillNo =
          rawNo is int ? rawNo : int.tryParse('$rawNo');
      _editingDate = (row['date'] ?? '').toString();
      _editingTime = (row['time'] ?? '').toString();
      _items
        ..clear()
        ..addAll(items);
      _selectedPaymentMode =
          _paymentModes.contains(mode) ? mode : _paymentModes.first;
      _partySuggestions = [];
    });
    _onPartyTextChanged();
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
                    "${item.type} — Wt ${formatWeight(item.weight)}  Touch ${formatWeight(item.touch)}%  "
                        "Pure ${formatWeight(item.pureWt)}  "
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
            onPressed: () {
              Navigator.pop(context);
              _beginEdit(row);
            },
            child: const Text("EDIT"),
          ),
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
    final phone = await DatabaseHelper.instance.getPartyMobile(
      (row['partyName'] ?? '').toString(),
      isCustomer: (row['transactionType'] ?? '') != 'PURCHASE',
    );
    final balance = (row['balance'] ?? '').toString();
    final unit = (row['balanceUnit'] ?? '').toString();
    final closing = (double.tryParse(balance) ?? 0).abs() < 0.001
        ? 'NIL'
        : '$balance $unit';
    return buildEstimateBillPdf(
      billNo: '${row['billNo']}',
      date: (row['date'] ?? '').toString(),
      time: (row['time'] ?? '').toString(),
      name: (row['partyName'] ?? '').toString(),
      phone: phone,
      lines: [
        for (var i = 0; i < items.length; i++)
          EstimateLine(
            sno: i + 1,
            token: items[i].token,
            weight: items[i].weight,
            touch: items[i].touch,
            pureWt: items[i].pureWt,
          ),
      ],
      closingBalance: closing,
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
      "Bill No,Party,Type,Weight,Touch,Pure Wt,Rate,Value,"
          "Total Wt,Total Pure Wt,Total Value,Payment Mode,"
          "Payment Amount,Balance,Balance Unit,Date,Time",
    );

    for (final row in _history) {
      List<dynamic> items;
      try {
        items = jsonDecode((row['items'] ?? '[]').toString()) as List<dynamic>;
      } catch (_) {
        items = [];
      }
      if (items.isEmpty) {
        items = [
          {'type': '', 'weight': 0, 'touch': 0, 'pureWt': 0, 'rate': 0, 'value': 0}
        ];
      }
      for (final raw in items) {
        final item = raw is Map ? raw : <String, dynamic>{};
        final line = [
          row['billNo'],
          row['partyName'],
          item['type'],
          formatWeight(item['weight']),
          formatWeight(item['touch']),
          formatWeight(item['pureWt']),
          item['rate'],
          formatAmount(item['value']),
          formatWeight(row['totalWt']),
          formatWeight(row['totalPureWt']),
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
      width: double.infinity,
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
                "$_billNoOnForm${_isEditing ? '  (EDIT)' : ''}",
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
            focusNode: _partyFocus,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _onPartySubmitted(),
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              label: Text(
                  _isCustomerParty ? "Customer Name" : "Supplier Name"),
              helperText: _isCustomerParty
                  ? "Pick an existing customer, or Enter to add a new one"
                  : "Pick an existing supplier, or Enter to add a new one",
              helperStyle: const TextStyle(fontSize: 11),
            ),
          ),
          if (_partySuggestions.isNotEmpty)
            Material(
              color: AppColors.cardWhite,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: const BorderSide(color: AppColors.border),
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
                flex: 2,
                child: DropdownButtonFormField<String>(
                  value: _selectedItemType,
                  isExpanded: true,
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
                flex: 2,
                child: TextFormField(
                  controller: _tokenController,
                  focusNode: _tokenFocus,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _weightFocus.requestFocus(),
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    label: Text("Token"),
                    hintText: "optional",
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _weightController,
                  focusNode: _weightFocus,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _touchFocus.requestFocus(),
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 14),
                  decoration:
                  const InputDecoration(label: Text("Weight"), hintText: "0.000"),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _touchController,
                  focusNode: _touchFocus,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _addItem(),
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 14),
                  decoration:
                  const InputDecoration(label: Text("Touch %"), hintText: "0.000"),
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
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                showCheckboxColumn: false,
                headingRowColor:
                    WidgetStateProperty.all(AppColors.tableHeader),
                headingTextStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ),
                dataTextStyle: const TextStyle(fontSize: 12.5),
                columns: const [
                  DataColumn(label: Text('SNo')),
                  DataColumn(label: Text('TOKEN')),
                  DataColumn(label: Text('WT'), numeric: true),
                  DataColumn(label: Text('TOUCH'), numeric: true),
                  DataColumn(label: Text('PURE'), numeric: true),
                  DataColumn(label: Text('')),
                ],
                rows: List.generate(_items.length, (index) {
                  final item = _items[index];
                  return DataRow(
                    onSelectChanged: (_) => _editLine(index),
                    cells: [
                    DataCell(Text('${index + 1}')),
                    DataCell(Text(item.token.isEmpty ? '-' : item.token)),
                    DataCell(Text(formatWeight(item.weight))),
                    DataCell(Text(formatWeight(item.touch))),
                    DataCell(Text(formatWeight(item.pureWt))),
                    DataCell(
                      IconButton(
                        icon: const Icon(Icons.close,
                            size: 16, color: Colors.redAccent),
                        onPressed: () => _removeItem(index),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ),
                  ]);
                }),
              ),
            ),
          ],
          if (_items.isNotEmpty) ...[
            const Divider(height: 24, color: AppColors.border),
            _totalRow("TOTAL WT", _totalWt, decimals: 3),
            _totalRow("PURE GOLD", _totalPureWt, decimals: 3),
            _totalRow("TOTAL VALUE (₹)", _totalValue),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                "Tap a line to change weight or touch — pure recalculates.",
                style: TextStyle(fontSize: 11.5, color: Colors.black54),
              ),
            ),
          ],
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
                  isExpanded: true,
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
                  textInputAction: TextInputAction.done,
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
          if (_isEditing) ...[
            SizedBox(
              width: double.infinity,
              height: 40,
              child: OutlinedButton(
                onPressed: _saving
                    ? null
                    : () {
                        _clearForm();
                        _load();
                      },
                child: const Text('CANCEL EDIT'),
              ),
            ),
            const SizedBox(height: 8),
          ],
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
                  : Text(_isEditing
                      ? (_isPurchase ? "UPDATE PURCHASE" : "UPDATE SALE")
                      : (_isPurchase ? "SAVE PURCHASE" : "SAVE SALE")),
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
          Material(
            color: AppColors.cardWhite,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: List.generate(_history.length, (index) {
                final row = _history[index];
                final isLast = index == _history.length - 1;

                return Column(
                  children: [
                    ListTile(
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
                          onPressed: () => _confirmDelete(row),
                        ),
                      ],
                    ),
                    ),
                    if (!isLast) const Divider(height: 1),
                  ],
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
        leading: shellMenuButton(context),
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
          : Padding(
        padding: const EdgeInsets.all(12),
        child: SplitLayout(
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




