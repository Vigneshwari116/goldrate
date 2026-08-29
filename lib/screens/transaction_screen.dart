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
import '../models/party_suggestion.dart';
import '../widgets/party_search_field.dart';
import '../util/party_save_prompt.dart';
import '../util/party_name_match.dart';
import '../util/field_advance.dart';
import '../util/focus_chain.dart';
import '../util/screen_activation.dart';
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

class _PanelLine {
  final String type;
  final double weight;
  final double touch;
  final double? cashAmount;

  const _PanelLine({
    required this.type,
    this.weight = 0,
    this.touch = 0,
    this.cashAmount,
  });

  factory _PanelLine.cash(double amount) => _PanelLine(
        type: 'CASH',
        cashAmount: amount,
      );

  factory _PanelLine.metal({
    required String type,
    required double weight,
    required double touch,
  }) =>
      _PanelLine(type: type, weight: weight, touch: touch);

  bool get isCash => type == 'CASH';

  double get metalPureWt => isCash ? 0 : weight * touch / 100;

  double pureWtAtRate(double goldRate) =>
      isCash ? GoldLedger.cashToGold(cashAmount ?? 0, goldRate) : metalPureWt;
}

class TransactionScreen extends StatefulWidget {
  final TransactionKind kind;
  final bool embedded;
  final bool isActive;

  const TransactionScreen({
    super.key,
    required this.kind,
    this.embedded = false,
    this.isActive = true,
  });

  @override
  State<TransactionScreen> createState() => _TransactionScreenState();
}

