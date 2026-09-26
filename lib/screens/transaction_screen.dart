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
import '../logic/bill_tax.dart';
import '../logic/gold_ledger.dart';
import '../models/bill_line_item.dart';
import '../models/party_billing_profile.dart';
import '../pdf/purchase_tax_invoice_pdf.dart';
import '../pdf/sales_tax_invoice_pdf.dart';
import '../pdf/simple_sales_tax_invoice_pdf.dart';
import '../util/sales_invoice_prefs.dart';
import '../widgets/party_billing_fields.dart';
import '../pdf/pdf_kit.dart';
import '../util/pdf_print.dart';
import '../models/party_suggestion.dart';
import '../widgets/party_search_field.dart';
import '../util/party_save_prompt.dart';
import '../util/focus_chain.dart';
import '../util/screen_activation.dart';
import '../util/touch_input.dart';
import '../theme/app_theme.dart';
import '../theme/field_sizes.dart';
import '../theme/responsive.dart';
import '../widgets/material_tile_card.dart';

enum TransactionKind { purchase, sales, receiptVoucher, paymentVoucher }

const Map<String, String> kItemTypeToRateName = {
  'GWT': 'G.P RATE',
  'FWT': 'F.T RATE',
  'KWT': 'KACHA RATE',
  'SWT': 'S RATE',
};

