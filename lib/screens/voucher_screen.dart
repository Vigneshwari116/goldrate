import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../database/database_helper.dart';
import '../logic/gold_ledger.dart';
import '../pdf/pdf_kit.dart';
import '../util/field_advance.dart';
import '../util/focus_chain.dart';
import '../util/screen_activation.dart';
import '../util/party_save_prompt.dart';
import '../theme/app_theme.dart';
import '../theme/field_sizes.dart';
import '../theme/responsive.dart';
import '../widgets/material_tile_card.dart';
import '../widgets/party_autocomplete_field.dart';

/// Receipt from a customer (they pay gold or cash) or payment to a
/// supplier. Cash is converted to gold at today's G.P RATE.
class VoucherScreen extends StatefulWidget {
  const VoucherScreen({
    super.key,
    this.embedded = false,
    this.isActive = true,
  });

  final bool embedded;
  final bool isActive;

  @override
  State<VoucherScreen> createState() => _VoucherScreenState();
}

class _VoucherScreenState extends State<VoucherScreen>
    with FocusAdvanceMixin, ScreenActivationMixin<VoucherScreen> {
  static const _modes = ['CASH', 'UPI', 'GOLD'];

  final _partyController = TextEditingController();
  final _amountController = TextEditingController(text: '0.00');
  final _narrationController = TextEditingController();
  final _partyFocus = FocusNode();
  final _modeFocus = FocusNode();
  final _amountFocus = FocusNode();
  final _narrationFocus = FocusNode();
  final _saveFocus = FocusNode();

  bool _isCustomer = true;
  String _mode = 'CASH';
  int _nextNo = 1;
  bool _loading = true;
  bool _saving = false;
  List<String> _names = [];
  Map<String, double> _outstanding = const {'rupees': 0, 'grams': 0};
  Map<String, double> _rates = {};
  List<Map<String, dynamic>> _history = [];
  Timer? _nameRefreshTimer;

  @override
  void initState() {
    super.initState();
    _partyController.addListener(_onParty);
    _partyFocus.addListener(_onPartyFocus);
    _load();
  }

  @override
  bool get screenIsActive => widget.isActive;

  @override
  bool wasScreenActive(VoucherScreen oldWidget) => oldWidget.isActive;

  @override
  void onScreenActivated() {
    _refreshNames();
  }

  void _onPartyFocus() {
    if (_partyFocus.hasFocus) {
      _refreshNames();
    }
  }

  @override
  void dispose() {
    _nameRefreshTimer?.cancel();
    _partyFocus.removeListener(_onPartyFocus);
    _partyFocus.dispose();
    _modeFocus.dispose();
    _amountFocus.dispose();
    _narrationFocus.dispose();
    _saveFocus.dispose();
    _partyController.dispose();
    _amountController.dispose();
    _narrationController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final names = await DatabaseHelper.instance
        .getDistinctPartyNames(isCustomer: _isCustomer);
    final rates = await DatabaseHelper.instance.getRatesMap();
    final next = await DatabaseHelper.instance
        .getNextVoucherNo(_isCustomer ? 'RECEIPT' : 'PAYMENT');
    final history = await DatabaseHelper.instance
        .getVouchers(voucherType: _isCustomer ? 'RECEIPT' : 'PAYMENT');
    if (!mounted) return;
    setState(() {
      _names = names;
      _rates = rates;
      _nextNo = next;
      _history = history;
      _loading = false;
    });
    _refreshOutstanding();
  }

  Future<void> _refreshNames() async {
    final names = await DatabaseHelper.instance
        .getDistinctPartyNames(isCustomer: _isCustomer);
    if (!mounted) return;
    setState(() => _names = names);
  }

  void _onParty([String? value]) {
    _refreshOutstanding();
  }

  Future<void> _advanceFromParty(String value) async {
    if (!await _ensurePartySaved()) return;
    FocusChain.focus(_modeFocus);
  }

  void _onPartyNameChanged(String value) {
    _onParty(value);
    if (value.trim().isNotEmpty) {
      _nameRefreshTimer?.cancel();
      _nameRefreshTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) _refreshNames();
      });
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;

    advanceWhenIdle(
      value: trimmed,
      from: _partyFocus,
      when: (v) => v.trim().length >= 2,
      action: () => _advanceFromParty(trimmed),
    );
  }

  void _onAmountChanged(String value) {
    setState(() {});
    advanceWhenComplete(
      value: value,
      from: _amountFocus,
      isComplete: (v) => FieldComplete.voucherAmount(v, _mode),
      to: _narrationFocus,
      toController: _narrationController,
    );
  }

  void _onNarrationChanged(String value) {
    advanceWhenIdle(
      value: value,
      from: _narrationFocus,
      when: (v) => v.trim().isNotEmpty,
      action: () => FocusChain.focus(_saveFocus),
    );
  }

  Iterable<String> _partyOptions(String query) {
    final lower = query.trim().toLowerCase();
    if (lower.isEmpty) return _names.take(12);
    return _names.where((n) => n.toLowerCase().contains(lower)).take(12);
  }

  Future<void> _refreshOutstanding() async {
    final name = _partyController.text.trim();
    if (name.isEmpty) {
      setState(() => _outstanding = const {'rupees': 0, 'grams': 0});
      return;
    }
    final result = await DatabaseHelper.instance
        .getPartyOutstanding(name, isCustomer: _isCustomer);
    if (!mounted) return;
    setState(() => _outstanding = result);
  }

  Future<bool> _ensurePartySaved() async {
    final name = _partyController.text.trim();
    if (name.isEmpty) return false;
    if (_names.any((n) => n.toLowerCase() == name.toLowerCase())) {
      return true;
    }
    final save = await confirmSaveNewParty(
      context,
      isCustomer: _isCustomer,
      name: name,
    );
    if (!save) return false;
    await DatabaseHelper.instance.ensureParty(name, isCustomer: _isCustomer);
    await _load();
    return true;
  }

  SettlementResult get _settlement {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    return settleLedger(
      oldGrams: _outstanding['grams'] ?? 0,
      oldRupees: _outstanding['rupees'] ?? 0,
      billGrams: 0,
      billRupees: 0,
      paymentMode: _mode,
      paymentAmount: amount,
      ratePerGram: GoldLedger.goldRate(_rates),
      billSign: _isCustomer ? 1 : -1,
    );
  }

  String _signedGrams(double grams) {
    final sign = grams > 0 ? '+' : grams < 0 ? '' : '';
    return '$sign${grams.toStringAsFixed(3)} g';
  }

  Future<void> _save() async {
    final name = _partyController.text.trim();
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    if (name.isEmpty) {
      _toast('Enter a name');
      return;
    }
    if (!await _ensurePartySaved()) return;
    if (amount <= 0) {
      _toast('Enter a receipt amount');
      return;
    }
    if (!_mode.startsWith('G') && GoldLedger.goldRate(_rates) <= 0) {
      _toast("Set today's G.P RATE first so cash can convert to gold");
      return;
    }

    setState(() => _saving = true);
    final date = DateFormat('dd-MM-yyyy').format(DateTime.now());
    final time = DateFormat('hh:mm a').format(DateTime.now());
    final s = _settlement;
    final type = _isCustomer ? 'RECEIPT' : 'PAYMENT';

    await DatabaseHelper.instance.insertVoucher({
      'voucherType': type,
      'voucherNo': _nextNo,
      'partyName': name,
      'isCustomer': _isCustomer ? 1 : 0,
      'paymentMode': _mode,
      'amount': amount.toStringAsFixed(2),
      'amountUnit': _mode == 'GOLD' ? 'GRAMS' : 'RUPEES',
      'cashToGold': s.cashToGoldGrams.toStringAsFixed(3),
      'goldRateUsed': s.ratePerGram.toStringAsFixed(2),
      'oldGrams': s.oldGrams.toStringAsFixed(3),
      'oldRupees': s.oldRupees.toStringAsFixed(2),
      'newGrams': s.newGrams.toStringAsFixed(3),
      'newRupees': s.newRupees.toStringAsFixed(2),
      'narration': _narrationController.text.trim(),
      'date': date,
      'time': time,
    });

    final deltaG = s.newGrams - s.oldGrams;
    final entry = {
      'name': name,
      'mobile': '',
      'city': '',
      'cr': deltaG < 0 ? deltaG.abs().toStringAsFixed(3) : '0',
      'dr': deltaG > 0 ? deltaG.abs().toStringAsFixed(3) : '0',
      'narration':
          'Voucher $type #$_nextNo · ${s.paymentLabel}. Old ${s.oldGrams.toStringAsFixed(3)}g → New ${s.newGrams.toStringAsFixed(3)}g',
      'balanceUnit': 'GRAMS',
      'billRef': '$type-$_nextNo',
      'date': date,
      'time': time,
    };
    if (_isCustomer) {
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

    final saved = {
      'voucherType': type,
      'voucherNo': _nextNo,
      'partyName': name,
      'paymentMode': _mode,
      'amount': amount.toStringAsFixed(2),
      'cashToGold': s.cashToGoldGrams.toStringAsFixed(3),
      'goldRateUsed': s.ratePerGram.toStringAsFixed(2),
      'oldGrams': s.oldGrams.toStringAsFixed(3),
      'newGrams': s.newGrams.toStringAsFixed(3),
      'narration': _narrationController.text.trim(),
      'date': date,
      'time': time,
    };

    if (!mounted) return;
    setState(() => _saving = false);
    _partyController.clear();
    _amountController.text = '0.00';
    _narrationController.clear();
    _toast(
        'Voucher #$type-${saved['voucherNo']} saved. Balance ${_signedGrams(s.newGrams)}');
    await _load();
    if (!mounted) return;
    await _shareVoucherPdf(saved);
  }

  Future<void> _shareVoucherPdf(Map<String, dynamic> row) async {
    final type = (row['voucherType'] ?? 'RECEIPT').toString();
    final no = row['voucherNo'];
    final doc = await PdfKit.document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('JEWELLERY MANAGEMENT',
                style: pw.TextStyle(
                    fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('$type VOUCHER',
                style: pw.TextStyle(
                    fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.Divider(),
            pw.Text('Voucher No: $type-$no'),
            pw.Text('Date: ${row['date'] ?? ''}  ${row['time'] ?? ''}'),
            pw.Text('Name: ${row['partyName'] ?? ''}'),
            pw.SizedBox(height: 10),
            pw.Text('Mode: ${row['paymentMode'] ?? ''}'),
            pw.Text('Amount: ${row['amount'] ?? ''}'),
            pw.Text('Cash to gold: ${row['cashToGold'] ?? '0'} g'),
            pw.Text('G.P rate used: ${row['goldRateUsed'] ?? ''}'),
            pw.Text('Balance: ${row['newGrams'] ?? ''} g'),
            if ((row['narration'] ?? '').toString().isNotEmpty)
              pw.Text('Narration: ${row['narration']}'),
            pw.SizedBox(height: 16),
            pw.Text('Share this PDF, then print from the share app if needed.',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          ],
        ),
      ),
    );
    final bytes = await doc.save();
    final file = await PdfKit.sharePdf(
      bytes: bytes,
      fileName: '${type}_$no.pdf',
      subject: '$type voucher #$no - ${row['partyName'] ?? ''}',
    );
    if (!mounted) return;
    if (!(Platform.isAndroid || Platform.isIOS)) {
      _toast('PDF saved: ${file.path}');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final s = _settlement;
    final currentGrams = _outstanding['grams'] ?? 0;
    final form = Container(
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ChoiceChip(
                label: const Text('Customer receipt'),
                selected: _isCustomer,
                onSelected: (_) {
                  setState(() => _isCustomer = true);
                  _load();
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Supplier payment'),
                selected: !_isCustomer,
                onSelected: (_) {
                  setState(() => _isCustomer = false);
                  _load();
                },
              ),
              const Spacer(),
              Text(
                '${_isCustomer ? 'RCPT' : 'PAY'}-$_nextNo',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: FieldSizes.name,
            child: PartyAutocompleteField(
              label: _isCustomer ? 'Customer Name' : 'Supplier Name',
              controller: _partyController,
              options: _partyOptions,
              helperText: 'Search saved name or type a new one',
              focusNode: _partyFocus,
              onFocus: _refreshNames,
              onChanged: _onPartyNameChanged,
              onFieldSubmitted: () => _advanceFromParty(_partyController.text),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.headerBand,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              'Balance  ${_signedGrams(currentGrams)}',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: FieldSizes.typeDropdown + 24,
                child: Focus(
                  focusNode: _modeFocus,
                  onKeyEvent: (_, event) {
                    return KeyEventResult.ignored;
                  },
                  child: DropdownButtonFormField<String>(
                    value: _mode,
                    decoration: const InputDecoration(
                      labelText: 'Mode',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    ),
                    isDense: true,
                    items: _modes
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (v) {
                      setState(() => _mode = v!);
                      FocusChain.focus(
                        _amountFocus,
                        controller: _amountController,
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: FieldSizes.cash,
                child: TextField(
                  controller: _amountController,
                  focusNode: _amountFocus,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  onChanged: _onAmountChanged,
                  onSubmitted: (_) => FocusChain.focus(
                    _narrationFocus,
                    controller: _narrationController,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    labelText: _mode == 'GOLD'
                        ? 'Gold (g)'
                        : _mode == 'CASH'
                            ? 'Cash (₹)'
                            : 'Amount (₹)',
                  ),
                ),
              ),
            ],
          ),
          if ((double.tryParse(_amountController.text.trim()) ?? 0) > 0) ...[
            const SizedBox(height: 8),
            Text(
              'After this voucher: ${_signedGrams(s.newGrams)}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.mutedBlue,
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: FieldSizes.name,
            child: TextField(
              controller: _narrationController,
              focusNode: _narrationFocus,
              textInputAction: TextInputAction.done,
              onChanged: _onNarrationChanged,
              onSubmitted: (_) => FocusChain.focus(_saveFocus),
              decoration: const InputDecoration(
                labelText: 'Narration',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: 220,
            height: 42,
            child: ElevatedButton(
              focusNode: _saveFocus,
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : Text(_isCustomer ? 'SAVE RECEIPT' : 'SAVE PAYMENT'),
            ),
          ),
        ],
      ),
    );

    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${_isCustomer ? 'RECEIPTS' : 'PAYMENTS'} (${_history.length})',
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: AppColors.mutedBlue),
        ),
        const SizedBox(height: 8),
        if (_history.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No vouchers yet')),
          )
        else
          Expanded(
            child: ListView(
              children: _history.map((row) {
                return MaterialTileCard(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    dense: true,
                    onTap: () => _shareVoucherPdf(row),
                    title: Text(
                      '${row['partyName']}',
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${row['voucherType']}-#${row['voucherNo']}  '
                      '${row['paymentMode']} ${row['amount']}  '
                      '${row['date']}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.share,
                          size: 16, color: AppColors.mutedBlue),
                      onPressed: () => _shareVoucherPdf(row),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );

    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : WorkbenchLayout(
            secondaryWidth: 220,
            primary: form,
            secondary: list,
          );

    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('RECEIPT VOUCHER')),
      body: content,
    );
  }
}