class _TransactionScreenState extends State<TransactionScreen>
    with FocusAdvanceMixin, ScreenActivationMixin<TransactionScreen> {
  static const _itemTypes = ['GWT', 'FWT', 'KWT', 'SWT'];
  static const _paymentItemTypes = ['GWT', 'FWT', 'KWT', 'SWT', 'CASH'];
  static final RegExp _numberRegex = RegExp(r'^\d+(\.\d+)?$');

  final _partyController = TextEditingController();
  FocusNode? _partyFocus;

  final List<_TransactionItem> _billLines = [];
  final List<_PanelLine> _paymentLines = [];

  String _billEntryType = _itemTypes.first;
  String _paymentEntryType = _paymentItemTypes.first;
  final _billEntryWeight = TextEditingController(text: '0.000');
  final _billEntryTouch = TextEditingController(text: '0.00');
  final _paymentEntryWeight = TextEditingController(text: '0.000');
  final _paymentEntryTouch = TextEditingController(text: '0.00');
  final _paymentEntryAmount = TextEditingController(text: '0.00');

  final _billEntryWeightFocus = FocusNode();
  final _billEntryTouchFocus = FocusNode();
  final _paymentEntryWeightFocus = FocusNode();
  final _paymentEntryTouchFocus = FocusNode();
  final _paymentEntryAmountFocus = FocusNode();
  final _saveFocus = FocusNode();

  int _nextBillNo = 1;
  bool _loading = true;
  bool _saving = false;
  bool _sharingPdf = false;

  List<Map<String, dynamic>> _history = [];
  Map<String, double> _rates = {};
  List<PartySuggestion> _partySuggestions = [];
  Map<String, double>? _partyOutstanding;
  Timer? _partyRefreshTimer;

  /// Purchase looks up Suppliers (stock coming in from them); Sales
  /// looks up Customers (stock going out to them).
  bool get _isCustomerParty => !_isPurchase;

  bool get _isPurchase => widget.kind == TransactionKind.purchase;

  static final _rupeeFmt = NumberFormat('#,##0.00', 'en_IN');

  String _rupee(double amount) => _rupeeFmt.format(amount);

  String get _transactionType => _isPurchase ? 'PURCHASE' : 'SALES';

  String get _title => _isPurchase ? 'PURCHASE' : 'SALES';

  bool get _showPanels =>
      _partyController.text.trim().isNotEmpty || _hasBillOrPaymentData;

  bool get _hasBillOrPaymentData =>
      _billLines.isNotEmpty || _paymentLines.isNotEmpty;

  List<_TransactionItem> get _billItems => _billLines;

  double get _totalWt =>
      _billItems.fold(0, (sum, item) => sum + item.weight);

  double get _totalPureWt =>
      _billItems.fold(0, (sum, item) => sum + item.pureWt);

  double get _totalValue =>
      _billItems.fold(0, (sum, item) => sum + item.value);

  double get _billTotalPure =>
      _billLines.fold(0, (sum, item) => sum + item.pureWt);

  double get _paymentMetalPure => _paymentLines
      .where((line) => !line.isCash)
      .fold(0, (sum, line) => sum + line.metalPureWt);

  double get _paymentTotalCash => _paymentLines
      .where((line) => line.isCash)
      .fold(0, (sum, line) => sum + (line.cashAmount ?? 0));

  double get _paymentCashGold => _paymentLines
      .where((line) => line.isCash)
      .fold(0, (sum, line) => sum + line.pureWtAtRate(_goldRate));

  double get _paymentTotalPure => _paymentMetalPure + _paymentCashGold;

  double get _goldRate => GoldLedger.goldRate(_rates);

  double get _balancePure => _billTotalPure - _paymentTotalPure;

  bool get _paymentIsCashOnly =>
      _paymentLines.isNotEmpty && _paymentLines.every((line) => line.isCash);

  double get _paymentAmount => _paymentIsCashOnly
      ? _paymentTotalCash
      : _paymentTotalPure;

  SettlementResult get _settlement {
    return settleLedger(
      oldGrams: _partyOutstanding?['grams'] ?? 0,
      oldRupees: _partyOutstanding?['rupees'] ?? 0,
      billGrams: _totalPureWt,
      billRupees: _totalValue,
      paymentMode: _paymentIsCashOnly ? 'CASH' : 'GOLD',
      paymentAmount: _paymentAmount,
      ratePerGram: _goldRate,
      billSign: _isPurchase ? -1 : 1,
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
    _partyController
      ..addListener(_onPartyControllerChanged)
      ..addListener(() => _onPartyTextChanged());
  }

  void _onPartyControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  bool get screenIsActive => widget.isActive;

  @override
  bool wasScreenActive(TransactionScreen oldWidget) => oldWidget.isActive;

  @override
  void onScreenActivated() {
    _load();
  }

  void _bindPartyFocus(FocusNode node) {
    if (_partyFocus == node) return;
    _partyFocus?.removeListener(_onPartyFocus);
    _partyFocus = node;
    node.addListener(_onPartyFocus);
  }

  void _onPartyFocus() {
    if (_partyFocus?.hasFocus == true) {
      _refreshParties();
    }
  }

  double _entryPure(TextEditingController weight, TextEditingController touch) {
    final w = double.tryParse(weight.text.trim()) ?? 0;
    final t = double.tryParse(touch.text.trim()) ?? 0;
    return w * t / 100;
  }

  void _resetBillEntry({bool resetType = true}) {
    if (resetType) _billEntryType = _itemTypes.first;
    _billEntryWeight.text = '0.000';
    _billEntryTouch.text = '0.00';
  }

  void _resetPaymentEntry({bool resetType = true}) {
    if (resetType) _paymentEntryType = _paymentItemTypes.first;
    _paymentEntryWeight.text = '0.000';
    _paymentEntryTouch.text = '0.00';
    _paymentEntryAmount.text = '0.00';
  }

  _TransactionItem? _validatedBillEntry() {
    final weight = double.tryParse(_billEntryWeight.text.trim());
    final touch = double.tryParse(_billEntryTouch.text.trim());
    if (weight == null ||
        !_numberRegex.hasMatch(_billEntryWeight.text.trim()) ||
        weight <= 0) {
      return null;
    }
    if (touch == null || !_numberRegex.hasMatch(_billEntryTouch.text.trim())) {
      return null;
    }
    final rateName = kItemTypeToRateName[_billEntryType];
    final rate = _rates[rateName] ?? 0;
    return _TransactionItem(
      type: _billEntryType,
      weight: weight,
      touch: touch,
      rate: rate,
    );
  }

  _PanelLine? _validatedPaymentEntry() {
    if (_paymentEntryType == 'CASH') {
      final amount = double.tryParse(_paymentEntryAmount.text.trim());
      if (amount == null ||
          !_numberRegex.hasMatch(_paymentEntryAmount.text.trim()) ||
          amount <= 0) {
        return null;
      }
      return _PanelLine.cash(amount);
    }
    final weight = double.tryParse(_paymentEntryWeight.text.trim());
    final touch = double.tryParse(_paymentEntryTouch.text.trim());
    if (weight == null ||
        !_numberRegex.hasMatch(_paymentEntryWeight.text.trim()) ||
        weight <= 0) {
      return null;
    }
    if (touch == null ||
        !_numberRegex.hasMatch(_paymentEntryTouch.text.trim())) {
      return null;
    }
    return _PanelLine.metal(
      type: _paymentEntryType,
      weight: weight,
      touch: touch,
    );
  }

  void _commitBillEntry() {
    final item = _validatedBillEntry();
    if (item == null) {
      _showMessage('Enter weight and touch before continuing');
      return;
    }
    final rateName = kItemTypeToRateName[item.type];
    if ((_rates[rateName] ?? 0) <= 0) {
      _showMessage(
          "$rateName isn't set yet — update it on the Master screen first");
      return;
    }
    setState(() {
      _billLines.add(item);
      _resetBillEntry(resetType: false);
    });
    FocusChain.focusNextFrame(
      _billEntryWeightFocus,
      controller: _billEntryWeight,
    );
  }

  void _commitPaymentEntry() {
    final line = _validatedPaymentEntry();
    if (line == null) {
      _showMessage(_paymentEntryType == 'CASH'
          ? 'Enter a cash amount before continuing'
          : 'Enter weight and touch before continuing');
      return;
    }
    if (line.isCash && _goldRate <= 0) {
      _showMessage("Set G.P RATE on Master so cash can convert to gold");
      return;
    }
    setState(() {
      _paymentLines.add(line);
      _resetPaymentEntry(resetType: false);
    });
    if (line.isCash) {
      FocusChain.focusNextFrame(
        _paymentEntryAmountFocus,
        controller: _paymentEntryAmount,
      );
    } else {
      FocusChain.focusNextFrame(
        _paymentEntryWeightFocus,
        controller: _paymentEntryWeight,
      );
    }
  }

  void _onPaymentTypeChanged(String type) {
    setState(() => _paymentEntryType = type);
    if (type == 'CASH') {
      FocusChain.focusNextFrame(
        _paymentEntryAmountFocus,
        controller: _paymentEntryAmount,
      );
    } else {
      FocusChain.focusNextFrame(
        _paymentEntryWeightFocus,
        controller: _paymentEntryWeight,
      );
    }
  }

  @override
  void dispose() {
    _partyRefreshTimer?.cancel();
    _partyFocus?.removeListener(_onPartyFocus);
    _partyController.dispose();
    _billEntryWeight.dispose();
    _billEntryTouch.dispose();
    _paymentEntryWeight.dispose();
    _paymentEntryTouch.dispose();
    _paymentEntryAmount.dispose();
    _billEntryWeightFocus.dispose();
    _billEntryTouchFocus.dispose();
    _paymentEntryWeightFocus.dispose();
    _paymentEntryTouchFocus.dispose();
    _paymentEntryAmountFocus.dispose();
    _saveFocus.dispose();
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
      _partySuggestions = PartySuggestion.fromLedgerRows(
        partyRows,
        roleLabel: _isCustomerParty ? 'Customer' : 'Supplier',
      );
      _loading = false;
    });
  }

  Future<void> _refreshParties() async {
    final partyRows = _isCustomerParty
        ? await DatabaseHelper.instance.getCustomers()
        : await DatabaseHelper.instance.getSuppliers();
    if (!mounted) return;
    setState(() {
      _partySuggestions = PartySuggestion.fromLedgerRows(
        partyRows,
        roleLabel: _isCustomerParty ? 'Customer' : 'Supplier',
      );
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
      _billEntryWeightFocus,
      controller: _billEntryWeight,
    );
  }

  bool _partyHasMatches(String name) =>
      PartySearchField.filterParties(_partySuggestions, name).isNotEmpty;

  bool _partyExactMatch(String name) =>
      _partySuggestions.any((party) => party.isExactNameMatch(name));

  Future<void> _advanceFromParty(String value) async {
    final name = value.trim();
    if (name.isEmpty) return;
    if (_partyHasMatches(name) && !_partyExactMatch(name)) return;
    if (!await _ensurePartySaved()) return;
    FocusChain.focusNextFrame(
      _billEntryWeightFocus,
      controller: _billEntryWeight,
    );
  }

  void _onPartyNameChanged(String value) {
    if (value.trim().isNotEmpty) {
      _partyRefreshTimer?.cancel();
      _partyRefreshTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) _refreshParties();
      });
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty || _partyFocus == null) return;

    advanceWhenIdle(
      value: trimmed,
      from: _partyFocus!,
      when: (v) {
        final t = v.trim();
        if (t.length < 2) return false;
        return !_partyHasMatches(t) || _partyExactMatch(t);
      },
      action: () => _advanceFromParty(trimmed),
    );
  }

  Future<bool> _ensurePartySaved() async {
    final name = _partyController.text.trim();
    if (name.isEmpty) return false;
    if (_partyExactMatch(name)) return true;
    if (_partyHasMatches(name)) return false;

    final save = await confirmSaveNewParty(
      context,
      isCustomer: _isCustomerParty,
      name: name,
    );
    if (!save) return false;

    await DatabaseHelper.instance.ensureParty(
      name,
      isCustomer: _isCustomerParty,
    );
    await _refreshParties();
    _onPartyTextChanged(name);
    return true;
  }

  void _clearPanels() {
    _billLines.clear();
    _paymentLines.clear();
    _resetBillEntry();
    _resetPaymentEntry();
  }

  void _clearForm() {
    _partyController.clear();
    _clearPanels();
    setState(() => _partyOutstanding = null);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  bool _validateBillRates() {
    for (final item in _billItems) {
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
    if (!await _ensurePartySaved()) return;
    if (_billItems.isEmpty) {
      _showMessage(_isPurchase
          ? "Enter at least one receipt weight (gold received)"
          : "Enter at least one issue weight");
      return;
    }
    if (!_validateBillRates()) return;

    setState(() => _saving = true);

    final date = DateFormat("dd-MM-yyyy").format(DateTime.now());
    final time = DateFormat("hh:mm a").format(DateTime.now());

    final items = _billItems;
    final s = _settlement;
    final paymentMode = _paymentIsCashOnly ? 'CASH' : 'GOLD';
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
          _paymentIsCashOnly ? 2 : 3),
      'balance': s.newGrams.toStringAsFixed(3),
      'balanceUnit': 'GRAMS',
      'date': date,
      'time': time,
      'oldGrams': s.oldGrams.toStringAsFixed(3),
      'oldRupees': s.oldRupees.toStringAsFixed(2),
      'newGrams': s.newGrams.toStringAsFixed(3),
      'newRupees': s.newRupees.toStringAsFixed(2),
      'cashToGold': (_paymentCashGold > 0
              ? _paymentCashGold
              : s.cashToGoldGrams)
          .toStringAsFixed(3),
      'goldRateUsed': s.ratePerGram.toStringAsFixed(2),
    };

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
              onFocusNodeReady: _bindPartyFocus,
              parties: _partySuggestions,
              helperText: 'Search saved name, mobile, or city',
              onFocus: _refreshParties,
              onSelected: _selectParty,
              onFieldSubmitted: () => _advanceFromParty(_partyController.text),
              onChanged: _onPartyNameChanged,
            ),
          ),
          if (_showPanels) ...[
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 720;
                if (stacked) {
                  return Column(
                    children: [
                      _leftPanel(),
                      const SizedBox(height: 10),
                      _rightPanel(),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _leftPanel()),
                    const SizedBox(width: 10),
                    Expanded(child: _rightPanel()),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            _balanceBar(),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: 220,
            height: 42,
            child: ElevatedButton(
              focusNode: _saveFocus,
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
    double? totalCash,
    bool combinedCashAndGrams = false,
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
                combinedCashAndGrams
                    ? '₹${_rupee(totalCash ?? 0)} · ${totalPure.toStringAsFixed(3)} g'
                    : '${totalPure.toStringAsFixed(3)} g',
                style: const TextStyle(
                  fontSize: 13,
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

  Widget _linesTable({
    required List<Widget> rows,
    bool showRate = false,
  }) {
    if (rows.isEmpty) return const SizedBox.shrink();
    const headerStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: AppColors.navy,
    );

    Widget head(String text, {int flex = 2, TextAlign align = TextAlign.left}) {
      return Expanded(
        flex: flex,
        child: Text(text, style: headerStyle, textAlign: align),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Container(
            color: AppColors.tableHeader,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                head('TYPE', flex: 2),
                head('WEIGHT', flex: 2, align: TextAlign.right),
                head('TOUCH %', flex: 2, align: TextAlign.right),
                head('PURE WT', flex: 2, align: TextAlign.right),
                if (showRate) head('RATE', flex: 2, align: TextAlign.right),
                const SizedBox(width: 24),
              ],
            ),
          ),
          ...rows,
        ],
      ),
    );
  }

  Widget _lineDataRow({
    required String type,
    required double weight,
    required double touch,
    required double pureWt,
    double? cashAmount,
    double? rate,
    required VoidCallback onRemove,
    int index = 0,
  }) {
    const cellStyle = TextStyle(fontSize: 12);
    Widget cell(String text, {int flex = 2, TextAlign align = TextAlign.left}) {
      return Expanded(
        flex: flex,
        child: Text(text, style: cellStyle, textAlign: align),
      );
    }

    final isCash = type == 'CASH';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: index.isEven ? Colors.white : AppColors.headerBand,
        border: const Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          cell(type, flex: 2),
          cell(
            isCash ? '₹${(cashAmount ?? 0).toStringAsFixed(2)}' : weight.toStringAsFixed(3),
            flex: 2,
            align: TextAlign.right,
          ),
          cell(isCash ? '—' : touch.toStringAsFixed(2), flex: 2, align: TextAlign.right),
          cell(pureWt.toStringAsFixed(3), flex: 2, align: TextAlign.right),
          if (rate != null)
            cell(rate.toStringAsFixed(0), flex: 2, align: TextAlign.right),
          SizedBox(
            width: 24,
            child: IconButton(
              icon: const Icon(Icons.close, size: 15, color: Colors.redAccent),
              onPressed: onRemove,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentEntryBlock({
    required String prefix,
    bool enabled = true,
  }) {
    final isCash = _paymentEntryType == 'CASH';
    final cashAmount =
        double.tryParse(_paymentEntryAmount.text.trim()) ?? 0;
    final cashGold = GoldLedger.cashToGold(cashAmount, _goldRate);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _compactField(
          width: FieldSizes.paymentTypeDropdown,
          child: DropdownButtonFormField<String>(
            value: _paymentEntryType,
            isExpanded: true,
            isDense: true,
            decoration: const InputDecoration(
              labelText: 'Type',
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            ),
            items: _paymentItemTypes
                .map(
                  (t) => DropdownMenuItem(
                    value: t,
                    child: Text(t),
                  ),
                )
                .toList(),
            onChanged: enabled
                ? (v) {
                    if (v == null) return;
                    _onPaymentTypeChanged(v);
                  }
                : null,
          ),
        ),
        if (isCash) ...[
          const SizedBox(width: 6),
          _compactField(
            width: FieldSizes.cash,
            child: TextFormField(
              controller: _paymentEntryAmount,
              focusNode: _paymentEntryAmountFocus,
              enabled: enabled,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13),
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: '₹ Amount',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              ),
              onTap: () => _paymentEntryAmount.selection = TextSelection(
                baseOffset: 0,
                extentOffset: _paymentEntryAmount.text.length,
              ),
              onFieldSubmitted: (_) => _commitPaymentEntry(),
              onChanged: (v) {
                setState(() {});
                advanceWhenComplete(
                  value: v,
                  from: _paymentEntryAmountFocus,
                  isComplete: FieldComplete.cash,
                  action: _commitPaymentEntry,
                );
              },
            ),
          ),
          const SizedBox(width: 6),
          _compactField(
            width: FieldSizes.weight,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: '$prefix.Weight',
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
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
        ] else ...[
          const SizedBox(width: 6),
          _compactField(
            width: FieldSizes.weight,
            child: TextFormField(
              controller: _paymentEntryWeight,
              focusNode: _paymentEntryWeightFocus,
              enabled: enabled,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13),
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: '$prefix.Weight',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 8),
              ),
              onTap: () => _paymentEntryWeight.selection = TextSelection(
                baseOffset: 0,
                extentOffset: _paymentEntryWeight.text.length,
              ),
              onChanged: (v) {
                setState(() {});
                advanceWhenComplete(
                  value: v,
                  from: _paymentEntryWeightFocus,
                  isComplete: FieldComplete.weight,
                  to: _paymentEntryTouchFocus,
                  toController: _paymentEntryTouch,
                );
                advanceWhenIdle(
                  value: v,
                  from: _paymentEntryWeightFocus,
                  when: FieldComplete.weightWholeIdle,
                  to: _paymentEntryTouchFocus,
                  toController: _paymentEntryTouch,
                );
              },
              onFieldSubmitted: (_) => FocusChain.focusNextFrame(
                _paymentEntryTouchFocus,
                controller: _paymentEntryTouch,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _compactField(
            width: FieldSizes.touch,
            child: TextFormField(
              controller: _paymentEntryTouch,
              focusNode: _paymentEntryTouchFocus,
              enabled: enabled,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13),
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: '$prefix.Touch %',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 8),
              ),
              onTap: () => _paymentEntryTouch.selection = TextSelection(
                baseOffset: 0,
                extentOffset: _paymentEntryTouch.text.length,
              ),
              onFieldSubmitted: (_) => _commitPaymentEntry(),
              onChanged: (v) {
                setState(() {});
                advanceWhenComplete(
                  value: v,
                  from: _paymentEntryTouchFocus,
                  isComplete: FieldComplete.touch,
                  action: _commitPaymentEntry,
                );
                advanceWhenIdle(
                  value: v,
                  from: _paymentEntryTouchFocus,
                  when: FieldComplete.touchWholeIdle,
                  action: _commitPaymentEntry,
                );
              },
            ),
          ),
          const SizedBox(width: 6),
          _compactField(
            width: FieldSizes.pure,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: '$prefix.Pure Wt',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 8),
              ),
              child: Text(
                _entryPure(_paymentEntryWeight, _paymentEntryTouch)
                    .toStringAsFixed(3),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _metalEntryRow({
    required String prefix,
    required String selectedType,
    required ValueChanged<String> onTypeChanged,
    required TextEditingController weight,
    required TextEditingController touch,
    required FocusNode weightFocus,
    required FocusNode touchFocus,
    required VoidCallback onTouchSubmitted,
    bool enabled = true,
  }) {
    final pure = _entryPure(weight, touch);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _compactField(
          width: FieldSizes.typeDropdown,
          child: DropdownButtonFormField<String>(
            value: selectedType,
            isExpanded: true,
            isDense: true,
            decoration: const InputDecoration(
              labelText: 'Type',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            ),
            items: _itemTypes
                .map(
                  (t) => DropdownMenuItem(
                    value: t,
                    child: Text(t),
                  ),
                )
                .toList(),
            onChanged: enabled
                ? (v) {
                    if (v == null) return;
                    onTypeChanged(v);
                    FocusChain.focusNextFrame(weightFocus, controller: weight);
                  }
                : null,
          ),
        ),
        const SizedBox(width: 6),
        _compactField(
          width: FieldSizes.weight,
          child: TextFormField(
            controller: weight,
            focusNode: weightFocus,
            enabled: enabled,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13),
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: '$prefix.Weight',
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            ),
            onTap: () => weight.selection = TextSelection(
              baseOffset: 0,
              extentOffset: weight.text.length,
            ),
            onChanged: (v) {
              setState(() {});
              advanceWhenComplete(
                value: v,
                from: weightFocus,
                isComplete: FieldComplete.weight,
                to: touchFocus,
                toController: touch,
              );
              advanceWhenIdle(
                value: v,
                from: weightFocus,
                when: FieldComplete.weightWholeIdle,
                to: touchFocus,
                toController: touch,
              );
            },
            onFieldSubmitted: (_) => FocusChain.focusNextFrame(
              touchFocus,
              controller: touch,
            ),
          ),
        ),
        const SizedBox(width: 6),
        _compactField(
          width: FieldSizes.touch,
          child: TextFormField(
            controller: touch,
            focusNode: touchFocus,
            enabled: enabled,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13),
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: '$prefix.Touch %',
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            ),
            onTap: () => touch.selection = TextSelection(
              baseOffset: 0,
              extentOffset: touch.text.length,
            ),
            onFieldSubmitted: (_) => onTouchSubmitted(),
            onChanged: (v) {
              setState(() {});
              advanceWhenComplete(
                value: v,
                from: touchFocus,
                isComplete: FieldComplete.touch,
                action: onTouchSubmitted,
              );
              advanceWhenIdle(
                value: v,
                from: touchFocus,
                when: FieldComplete.touchWholeIdle,
                action: onTouchSubmitted,
              );
            },
          ),
        ),
        const SizedBox(width: 6),
        _compactField(
          width: FieldSizes.pure,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: '$prefix.Pure Wt',
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            ),
            child: Text(
              pure.toStringAsFixed(3),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _leftPanel() =>
      _isPurchase ? _paymentPanel(title: 'ISSUE', prefix: 'I') : _billPanel(title: 'ISSUE', prefix: 'I');

  Widget _rightPanel() =>
      _isPurchase ? _billPanel(title: 'RECEIPT', prefix: 'R') : _paymentPanel(title: 'RECEIPT', prefix: 'R');

  Widget _billPanel({required String title, required String prefix}) {
    return _panelShell(
      title: title,
      totalLabel: '$title total pure wt',
      totalPure: _billTotalPure,
      rows: [
        _metalEntryRow(
          prefix: prefix,
          selectedType: _billEntryType,
          onTypeChanged: (v) => setState(() => _billEntryType = v),
          weight: _billEntryWeight,
          touch: _billEntryTouch,
          weightFocus: _billEntryWeightFocus,
          touchFocus: _billEntryTouchFocus,
          onTouchSubmitted: _commitBillEntry,
        ),
        _linesTable(
          showRate: false,
          rows: [
            for (var i = 0; i < _billLines.length; i++)
              _lineDataRow(
                index: i,
                type: _billLines[i].type,
                weight: _billLines[i].weight,
                touch: _billLines[i].touch,
                pureWt: _billLines[i].pureWt,
                onRemove: () => setState(() => _billLines.removeAt(i)),
              ),
          ],
        ),
      ],
    );
  }

  Widget _paymentPanel({required String title, required String prefix}) {
    return _panelShell(
      title: title,
      totalLabel: '$title totals',
      totalPure: _paymentTotalPure,
      totalCash: _paymentTotalCash,
      combinedCashAndGrams: true,
      rows: [
        _paymentEntryBlock(
          prefix: prefix,
        ),
        _linesTable(
          rows: [
            for (var i = 0; i < _paymentLines.length; i++)
              _lineDataRow(
                index: i,
                type: _paymentLines[i].type,
                weight: _paymentLines[i].weight,
                touch: _paymentLines[i].touch,
                cashAmount: _paymentLines[i].cashAmount,
                pureWt: _paymentLines[i].pureWtAtRate(_goldRate),
                onRemove: () => setState(() => _paymentLines.removeAt(i)),
              ),
          ],
        ),
        if (_goldRate <= 0 && _paymentTotalCash > 0)
          const Text(
            'Set G.P RATE on Master to convert cash to gold.',
            style: TextStyle(fontSize: 10.5, color: Colors.black54),
          ),
      ],
    );
  }

  Widget _balanceBar() {
    final partyGrams = _partyOutstanding?['grams'] ?? 0;
    final s = _settlement;
    final hasBillData = _hasBillOrPaymentData;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.headerBand,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Balance  ${_signedGrams(partyGrams)}',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
            if (hasBillData) ...[
              const SizedBox(height: 4),
              Text(
                'After this bill: ${_signedGrams(s.newGrams)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.mutedBlue,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _signedGrams(double grams) {
    final sign = grams > 0 ? '+' : grams < 0 ? '' : '';
    return '$sign${grams.toStringAsFixed(3)} g';
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
                      radius: 14,
                      backgroundColor: AppColors.headerBand,
                      child: Text(
                        "${row['billNo']}",
                        style: const TextStyle(
                            fontSize: 10, color: AppColors.navy),
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
                    trailing: row['fromLedger'] == true
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.delete,
                                color: Colors.redAccent, size: 16),
                            onPressed: () => _confirmDelete(row['id'] as int),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
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
            secondaryWidth: 240,
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