/// Receipt-side labels on Sales bills (old gold from customer).
const Map<String, String> kOldGoldReceiptTypeLabels = {
  'GWT': 'O.GWT',
  'FWT': 'O.FWT',
  'KWT': 'O.KWT',
  'SWT': 'O.SWT',
};

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
    with ScreenActivationMixin<TransactionScreen> {
  static const _itemTypes = ['GWT', 'FWT', 'KWT', 'SWT'];
  static const _paymentItemTypes = ['GWT', 'FWT', 'KWT', 'SWT', 'CASH'];
  static final RegExp _numberRegex = RegExp(r'^\d+(\.\d+)?$');

  final _partyController = TextEditingController();
  FocusNode? _partyFocus;

  final List<BillLineItem> _billLines = [];
  Map<String, String> _hsnByType = Map<String, String>.from(kDefaultHsnByItemType);

  final _partyAddressController = TextEditingController();
  final _partyCityController = TextEditingController();
  final _partyPincodeController = TextEditingController();
  final _partyGstinController = TextEditingController();
  final _partyStateController = TextEditingController();
  final _ewayBillController = TextEditingController();
  final _billNarrationController = TextEditingController();
  final _partyAddressFocus = FocusNode();
  final _partyCityFocus = FocusNode();
  final _partyPincodeFocus = FocusNode();
  final _partyGstinFocus = FocusNode();
  final _partyStateFocus = FocusNode();
  final _ewayBillFocus = FocusNode();
  final _billNarrationFocus = FocusNode();
  final _poNoController = TextEditingController();
  final _poDateController = TextEditingController();
  final _tdsAmountController = TextEditingController();
  bool _tdsUserOverride = false;

  static const double _defaultTdsRatePercent = 0.1;
  final List<_PanelLine> _paymentLines = [];

  String _billEntryType = _itemTypes.first;
  String _paymentEntryType = _paymentItemTypes.first;
  final _billEntryWeight = TextEditingController(text: '0.000');
  final _billEntryTouch = TextEditingController();
  final _billEntryDescription = TextEditingController();
  final _paymentEntryWeight = TextEditingController(text: '0.000');
  final _paymentEntryTouch = TextEditingController();
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
  final Map<String, double> _billRateOverrideByType = {};
  List<PartySuggestion> _partySuggestions = [];
  Map<String, double>? _partyOutstanding;
  Timer? _partyRefreshTimer;
  String? _billTouchError;
  String? _paymentTouchError;
  int? _editingTransactionId;
  int? _editingBillNo;
  String? _editingPreserveDate;
  String? _editingPreserveTime;

  int? _transactionRowId(Map<String, dynamic> row) {
    final id = row['id'];
    if (id is int) return id;
    if (id is num) return id.toInt();
    return int.tryParse(id?.toString() ?? '');
  }

  /// Purchase looks up Suppliers (stock coming in from them); Sales
  /// looks up Customers (stock going out to them).
  bool get _isReceiptVoucher => widget.kind == TransactionKind.receiptVoucher;

  bool get _isPaymentVoucher => widget.kind == TransactionKind.paymentVoucher;

  bool get _isVoucher => _isReceiptVoucher || _isPaymentVoucher;

  bool get _hideIssuePanel => _isReceiptVoucher || _isPurchaseBill;

  bool get _hideReceiptPanel => _isPaymentVoucher;

  bool get _isSales => widget.kind == TransactionKind.sales;

  String _receiptTypeLabel(String type) {
    if (_isSales && kOldGoldReceiptTypeLabels.containsKey(type)) {
      return kOldGoldReceiptTypeLabels[type]!;
    }
    return type;
  }

  bool get _isCustomerParty =>
      widget.kind == TransactionKind.sales || _isReceiptVoucher;

  bool get _isPurchaseBill => widget.kind == TransactionKind.purchase;

  bool get _isPurchase =>
      widget.kind == TransactionKind.purchase || _isPaymentVoucher;

  static final _rupeeFmt = NumberFormat('#,##0.00', 'en_IN');

  String _rupee(double amount) => _rupeeFmt.format(amount);

  String get _transactionType {
    if (_isReceiptVoucher) return 'RECEIPT';
    if (_isPaymentVoucher) return 'PAYMENT';
    return _isPurchase ? 'PURCHASE' : 'SALES';
  }

  String get _title {
    if (_isReceiptVoucher) return 'RECEIPT VOUCHER';
    if (_isPaymentVoucher) return 'PAYMENT VOUCHER';
    return _isPurchase ? 'PURCHASE' : 'SALES';
  }

  String get _numberLabel => _isVoucher ? 'VOUCHER NO' : 'BILL NO';

  String get _saveButtonLabel {
    if (_isReceiptVoucher) {
      return _editingTransactionId != null ? 'UPDATE RECEIPT' : 'SAVE RECEIPT';
    }
    if (_isPaymentVoucher) {
      return _editingTransactionId != null ? 'UPDATE PAYMENT' : 'SAVE PAYMENT';
    }
    if (_editingTransactionId != null) {
      return _isPurchase ? 'UPDATE PURCHASE' : 'UPDATE SALE';
    }
    return _isPurchase ? 'SAVE PURCHASE' : 'SAVE SALE';
  }

  String get _historyTitle {
    if (_isReceiptVoucher) return 'RECEIPTS';
    if (_isPaymentVoucher) return 'PAYMENTS';
    return _isPurchase ? 'PURCHASE' : 'SALES';
  }

  bool get _showPanels =>
      _partyController.text.trim().isNotEmpty || _hasBillOrPaymentData;

  bool get _hasBillOrPaymentData =>
      _billLines.isNotEmpty || _paymentLines.isNotEmpty;

  List<BillLineItem> get _billItems => _billLines;

  double get _billTaxableBeforeTds =>
      _billItems.fold(0, (sum, item) => sum + item.tax.taxableValue);

  double get _autoTdsAmount {
    if (!_isSales || _billLines.isEmpty) return 0;
    return _billTaxableBeforeTds * _defaultTdsRatePercent / 100;
  }

  double get _tdsAmountApplied {
    if (!_isSales || _billLines.isEmpty) return 0;
    if (_tdsUserOverride) {
      return double.tryParse(_tdsAmountController.text.trim()) ??
          _autoTdsAmount;
    }
    return _autoTdsAmount;
  }

  void _syncAutoTds({bool force = false}) {
    if (!_isSales || _billLines.isEmpty) return;
    if (_tdsUserOverride && !force) return;
    final amt = _autoTdsAmount;
    _tdsAmountController.text = amt.toStringAsFixed(2);
  }

  BillTaxTotals get _billTaxTotals {
    return BillTaxTotals.compute(
      lines: _billItems.map((i) => i.tax).toList(),
      tdsAmount: _tdsAmountApplied,
      tcsAmount: 0,
    );
  }

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

  double _masterRateForType(String type) {
    final rateName = kItemTypeToRateName[type];
    if (rateName == null) return 0;
    return _rates[rateName] ?? 0;
  }

  double _effectiveRateForType(String type) {
    return _billRateOverrideByType[type] ?? _masterRateForType(type);
  }

  double get _balancePure => _billTotalPure - _paymentTotalPure;

  bool get _paymentIsCashOnly =>
      _paymentLines.isNotEmpty && _paymentLines.every((line) => line.isCash);

  double get _paymentAmount => _paymentIsCashOnly
      ? _paymentTotalCash
      : _paymentTotalPure;

  SettlementResult get _settlement {
    final billGrams = _isVoucher ? 0.0 : _totalPureWt;
    final billRupees = _isVoucher ? 0.0 : _totalValue;
    final billSign = _isReceiptVoucher
        ? 1
        : _isPaymentVoucher
            ? -1
            : _isPurchase
                ? -1
                : 1;
    return settleLedger(
      oldGrams: _partyOutstanding?['grams'] ?? 0,
      oldRupees: _partyOutstanding?['rupees'] ?? 0,
      billGrams: billGrams,
      billRupees: billRupees,
      paymentMode: _paymentIsCashOnly ? 'CASH' : 'GOLD',
      paymentAmount: _paymentAmount,
      ratePerGram: _goldRate,
      billSign: billSign,
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
    _partyController
      ..addListener(_onPartyControllerChanged)
      ..addListener(() => _onPartyTextChanged());
    _billEntryTouchFocus.addListener(_onBillTouchFocusChange);
    _paymentEntryTouchFocus.addListener(_onPaymentTouchFocusChange);
  }

  void _onBillTouchFocusChange() {
    if (!_billEntryTouchFocus.hasFocus) {
      _validateBillTouchOnBlur();
    }
  }

  void _onPaymentTouchFocusChange() {
    if (!_paymentEntryTouchFocus.hasFocus) {
      _validatePaymentTouchOnBlur();
    }
  }

  void _validateBillTouchOnBlur() {
    final message = touchPercentBlurValidationMessage(_billEntryTouch.text);
    if (_billTouchError != message) {
      setState(() => _billTouchError = message);
    }
  }

  void _validatePaymentTouchOnBlur() {
    if (_paymentEntryType == 'CASH') return;
    final message = touchPercentBlurValidationMessage(_paymentEntryTouch.text);
    if (_paymentTouchError != message) {
      setState(() => _paymentTouchError = message);
    }
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
    _billEntryTouch.clear();
    _billEntryDescription.clear();
    _billTouchError = null;
  }

  void _resetPaymentEntry({bool resetType = true}) {
    if (resetType) _paymentEntryType = _paymentItemTypes.first;
    _paymentEntryWeight.text = '0.000';
    _paymentEntryTouch.clear();
    _paymentEntryAmount.text = '0.00';
    _paymentTouchError = null;
  }

  BillLineItem? _validatedBillEntry() {
    final weight = double.tryParse(_billEntryWeight.text.trim());
    if (weight == null ||
        !_numberRegex.hasMatch(_billEntryWeight.text.trim()) ||
        weight <= 0) {
      return null;
    }
    if (!isValidTouchPercent(_billEntryTouch.text)) {
      return null;
    }
    final touch = double.parse(_billEntryTouch.text.trim());
    final rate = _effectiveRateForType(_billEntryType);
    final hsn = _hsnByType[_billEntryType] ?? kDefaultHsnByItemType[_billEntryType] ?? '';
    final desc = _billEntryDescription.text.trim();
    return BillLineItem(
      type: _billEntryType,
      weight: weight,
      touch: touch,
      rate: rate,
      hsn: hsn,
      description: desc.isEmpty ? null : desc,
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
    if (weight == null ||
        !_numberRegex.hasMatch(_paymentEntryWeight.text.trim()) ||
        weight <= 0) {
      return null;
    }
    if (!isValidTouchPercent(_paymentEntryTouch.text)) {
      return null;
    }
    final touch = double.parse(_paymentEntryTouch.text.trim());
    return _PanelLine.metal(
      type: _paymentEntryType,
      weight: weight,
      touch: touch,
    );
  }

  void _commitBillEntry() {
    final touchMessage = touchPercentValidationMessage(_billEntryTouch.text);
    if (touchMessage != null) {
      setState(() => _billTouchError = touchMessage);
      return;
    }
    final item = _validatedBillEntry();
    if (item == null) {
      _showMessage('Enter weight and touch before continuing');
      return;
    }
    final rateName = kItemTypeToRateName[item.type] ?? item.type;
    if (_effectiveRateForType(item.type) <= 0) {
      _showMessage(
          "$rateName isn't set yet — update it on the Master screen first");
      return;
    }
    setState(() {
      _billLines.add(item);
      _resetBillEntry(resetType: false);
      _syncAutoTds(force: true);
    });
    FocusChain.focusNextFrame(
      _billEntryWeightFocus,
      controller: _billEntryWeight,
    );
  }

  void _commitPurchaseReceiptEntry() {
    if (_paymentEntryType == 'CASH') {
      _commitPaymentEntry();
      return;
    }
    _billEntryType = _paymentEntryType;
    _billEntryWeight.text = _paymentEntryWeight.text;
    _billEntryTouch.text = _paymentEntryTouch.text;
    _commitBillEntry();
    _resetPaymentEntry(resetType: false);
  }

  void _commitPaymentEntry() {
    if (_paymentEntryType != 'CASH') {
      final touchMessage =
          touchPercentValidationMessage(_paymentEntryTouch.text);
      if (touchMessage != null) {
        setState(() => _paymentTouchError = touchMessage);
        return;
      }
    }
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
    setState(() {
      _paymentEntryType = type;
      if (type == 'CASH') _paymentTouchError = null;
    });
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
    _billEntryTouchFocus.removeListener(_onBillTouchFocusChange);
    _paymentEntryTouchFocus.removeListener(_onPaymentTouchFocusChange);
    _partyController.dispose();
    _partyAddressController.dispose();
    _partyCityController.dispose();
    _partyPincodeController.dispose();
    _partyGstinController.dispose();
    _partyStateController.dispose();
    _ewayBillController.dispose();
    _billNarrationController.dispose();
    _partyAddressFocus.dispose();
    _partyCityFocus.dispose();
    _partyPincodeFocus.dispose();
    _partyGstinFocus.dispose();
    _partyStateFocus.dispose();
    _ewayBillFocus.dispose();
    _billNarrationFocus.dispose();
    _poNoController.dispose();
    _poDateController.dispose();
    _tdsAmountController.dispose();
    _billEntryWeight.dispose();
    _billEntryTouch.dispose();
    _billEntryDescription.dispose();
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
    final nextNo = _isVoucher
        ? await DatabaseHelper.instance.getNextVoucherNo(_transactionType)
        : await DatabaseHelper.instance.getNextBillNo(_transactionType);
    final history = _isVoucher
        ? await DatabaseHelper.instance.getVouchers(voucherType: _transactionType)
        : await DatabaseHelper.instance.getTransactions(_transactionType);
    final rates = await DatabaseHelper.instance.getRatesMap();
    final hsnMap = await DatabaseHelper.instance.getItemTypeHsnMap();
    final partyRows = _isCustomerParty
        ? await DatabaseHelper.instance.getCustomers()
        : await DatabaseHelper.instance.getSuppliers();
    if (!mounted) return;
    setState(() {
      _nextBillNo = nextNo;
      _history = history;
      _rates = rates;
      _hsnByType = hsnMap;
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

    if (_partyExactMatch(query)) {
      _loadPartyBillingProfile(query);
    }
  }

  Future<void> _loadPartyBillingProfile(String name) async {
    final profile = await DatabaseHelper.instance.getPartyProfile(
      name,
      isCustomer: _isCustomerParty,
    );
    if (!mounted) return;
    setState(() {
      _partyAddressController.text = profile.address;
      _partyCityController.text =
          profile.city.isNotEmpty ? profile.city : _partyCityController.text;
      _partyPincodeController.text = profile.pincode;
      _partyGstinController.text = profile.gstin;
      _partyStateController.text = profile.state;
    });
  }

  void _clearPartyBillingFields() {
    _partyAddressController.clear();
    _partyCityController.clear();
    _partyPincodeController.clear();
    _partyGstinController.clear();
    _partyStateController.clear();
    _ewayBillController.clear();
    _billNarrationController.clear();
    _tdsUserOverride = false;
    _tdsAmountController.clear();
  }

  void _focusPaymentEntry() {
    if (_paymentEntryType == 'CASH') {
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

  void _focusFirstPanelField() {
    if (_hideIssuePanel) {
      if (_isPurchaseBill) {
        if (_paymentEntryType == 'CASH') {
          _focusPaymentEntry();
        } else {
          FocusChain.focusNextFrame(
            _paymentEntryWeightFocus,
            controller: _paymentEntryWeight,
          );
        }
      } else {
        _focusPaymentEntry();
      }
      return;
    }
    FocusChain.focusNextFrame(
      _billEntryWeightFocus,
      controller: _billEntryWeight,
    );
  }

  void _selectParty(PartySuggestion party) {
    _partyController.text = party.name;
    _onPartyTextChanged(party.name);
    _focusBillingAddress();
  }

  void _focusBillingAddress() {
    FocusChain.focusNextFrame(
      _partyAddressFocus,
      controller: _partyAddressController,
    );
  }

  void _focusAfterState() {
    if (_isSales) {
      FocusChain.focusNextFrame(
        _ewayBillFocus,
        controller: _ewayBillController,
      );
    } else {
      _focusNarration();
    }
  }

  void _focusNarration() {
    FocusChain.focusNextFrame(
      _billNarrationFocus,
      controller: _billNarrationController,
    );
  }

  void _focusAfterNarration() => _focusFirstPanelField();

  bool _partyHasMatches(String name) =>
      PartySearchField.filterParties(_partySuggestions, name).isNotEmpty;

  bool _partyExactMatch(String name) =>
      _partySuggestions.any((party) => party.isExactNameMatch(name));

  Future<void> _advanceFromParty(String value) async {
    final name = value.trim();
    if (name.isEmpty) return;
    if (_partyHasMatches(name) && !_partyExactMatch(name)) return;
    if (!await _ensurePartySaved()) return;
    _focusBillingAddress();
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

  void _clearPurchasePoFields() {
    _poNoController.clear();
    _poDateController.clear();
  }

  Future<void> _pickPoDate() async {
    DateTime initial = DateTime.now();
    final existing = _poDateController.text.trim();
    if (existing.isNotEmpty) {
      try {
        initial = DateFormat('dd-MM-yyyy').parse(existing);
      } catch (_) {}
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'PO Date',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _poDateController.text = DateFormat('dd-MM-yyyy').format(picked);
    });
  }

  Widget _purchasePoFields() {
    const labelStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: AppColors.mutedBlue,
    );
    final narrow = !Responsive.isWide(context);
    Widget poNo = TextFormField(
      controller: _poNoController,
      style: const TextStyle(fontSize: 13),
      decoration: const InputDecoration(
        labelText: 'PO No',
        isDense: true,
      ),
    );
    Widget poDate = TextFormField(
      controller: _poDateController,
      readOnly: true,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: 'PO Date',
        isDense: true,
        suffixIcon: _poDateController.text.trim().isEmpty
            ? const Icon(Icons.calendar_today, size: 18)
            : IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () => setState(_poDateController.clear),
              ),
      ),
      onTap: _pickPoDate,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('PURCHASE ORDER (optional)', style: labelStyle),
        const SizedBox(height: 4),
        if (narrow)
          Column(
            children: [poNo, const SizedBox(height: 6), poDate],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: FieldSizes.billingPoNo, child: poNo),
              const SizedBox(width: 8),
              SizedBox(width: FieldSizes.billingPoDate, child: poDate),
            ],
          ),
      ],
    );
  }

  void _clearForm() {
    _partyController.clear();
    _clearPartyBillingFields();
    _clearPurchasePoFields();
    _clearPanels();
    setState(() {
      _partyOutstanding = null;
      _editingTransactionId = null;
      _editingBillNo = null;
      _editingPreserveDate = null;
      _editingPreserveTime = null;
    });
  }

  void _editBillLine(int index) {
    final item = _billLines[index];
    setState(() {
      _billEntryType = item.type;
      _billEntryWeight.text = item.weight.toStringAsFixed(3);
      _billEntryTouch.text = item.touch.toStringAsFixed(2);
      final defaultDesc = defaultItemDescriptionForType(item.type);
      _billEntryDescription.text =
          item.description == defaultDesc ? '' : item.description;
      _billTouchError = null;
      _billLines.removeAt(index);
      _syncAutoTds(force: true);
    });
    FocusChain.focusNextFrame(
      _billEntryWeightFocus,
      controller: _billEntryWeight,
    );
  }

  Future<void> _editBillLineTax(int index) async {
    final item = _billLines[index];
    final cgstCtrl =
        TextEditingController(text: item.cgstPercent.toStringAsFixed(2));
    final sgstCtrl =
        TextEditingController(text: item.sgstPercent.toStringAsFixed(2));
    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('GST % — ${item.type}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: cgstCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'CGST %'),
            ),
            TextField(
              controller: sgstCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'SGST %'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
    if (updated != true || !mounted) {
      cgstCtrl.dispose();
      sgstCtrl.dispose();
      return;
    }
    final cgst = double.tryParse(cgstCtrl.text.trim()) ?? item.cgstPercent;
    final sgst = double.tryParse(sgstCtrl.text.trim()) ?? item.sgstPercent;
    cgstCtrl.dispose();
    sgstCtrl.dispose();
    setState(() {
      _billLines[index] = item.copyWith(cgstPercent: cgst, sgstPercent: sgst);
    });
  }

  void _editPaymentLine(int index) {
    final line = _paymentLines[index];
    setState(() {
      if (line.isCash) {
        _paymentEntryType = 'CASH';
        _paymentEntryAmount.text = (line.cashAmount ?? 0).toStringAsFixed(2);
        _paymentTouchError = null;
      } else {
        _paymentEntryType = line.type;
        _paymentEntryWeight.text = line.weight.toStringAsFixed(3);
        _paymentEntryTouch.text = line.touch.toStringAsFixed(2);
        _paymentTouchError = null;
      }
      _paymentLines.removeAt(index);
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

  List<_PanelLine> _paymentLinesFromRow(Map<String, dynamic> row) {
    final raw = row['paymentItems'];
    if (raw == null || raw.toString().isEmpty || raw.toString() == '[]') {
      return [];
    }
    final list = jsonDecode(raw.toString()) as List<dynamic>;
    return list.map((entry) {
      final map = Map<String, dynamic>.from(entry as Map);
      if ((map['type'] ?? '').toString() == 'CASH') {
        return _PanelLine.cash(
          (map['cashAmount'] as num?)?.toDouble() ?? 0,
        );
      }
      return _PanelLine.metal(
        type: map['type'].toString(),
        weight: (map['weight'] as num).toDouble(),
        touch: (map['touch'] as num).toDouble(),
      );
    }).toList();
  }

  void _loadBillForEdit(Map<String, dynamic> row) {
    if (row['fromLedger'] == true) {
      _showMessage('This bill was imported from the ledger and cannot be edited here');
      return;
    }

    final billNo = row['billNo'] as int? ?? _nextBillNo;
    setState(() {
      _editingTransactionId = _transactionRowId(row);
      _editingBillNo = billNo;
      _editingPreserveDate = (row['date'] ?? '').toString();
      _editingPreserveTime = (row['time'] ?? '').toString();
      _nextBillNo = billNo;
      _partyController.text = (row['partyName'] ?? '').toString();
      _partyAddressController.text = (row['partyAddress'] ?? '').toString();
      _partyCityController.text = (row['partyCity'] ?? '').toString();
      _partyPincodeController.text = (row['partyPincode'] ?? '').toString();
      _partyGstinController.text = (row['partyGstin'] ?? '').toString();
      _partyStateController.text = (row['partyState'] ?? '').toString();
      _ewayBillController.text = (row['ewayBill'] ?? '').toString();
      _billNarrationController.text = (row['billNarration'] ?? '').toString();
      _poNoController.text = (row['poNo'] ?? '').toString();
      _poDateController.text = (row['poDate'] ?? '').toString();
      final savedTds =
          double.tryParse((row['tdsAmount'] ?? '').toString()) ?? 0;
      _tdsAmountController.text = savedTds.toStringAsFixed(2);
      _tdsUserOverride = true;
      _billLines
        ..clear()
        ..addAll(_itemsFromRow(row));
      _paymentLines
        ..clear()
        ..addAll(_paymentLinesFromRow(row));
      _resetBillEntry();
      _resetPaymentEntry();
      _billTouchError = null;
      _paymentTouchError = null;
    });
    _onPartyTextChanged(_partyController.text.trim());
    if (_partyFocus != null) {
      FocusChain.focusNextFrame(_partyFocus!, controller: _partyController);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  bool _validateBillRates() {
    for (final item in _billItems) {
      final rateName = kItemTypeToRateName[item.type] ?? item.type;
      if (item.rate <= 0) {
        _showMessage(
            "$rateName isn't set yet — update it on the Master screen first");
        return false;
      }
    }
    return true;
  }

  Future<void> _editBillEntryRate([String? typeOverride]) async {
    final type = typeOverride ?? _billEntryType;
    final rateName = kItemTypeToRateName[type] ?? type;
    final master = _masterRateForType(type);
    final current = _effectiveRateForType(type);
    final ctrl = TextEditingController(
      text: current > 0 ? current.toStringAsFixed(2) : '',
    );
    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Rate — $type ($rateName)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (master > 0)
              Text(
                'Daily Rate: ${master.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Rate for this bill line',
                isDense: true,
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          if (_billRateOverrideByType.containsKey(type))
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (mounted) {
                  setState(() => _billRateOverrideByType.remove(type));
                }
              },
              child: const Text('USE DAILY RATE'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
    if (updated == true && mounted) {
      final parsed = double.tryParse(ctrl.text.trim());
      if (parsed != null && parsed > 0) {
        setState(() => _billRateOverrideByType[type] = parsed);
      }
    }
    ctrl.dispose();
  }

  /// Compact Daily Rate chip above metal entry (ISSUE on Sales, RECEIPT on Purchase).
  Widget _billEntryRateChip({String? typeOverride}) {
    final type = typeOverride ?? _billEntryType;
    final rateName = kItemTypeToRateName[type] ?? type;
    final rate = _effectiveRateForType(type);
    final overridden = _billRateOverrideByType.containsKey(type);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _editBillEntryRate(type),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.cardWhite,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: overridden ? AppColors.mutedBlue : AppColors.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    rateName,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.mutedBlue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    rate > 0 ? rate.toStringAsFixed(2) : '—',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.edit_outlined, size: 14, color: Colors.black45),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _paymentLineToJson(_PanelLine line) {
    if (line.isCash) {
      return {
        'type': 'CASH',
        'weight': 0,
        'touch': 0,
        'pureWt': 0,
        'cashAmount': line.cashAmount ?? 0,
      };
    }
    final rateName = kItemTypeToRateName[line.type];
    final rate = _rates[rateName] ?? 0;
    return {
      'type': line.type,
      'weight': line.weight,
      'touch': line.touch,
      'pureWt': double.parse(line.metalPureWt.toStringAsFixed(3)),
      'rate': rate,
    };
  }

  Future<void> _saveTransaction() async {
    if (_partyController.text.trim().isEmpty) {
      _showMessage("Enter a name");
      return;
    }
    if (!await _ensurePartySaved()) return;
    if (_isVoucher) {
      if (_paymentLines.isEmpty) {
        _showMessage(_isReceiptVoucher
            ? 'Enter at least one receipt amount'
            : 'Enter at least one payment amount');
        return;
      }
      if (_paymentLines.any((line) => line.isCash) && _goldRate <= 0) {
        _showMessage("Set G.P RATE on Master so cash can convert to gold");
        return;
      }
      await _saveVoucher();
      return;
    }
    if (_billItems.isEmpty) {
      _showMessage(_isPurchase
          ? "Enter at least one receipt weight (gold received)"
          : "Enter at least one issue weight");
      return;
    }
    if (!_validateBillRates()) return;

    setState(() => _saving = true);

    final date = (_editingTransactionId != null &&
            _editingPreserveDate != null &&
            _editingPreserveDate!.isNotEmpty)
        ? _editingPreserveDate!
        : DateFormat("dd-MM-yyyy").format(DateTime.now());
    final time = (_editingTransactionId != null &&
            _editingPreserveTime != null &&
            _editingPreserveTime!.isNotEmpty)
        ? _editingPreserveTime!
        : DateFormat("hh:mm a").format(DateTime.now());

    final items = _billItems;
    final s = _settlement;
    final taxTotals = _billTaxTotals;
    final paymentMode = _paymentIsCashOnly ? 'CASH' : 'GOLD';
    final billNo = _editingBillNo ?? _nextBillNo;
    final tdsAmt = _tdsAmountApplied;
    final record = {
      'transactionType': _transactionType,
      'billNo': billNo,
      'partyName': _partyController.text.trim(),
      'partyAddress': _partyAddressController.text.trim(),
      'partyCity': _partyCityController.text.trim(),
      'partyPincode': _partyPincodeController.text.trim(),
      'partyGstin': _partyGstinController.text.trim(),
      'partyState': _partyStateController.text.trim(),
      if (_isSales) 'ewayBill': _ewayBillController.text.trim(),
      'billNarration': _billNarrationController.text.trim(),
      if (_isPurchaseBill) 'poNo': _poNoController.text.trim(),
      if (_isPurchaseBill) 'poDate': _poDateController.text.trim(),
      'tdsApplicable': (_isSales && _billLines.isNotEmpty) ? 1 : 0,
      'tdsAmount': tdsAmt.toStringAsFixed(2),
      'tcsApplicable': 0,
      'tcsAmount': '0.00',
      'totalTaxable': taxTotals.totalTaxable.toStringAsFixed(2),
      'totalInclusive': taxTotals.totalInclusive.toStringAsFixed(2),
      'roundOff': taxTotals.roundOff.toStringAsFixed(2),
      'grandTotal': taxTotals.grandTotal.toStringAsFixed(2),
      'items': jsonEncode(items.map((i) => i.toJson()).toList()),
      if (_paymentLines.isNotEmpty)
        'paymentItems': jsonEncode(
            _paymentLines.map(_paymentLineToJson).toList()),
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

    if (_editingTransactionId != null) {
      final billRef = '${_isPurchase ? 'PUR' : 'SAL'}-$billNo';
      await DatabaseHelper.instance.deleteLedgerByBillRef(
        billRef,
        isCustomer: _isCustomerParty,
      );
      await DatabaseHelper.instance.deleteTransaction(_editingTransactionId!);
    }

    await DatabaseHelper.instance.insertTransaction(record);
    await _postToLedger(date, time, s);

    if (!mounted) return;

    setState(() => _saving = false);

    final savedRow = Map<String, dynamic>.from(record);
    final billNoSaved = billNo;
    final partyName = _partyController.text.trim();
    final wasEdit = _editingTransactionId != null;
    _clearForm();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              wasEdit
                  ? "Bill #$billNoSaved updated for $partyName"
                  : "Bill #$billNoSaved saved and posted to $partyName's ledger")),
    );

    await _load();
    if (!mounted) return;
    if (!wasEdit) {
      final txnType = (savedRow['transactionType'] ?? '').toString();
      if (txnType == 'SALES') {
        await _saveAndPrintBillPdf(
          savedRow,
          gstInvoice: true,
          salesInvoiceFormat: SalesInvoiceFormat.detailed,
        );
      } else {
        await _shareBillPdf(
          savedRow,
          gstInvoice: true,
          openAfterSave: false,
        );
      }
    }
  }

  Future<void> _saveVoucher() async {
    setState(() => _saving = true);

    final date = DateFormat("dd-MM-yyyy").format(DateTime.now());
    final time = DateFormat("hh:mm a").format(DateTime.now());
    final s = _settlement;
    final paymentMode = _paymentIsCashOnly ? 'CASH' : 'GOLD';
    final partyName = _partyController.text.trim();
    final type = _transactionType;

    await DatabaseHelper.instance.insertVoucher({
      'voucherType': type,
      'voucherNo': _nextBillNo,
      'partyName': partyName,
      'isCustomer': _isCustomerParty ? 1 : 0,
      'paymentMode': paymentMode,
      'amount': _paymentAmount.toStringAsFixed(_paymentIsCashOnly ? 2 : 3),
      'amountUnit': paymentMode == 'GOLD' ? 'GRAMS' : 'RUPEES',
      'cashToGold': s.cashToGoldGrams.toStringAsFixed(3),
      'goldRateUsed': s.ratePerGram.toStringAsFixed(2),
      'oldGrams': s.oldGrams.toStringAsFixed(3),
      'oldRupees': s.oldRupees.toStringAsFixed(2),
      'newGrams': s.newGrams.toStringAsFixed(3),
      'newRupees': s.newRupees.toStringAsFixed(2),
      'narration': '',
      'date': date,
      'time': time,
    });

    final deltaG = s.newGrams - s.oldGrams;
    final entry = {
      'name': partyName,
      'mobile': '',
      'city': '',
      'cr': deltaG < 0 ? deltaG.abs().toStringAsFixed(3) : '0',
      'dr': deltaG > 0 ? deltaG.abs().toStringAsFixed(3) : '0',
      'narration':
          'Voucher $type #$_nextBillNo · ${s.paymentLabel}. Old ${s.oldGrams.toStringAsFixed(3)}g → New ${s.newGrams.toStringAsFixed(3)}g',
      'balanceUnit': 'GRAMS',
      'billRef': '$type-$_nextBillNo',
      'date': date,
      'time': time,
    };
    if (_isCustomerParty) {
      await DatabaseHelper.instance.insertCustomer({
        ...entry,
        'drGross': '',
        'drNet': '',
      });
    } else {
      await DatabaseHelper.instance.insertSupplier({
        ...entry,
        'gross': '',
        'net': '',
      });
    }

    if (!mounted) return;
    setState(() => _saving = false);

    final voucherNoSaved = _nextBillNo;
    _clearForm();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Voucher #$type-$voucherNoSaved saved. Balance ${_signedGrams(s.newGrams)}',
        ),
      ),
    );

    await _load();
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
      'billRef': '${_isPurchase ? 'PUR' : 'SAL'}-${_editingBillNo ?? _nextBillNo}',
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

  Future<void> _confirmDelete(Map<String, dynamic> row) async {
    final fromLedger = row['fromLedger'] == true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_isVoucher ? 'Delete Voucher' : 'Delete Bill'),
        content: Text(_isVoucher
            ? 'Are you sure you want to delete this voucher?'
            : fromLedger
                ? 'Remove this ledger entry from Sales history? '
                    'This deletes the matching customer/supplier ledger row '
                    '(bill reference only — not a full saved bill).'
                : 'Are you sure you want to delete this record?'),
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
      if (_isVoucher) {
        await DatabaseHelper.instance.deleteVoucher(row['id'] as int);
      } else {
        await _deleteBillRow(row);
      }
      _load();
    }
  }

  Future<void> _deleteBillRow(Map<String, dynamic> row) async {
    final billNo = row['billNo'];
    final storedRef = (row['billRef'] ?? '').toString().trim();
    final billRef = storedRef.isNotEmpty
        ? storedRef
        : '${_isPurchase ? 'PUR' : 'SAL'}-$billNo';

    final id = _transactionRowId(row);
    if (row['fromLedger'] != true && id != null && id > 0) {
      await DatabaseHelper.instance.deleteTransaction(id);
    }

    await DatabaseHelper.instance.deleteLedgerByBillRef(
      billRef,
      isCustomer: _isCustomerParty,
    );
  }

  void _showBillDetails(Map<String, dynamic> row) {
    // Post-save print can leave _sharingPdf true; bill actions must stay tappable.
    _sharingPdf = false;

    final items = (jsonDecode(row['items'] as String) as List)
        .map((e) => BillLineItem.fromJson(e as Map<String, dynamic>))
        .toList();

    Future<void> openInvoice(
      SalesInvoiceFormat format,
    ) async {
      await _shareBillPdf(
        row,
        gstInvoice: true,
        salesInvoiceFormat: format,
        openAfterSave: true,
      );
    }

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
              if ((row['grandTotal'] ?? '').toString().trim().isNotEmpty)
                _detailRow('Grand Total (₹)', row['grandTotal']),
              if (items.isNotEmpty) ...[
                _detailRow(
                  'Avg Rate (₹)',
                  _weightedBillRate(items).toStringAsFixed(2),
                ),
              ],
              _detailRow("Payment Mode", row['paymentMode']),
              _detailRow("Payment Amount", row['paymentAmount']),
              _detailRow(
                "Balance",
                "${row['balance'] ?? '-'} ${row['balanceUnit'] ?? ''}",
              ),
              if ((row['transactionType'] ?? '').toString() == 'PURCHASE') ...[
                if ((row['poNo'] ?? '').toString().trim().isNotEmpty)
                  _detailRow('PO No', row['poNo']),
                if ((row['poDate'] ?? '').toString().trim().isNotEmpty)
                  _detailRow('PO Date', row['poDate']),
              ],
              _detailRow("Date", "${row['date'] ?? ''} ${row['time'] ?? ''}"),
            ],
          ),
        ),
        actions: [
          if (row['fromLedger'] != true)
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _loadBillForEdit(row);
              },
              child: const Text('EDIT'),
            ),
          if (row['fromLedger'] == true)
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _confirmDelete(row);
              },
              child: const Text(
                'DELETE',
                style: TextStyle(color: Colors.red),
              ),
            ),
          if (row['fromLedger'] != true) ...[
            if ((row['transactionType'] ?? '').toString() == 'PURCHASE')
              FilledButton.tonal(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await _shareBillPdf(
                    row,
                    gstInvoice: false,
                    openAfterSave: true,
                  );
                },
                child: const Text('ACCOUNTS SLIP'),
              ),
            if ((row['transactionType'] ?? '').toString() == 'SALES') ...[
              FilledButton.tonal(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await openInvoice(SalesInvoiceFormat.detailed);
                },
                child: const Text('GST INVOICE'),
              ),
              FilledButton.tonal(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await openInvoice(SalesInvoiceFormat.simple);
                },
                child: const Text('SIMPLE INVOICE'),
              ),
            ] else
              FilledButton.tonal(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await _shareBillPdf(
                    row,
                    gstInvoice: true,
                    openAfterSave: true,
                  );
                },
                child: const Text('GST INVOICE'),
              ),
          ],
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("CLOSE"),
          ),
        ],
      ),
    );
  }
  List<BillLineItem> _itemsFromRow(Map<String, dynamic> row) {
    return (jsonDecode((row['items'] ?? '[]').toString()) as List)
        .map((e) => BillLineItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  BillTaxTotals _taxTotalsFromRow(
    Map<String, dynamic> row,
    List<BillLineItem> items,
  ) {
    return BillTaxTotals(
      totalTaxable: double.tryParse(
              (row['totalTaxable'] ?? row['totalValue'] ?? '0').toString()) ??
          items.fold(0, (s, i) => s + i.tax.taxableValue),
      totalInclusive: double.tryParse(
              (row['totalInclusive'] ?? '0').toString()) ??
          items.fold(0, (s, i) => s + i.tax.inclusiveAmount),
      roundOff: double.tryParse((row['roundOff'] ?? '0').toString()) ?? 0,
      grandTotal: double.tryParse(
              (row['grandTotal'] ?? row['totalValue'] ?? '0').toString()) ??
          items.fold(0, (s, i) => s + i.tax.inclusiveAmount),
    );
  }

  double _weightedBillRate(List<BillLineItem> items) {
    var pure = 0.0;
    var weighted = 0.0;
    for (final item in items) {
      pure += item.pureWt;
      weighted += item.pureWt * item.rate;
    }
    return pure > 0 ? weighted / pure : 0;
  }

  Future<Uint8List> _buildGstInvoicePdf(
    Map<String, dynamic> row, {
    SalesInvoiceFormat? salesInvoiceFormat,
  }) async {
    final items = _itemsFromRow(row);
    final isSalesBill = row['transactionType'] == 'SALES';
    final tdsApplicable = (row['tdsApplicable'] as int? ?? 0) == 1;
    final tcsApplicable = (row['tcsApplicable'] as int? ?? 0) == 1;
    final tdsAmount =
        double.tryParse((row['tdsAmount'] ?? '0').toString()) ?? 0;
    final tcsAmount =
        double.tryParse((row['tcsAmount'] ?? '0').toString()) ?? 0;
    final totals = _taxTotalsFromRow(row, items);
    final salesFormat = isSalesBill
        ? (salesInvoiceFormat ?? await SalesInvoicePrefs.getFormat())
        : null;
    final doc = await PdfKit.document();
    final salesCopyLabels = salesFormat == SalesInvoiceFormat.simple
        ? [SimpleSalesTaxInvoicePdf.copyOriginalForBuyer]
        : [
            SalesTaxInvoicePdf.copyOriginalForRecipient,
            SalesTaxInvoicePdf.copyDuplicateForTransporter,
          ];
    for (final copyLabel in salesCopyLabels) {
      doc.addPage(
        isSalesBill
            ? (salesFormat == SalesInvoiceFormat.simple
                ? SimpleSalesTaxInvoicePdf.buildPage(
                    buyer: PartyBillingProfile.fromTransactionRow(row),
                    row: row,
                    items: items,
                    totals: totals,
                    copyLabel: copyLabel,
                  )
                : SalesTaxInvoicePdf.buildPage(
                    buyer: PartyBillingProfile.fromTransactionRow(row),
                    row: row,
                    items: items,
                    totals: totals,
                    tdsApplicable: tdsApplicable,
                    tcsApplicable: tcsApplicable,
                    tdsAmount: tdsAmount,
                    tcsAmount: tcsAmount,
                    copyLabel: copyLabel,
                  ))
            : PurchaseTaxInvoicePdf.buildPage(
                row: row,
                items: items,
                totals: totals,
                tdsApplicable: tdsApplicable,
                tcsApplicable: tcsApplicable,
                tdsAmount: tdsAmount,
                tcsAmount: tcsAmount,
                copyLabel: copyLabel,
              ),
      );
    }
    return doc.save();
  }

  Future<Uint8List> _buildAccountsSlipPdf(Map<String, dynamic> row) async {
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

  String _billPdfFileName(
    Map<String, dynamic> row, {
    required bool gstInvoice,
    SalesInvoiceFormat? salesInvoiceFormat,
  }) {
    final isSales = row['transactionType'] == 'SALES';
    final kind = isSales ? 'sales' : 'purchase';
    if (!gstInvoice) {
      return '${kind}_accounts_slip_${row['billNo']}.pdf';
    }
    if (isSales && salesInvoiceFormat == SalesInvoiceFormat.simple) {
      return '${kind}_simple_invoice_${row['billNo']}.pdf';
    }
    return '${kind}_gst_invoice_${row['billNo']}.pdf';
  }

  Future<void> _saveAndPrintBillPdf(
    Map<String, dynamic> row, {
    required bool gstInvoice,
    SalesInvoiceFormat? salesInvoiceFormat,
  }) async {
    if (_sharingPdf) return;
    _sharingPdf = true;
    try {
      final bytes = gstInvoice
          ? await _buildGstInvoicePdf(
              row,
              salesInvoiceFormat: salesInvoiceFormat,
            )
          : await _buildAccountsSlipPdf(row);
      final fileName = _billPdfFileName(
        row,
        gstInvoice: gstInvoice,
        salesInvoiceFormat: salesInvoiceFormat,
      );
      final file = await PdfKit.savePdf(bytes: bytes, fileName: fileName);
      if (!mounted) return;
      _showMessage('PDF saved: ${file.path}');
      final printed = await PdfPrint.showDialog(
        bytes: bytes,
        documentName: fileName,
      );
      if (!mounted) return;
      if (!printed) {
        _showMessage(
          'Print cancelled or unavailable. PDF is saved — open it from ${file.path}',
        );
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Saved bill PDF but could not open print: $e');
      }
    } finally {
      _sharingPdf = false;
    }
  }

  Future<void> _shareBillPdf(
    Map<String, dynamic> row, {
    required bool gstInvoice,
    SalesInvoiceFormat? salesInvoiceFormat,
    bool openAfterSave = true,
  }) async {
    if (_sharingPdf) return;
    _sharingPdf = true;
    try {
      final bytes = gstInvoice
          ? await _buildGstInvoicePdf(
              row,
              salesInvoiceFormat: salesInvoiceFormat,
            )
          : await _buildAccountsSlipPdf(row);
      final label = !gstInvoice
          ? 'Accounts slip'
          : (salesInvoiceFormat == SalesInvoiceFormat.simple
              ? 'Simple invoice'
              : 'GST invoice');
      final file = await PdfKit.sharePdf(
        bytes: bytes,
        fileName: _billPdfFileName(
          row,
          gstInvoice: gstInvoice,
          salesInvoiceFormat: salesInvoiceFormat,
        ),
        subject: '$label #${row['billNo']} - ${row['partyName'] ?? ''}',
        text:
            '$label (bill #${row['billNo']}). '
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
  Widget _billingDetailsSection() {
    final billingFields = PartyBillingFields(
      compact: true,
      addressController: _partyAddressController,
      cityController: _partyCityController,
      pincodeController: _partyPincodeController,
      gstinController: _partyGstinController,
      stateController: _partyStateController,
      addressFocus: _partyAddressFocus,
      cityFocus: _partyCityFocus,
      pincodeFocus: _partyPincodeFocus,
      gstinFocus: _partyGstinFocus,
      stateFocus: _partyStateFocus,
      onAddressSubmitted: () => FocusChain.focusNextFrame(
        _partyCityFocus,
        controller: _partyCityController,
      ),
      onCitySubmitted: () => FocusChain.focusNextFrame(
        _partyPincodeFocus,
        controller: _partyPincodeController,
      ),
      onPincodeSubmitted: () => FocusChain.focusNextFrame(
        _partyGstinFocus,
        controller: _partyGstinController,
      ),
      onGstinSubmitted: () => FocusChain.focusNextFrame(
        _partyStateFocus,
        controller: _partyStateController,
      ),
      onStateSubmitted: _focusAfterState,
    );

    final ewayField = _isSales
        ? SizedBox(
            width: FieldSizes.billingEway,
            child: TextFormField(
              controller: _ewayBillController,
              focusNode: _ewayBillFocus,
              style: const TextStyle(fontSize: 13),
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => _focusNarration(),
              decoration: const InputDecoration(
                labelText: 'E-Way Bill No (optional)',
                isDense: true,
              ),
            ),
          )
        : const SizedBox.shrink();

    final balanceAndNarration = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_partyOutstanding != null) _currentBalanceStrip(),
        if (_partyOutstanding != null) const SizedBox(height: 8),
        TextFormField(
          controller: _billNarrationController,
          focusNode: _billNarrationFocus,
          maxLines: 2,
          style: const TextStyle(fontSize: 13),
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _focusAfterNarration(),
          decoration: const InputDecoration(
            labelText: 'Narration',
            isDense: true,
          ),
        ),
      ],
    );

    final leftColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        billingFields,
        if (_isSales) ...[
          const SizedBox(height: 2),
          ewayField,
        ],
      ],
    );

    if (Responsive.isWide(context)) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: leftColumn),
          const SizedBox(width: 16),
          Expanded(child: balanceAndNarration),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        leftColumn,
        const SizedBox(height: 8),
        balanceAndNarration,
      ],
    );
  }

  Widget _partyNameField() {
    final field = PartySearchField(
      label: _isCustomerParty ? 'Customer Name' : 'Supplier Name',
      controller: _partyController,
      onFocusNodeReady: _bindPartyFocus,
      parties: _partySuggestions,
      helperText: 'Search saved name, mobile, or city',
      readOnly: _editingTransactionId != null,
      onFocus: _refreshParties,
      onSelected: _selectParty,
      onFieldSubmitted: () => _advanceFromParty(_partyController.text),
      onChanged: _onPartyNameChanged,
    );
    if (Responsive.isCompact(context)) {
      return KeyedSubtree(
        key: const Key('party_name_field'),
        child: field,
      );
    }
    return KeyedSubtree(
      key: const Key('party_name_field'),
      child: SizedBox(width: FieldSizes.name, child: field),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TransactionBillHeader(
            numberLabel: _numberLabel,
            billNumber: '$_nextBillNo',
            dateTimeText: DateFormat('dd-MM-yyyy  hh:mm a').format(DateTime.now()),
          ),
          const SizedBox(height: 12),
          if (_isPurchaseBill) ...[
            _purchasePoFields(),
            const SizedBox(height: 10),
          ],
          _partyNameField(),
          if (!_isVoucher && _partyController.text.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            _billingDetailsSection(),
          ],
          if (_showPanels) ...[
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final singlePanel = _hideIssuePanel || _hideReceiptPanel;
                final stacked = constraints.maxWidth < 720 || singlePanel;
                final receiptFirst = _isPurchase;

                Widget panelColumn() {
                  if (receiptFirst) {
                    return Column(
                      children: [
                        if (!_hideReceiptPanel) _receiptPanel(),
                        if (!_hideIssuePanel && !_hideReceiptPanel)
                          const SizedBox(height: 10),
                        if (!_hideIssuePanel) _issuePanel(),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      if (!_hideIssuePanel) _issuePanel(),
                      if (!_hideIssuePanel && !_hideReceiptPanel)
                        const SizedBox(height: 10),
                      if (!_hideReceiptPanel) _receiptPanel(),
                    ],
                  );
                }

                Widget panelRow() {
                  if (receiptFirst) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!_hideReceiptPanel) Expanded(child: _receiptPanel()),
                        if (!_hideIssuePanel && !_hideReceiptPanel)
                          const SizedBox(width: 10),
                        if (!_hideIssuePanel) Expanded(child: _issuePanel()),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!_hideIssuePanel) Expanded(child: _issuePanel()),
                      if (!_hideIssuePanel && !_hideReceiptPanel)
                        const SizedBox(width: 10),
                      if (!_hideReceiptPanel) Expanded(child: _receiptPanel()),
                    ],
                  );
                }

                if (stacked) {
                  return panelColumn();
                }
                return panelRow();
              },
            ),
            if (_hasBillOrPaymentData) ...[
              const SizedBox(height: 10),
              _projectedBalanceBar(),
            ],
            if (!_isVoucher && _billLines.isNotEmpty) ...[
              const SizedBox(height: 10),
              _taxTotalsSection(),
            ],
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
                  : Text(_saveButtonLabel),
            ),
          ),
        ],
      ),
    );
  }
  Widget _taxTotalsSection() {
    final totals = _billTaxTotals;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'GST TOTALS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < _billLines.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_billLines[i].type} — taxable ₹${_rupee(_billLines[i].tax.taxableValue)} '
                      '(incl. ₹${_rupee(_billLines[i].tax.inclusiveAmount)}) '
                      'CGST ${_billLines[i].cgstPercent}% / SGST ${_billLines[i].sgstPercent}%',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.percent, size: 18),
                    tooltip: 'Edit GST %',
                    onPressed: () => _editBillLineTax(i),
                  ),
                ],
              ),
            ),
          const Divider(height: 16),
          _totalRow('Total taxable value', totals.totalTaxable),
          _totalRow('Total inclusive of tax', totals.totalInclusive),
          if (_isSales && _billLines.isNotEmpty) ...[
            const SizedBox(height: 4),
            TextField(
              controller: _tdsAmountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText:
                    'TDS ($_defaultTdsRatePercent% of taxable — editable)',
                isDense: true,
                helperText:
                    'Auto: ₹${_rupee(_autoTdsAmount)} on ₹${_rupee(_billTaxableBeforeTds)} taxable',
                helperMaxLines: 2,
              ),
              onChanged: (_) {
                _tdsUserOverride = true;
                setState(() {});
              },
            ),
          ],
          _totalRow('Grand total (invoice)', totals.grandTotal, highlight: true),
        ],
      ),
    );
  }

  Widget _compactField({
    double? width,
    required Widget child,
  }) {
    if (width != null) return SizedBox(width: width, child: child);
    return child;
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
                const SizedBox(width: 48),
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
    String? displayType,
    required double weight,
    required double touch,
    required double pureWt,
    double? cashAmount,
    double? rate,
    required VoidCallback onRemove,
    VoidCallback? onEdit,
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
          cell(displayType ?? type, flex: 2),
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
            width: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onEdit != null)
                  IconButton(
                    icon: const Icon(Icons.edit, size: 15, color: AppColors.navy),
                    onPressed: onEdit,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Edit row',
                  ),
                IconButton(
                  icon: const Icon(Icons.close, size: 15, color: Colors.redAccent),
                  onPressed: onRemove,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Remove row',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentEntryBlock({
    required String prefix,
    bool enabled = true,
    VoidCallback? onCommit,
  }) {
    final commit = onCommit ?? _commitPaymentEntry;
    final isCash = _paymentEntryType == 'CASH';
    final cashAmount =
        double.tryParse(_paymentEntryAmount.text.trim()) ?? 0;
    final cashGold = GoldLedger.cashToGold(cashAmount, _goldRate);
    final stack = Responsive.isCompact(context);
    final fieldWidth = stack ? null : FieldSizes.paymentTypeDropdown;

    final typeField = _compactField(
      width: fieldWidth,
      child: DropdownButtonFormField<String>(
        value: _paymentEntryType,
        isExpanded: true,
        isDense: true,
        decoration: const InputDecoration(
          labelText: 'Type',
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        ),
        items: _paymentItemTypes
            .map(
              (t) => DropdownMenuItem(
                value: t,
                child: Text(_receiptTypeLabel(t)),
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
    );

    if (isCash) {
      final amountField = _compactField(
        width: stack ? null : FieldSizes.cash,
        child: TextFormField(
          controller: _paymentEntryAmount,
          focusNode: _paymentEntryAmountFocus,
          enabled: enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 13),
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: '₹ Amount',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          ),
          onTap: () => _paymentEntryAmount.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _paymentEntryAmount.text.length,
          ),
          onFieldSubmitted: (_) => commit(),
          onChanged: (_) => setState(() {}),
        ),
      );
      final weightField = _compactField(
        width: stack ? null : FieldSizes.weight,
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
      );
      if (stack) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            typeField,
            const SizedBox(height: 6),
            amountField,
            const SizedBox(height: 6),
            weightField,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          typeField,
          const SizedBox(width: 6),
          amountField,
          const SizedBox(width: 6),
          weightField,
        ],
      );
    }

    final weightField = _compactField(
      width: stack ? null : FieldSizes.weight,
      child: TextFormField(
        controller: _paymentEntryWeight,
        focusNode: _paymentEntryWeightFocus,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
        onTap: () => _paymentEntryWeight.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _paymentEntryWeight.text.length,
        ),
        onChanged: (_) => setState(() {}),
        onFieldSubmitted: (_) => FocusChain.focusNextFrame(
          _paymentEntryTouchFocus,
          controller: _paymentEntryTouch,
        ),
      ),
    );
    final touchField = _compactField(
      width: stack ? null : FieldSizes.touch,
      child: TextFormField(
        controller: _paymentEntryTouch,
        focusNode: _paymentEntryTouchFocus,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          TouchPercentInputFormatter(),
        ],
        textAlign: TextAlign.right,
        style: const TextStyle(fontSize: 13),
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: '$prefix.Touch %',
          isDense: true,
          errorText: _paymentTouchError,
          errorStyle: const TextStyle(fontSize: 10),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        ),
        onTap: () => _paymentEntryTouch.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _paymentEntryTouch.text.length,
        ),
        onFieldSubmitted: (_) => commit(),
        onChanged: (_) => setState(() {
          if (isValidTouchPercent(_paymentEntryTouch.text)) {
            _paymentTouchError = null;
          }
        }),
      ),
    );
    final pureField = _compactField(
      width: stack ? null : FieldSizes.pure,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: '$prefix.Pure Wt',
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
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
    );

    if (stack) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          typeField,
          const SizedBox(height: 6),
          weightField,
          const SizedBox(height: 6),
          touchField,
          const SizedBox(height: 6),
          pureField,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        typeField,
        const SizedBox(width: 6),
        weightField,
        const SizedBox(width: 6),
        touchField,
        const SizedBox(width: 6),
        pureField,
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
    String? touchError,
    bool enabled = true,
  }) {
    final pure = _entryPure(weight, touch);
    final stack = Responsive.isCompact(context);

    final typeField = _compactField(
      width: stack ? null : FieldSizes.typeDropdown,
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
    );
    final weightField = _compactField(
      width: stack ? null : FieldSizes.weight,
      child: TextFormField(
        controller: weight,
        focusNode: weightFocus,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
        onChanged: (_) => setState(() {}),
        onFieldSubmitted: (_) => FocusChain.focusNextFrame(
          touchFocus,
          controller: touch,
        ),
      ),
    );
    final touchField = _compactField(
      width: stack ? null : FieldSizes.touch,
      child: TextFormField(
        controller: touch,
        focusNode: touchFocus,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          TouchPercentInputFormatter(),
        ],
        textAlign: TextAlign.right,
        style: const TextStyle(fontSize: 13),
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: '$prefix.Touch %',
          isDense: true,
          errorText: touchError,
          errorStyle: const TextStyle(fontSize: 10),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        ),
        onTap: () => touch.selection = TextSelection(
          baseOffset: 0,
          extentOffset: touch.text.length,
        ),
        onFieldSubmitted: (_) => onTouchSubmitted(),
        onChanged: (_) => setState(() {
          if (isValidTouchPercent(touch.text)) {
            if (touch == _billEntryTouch) {
              _billTouchError = null;
            } else if (touch == _paymentEntryTouch) {
              _paymentTouchError = null;
            }
          }
        }),
      ),
    );
    final pureField = _compactField(
      width: stack ? null : FieldSizes.pure,
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
    );

    if (stack) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          typeField,
          const SizedBox(height: 6),
          weightField,
          const SizedBox(height: 6),
          touchField,
          const SizedBox(height: 6),
          pureField,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        typeField,
        const SizedBox(width: 6),
        weightField,
        const SizedBox(width: 6),
        touchField,
        const SizedBox(width: 6),
        pureField,
      ],
    );
  }

  Widget _issuePanel() {
    // Issue is always on the left — same physical position as Sales.
    // Purchase puts cash/payment lines in the Issue panel.
    if (_isPurchase) {
      return _paymentPanel(title: 'ISSUE', prefix: 'I');
    }
    return _billPanel(title: 'ISSUE', prefix: 'I');
  }

  Widget _receiptPanel() {
    if (_isPurchaseBill) {
      return _purchaseReceiptPanel();
    }
    return _paymentPanel(title: 'RECEIPT', prefix: 'R');
  }

  Widget _purchaseReceiptPanel() {
    final isCash = _paymentEntryType == 'CASH';
    return _panelShell(
      title: 'RECEIPT',
      totalLabel: 'RECEIPT totals',
      totalPure: _billTotalPure,
      totalCash: _paymentTotalCash,
      combinedCashAndGrams: true,
      rows: [
        if (!isCash) _billEntryRateChip(typeOverride: _paymentEntryType),
        _paymentEntryBlock(
          prefix: 'R',
          onCommit: _commitPurchaseReceiptEntry,
        ),
        if (!isCash)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: TextFormField(
              controller: _billEntryDescription,
              maxLength: 80,
              decoration: InputDecoration(
                labelText: 'Item description (optional)',
                hintText: defaultItemDescriptionForType(_paymentEntryType),
                isDense: true,
                counterText: '',
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _commitPurchaseReceiptEntry(),
            ),
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
                onEdit: () => _editBillLine(i),
                onRemove: () => setState(() {
                  _billLines.removeAt(i);
                  _syncAutoTds(force: true);
                }),
              ),
            for (var i = 0; i < _paymentLines.length; i++)
              _lineDataRow(
                index: _billLines.length + i,
                type: _paymentLines[i].type,
                displayType: _receiptTypeLabel(_paymentLines[i].type),
                weight: _paymentLines[i].weight,
                touch: _paymentLines[i].touch,
                cashAmount: _paymentLines[i].cashAmount,
                pureWt: _paymentLines[i].pureWtAtRate(_goldRate),
                onEdit: () => _editPaymentLine(i),
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

  Widget _billPanel({required String title, required String prefix}) {
    return _panelShell(
      title: title,
      totalLabel: '$title total pure wt',
      totalPure: _billTotalPure,
      rows: [
        _billEntryRateChip(),
        _metalEntryRow(
          prefix: prefix,
          selectedType: _billEntryType,
          onTypeChanged: (v) => setState(() {
            _billEntryType = v;
          }),
          weight: _billEntryWeight,
          touch: _billEntryTouch,
          weightFocus: _billEntryWeightFocus,
          touchFocus: _billEntryTouchFocus,
          touchError: _billTouchError,
          onTouchSubmitted: _commitBillEntry,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: TextFormField(
            controller: _billEntryDescription,
            maxLength: 80,
            decoration: InputDecoration(
              labelText: 'Item description (optional)',
              hintText: defaultItemDescriptionForType(_billEntryType),
              isDense: true,
              counterText: '',
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _commitBillEntry(),
          ),
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
                onEdit: () => _editBillLine(i),
                onRemove: () => setState(() {
                  _billLines.removeAt(i);
                  _syncAutoTds(force: true);
                }),
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
                displayType: _receiptTypeLabel(_paymentLines[i].type),
                weight: _paymentLines[i].weight,
                touch: _paymentLines[i].touch,
                cashAmount: _paymentLines[i].cashAmount,
                pureWt: _paymentLines[i].pureWtAtRate(_goldRate),
                onEdit: () => _editPaymentLine(i),
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

  Widget _currentBalanceStrip() {
    final partyGrams = _partyOutstanding?['grams'] ?? 0;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.headerBand,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          'Old Balance  ${_signedGrams(partyGrams)}',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
          ),
        ),
      ),
    );
  }

  Widget _projectedBalanceBar() {
    final s = _settlement;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.headerBand,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          '${_isVoucher ? 'After this voucher' : 'After this bill'}: ${_signedGrams(s.newGrams)}',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
          ),
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
            "${_historyTitle} (${_history.length})",
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
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                _isVoucher ? 'No vouchers yet' : 'No bills yet',
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ),
          )
        else
          MaterialTileCard(
            child: Column(
              children: List.generate(_history.length, (index) {
                final row = _history[index];
                final isLast = index == _history.length - 1;
                final rowNo = _isVoucher
                    ? '${row['voucherNo']}'
                    : '${row['billNo']}';

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
                    onTap: _isVoucher ? null : () => _showBillDetails(row),
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: AppColors.headerBand,
                      child: Text(
                        rowNo,
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
                      _isVoucher
                          ? '${row['voucherType']}-#$rowNo  ·  '
                              '${row['paymentMode']} ${row['amount']}  ·  '
                              '${row['date']}'
                          : '#$rowNo  ·  '
                              '₹${row['totalValue'] ?? '-'}  ·  '
                              '${row['totalPureWt'] ?? '-'} g',
                      style: const TextStyle(
                          fontSize: 10.5, color: Colors.black54),
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (row['fromLedger'] != true)
                                IconButton(
                                  icon: const Icon(Icons.edit,
                                      color: AppColors.navy, size: 16),
                                  onPressed: () => _loadBillForEdit(row),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  tooltip: 'Edit bill',
                                ),
                              IconButton(
                                icon: const Icon(Icons.delete,
                                    color: Colors.redAccent, size: 16),
                                onPressed: () => _confirmDelete(row),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: row['fromLedger'] == true
                                    ? 'Remove ledger entry'
                                    : 'Delete bill',
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

  Widget _totalRow(String label, double value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: highlight ? AppColors.navy : AppColors.mutedBlue,
              ),
            ),
          ),
          Text(
            '₹${_rupee(value)}',
            style: TextStyle(
              fontSize: highlight ? 15 : 13,
              fontWeight: FontWeight.bold,
              color: highlight ? AppColors.navy : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bill / voucher number and live timestamp above the entry form.
class TransactionBillHeader extends StatelessWidget {
  const TransactionBillHeader({
    super.key,
    required this.numberLabel,
    required this.billNumber,
    required this.dateTimeText,
  });

  final String numberLabel;
  final String billNumber;
  final String dateTimeText;

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColors.mutedBlue,
    );
    const numberStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.bold,
    );
    const dateStyle = TextStyle(
      fontSize: 11.5,
      color: Colors.black54,
    );

    if (Responsive.isCompact(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(numberLabel, style: labelStyle),
              const SizedBox(width: 8),
              Text(billNumber, style: numberStyle),
            ],
          ),
          const SizedBox(height: 4),
          Text(dateTimeText, style: dateStyle),
        ],
      );
    }

    return Row(
      children: [
        Text(numberLabel, style: labelStyle),
        const SizedBox(width: 8),
        Text(billNumber, style: numberStyle),
        const Spacer(),
        Text(dateTimeText, style: dateStyle),
      ],
    );
  }
}
