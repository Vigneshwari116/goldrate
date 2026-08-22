import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database/database_helper.dart';
import '../logic/gold_ledger.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';

/// Receipt from a customer (they pay gold or cash) or payment to a
/// supplier. Cash is converted to gold at today's G.P RATE.
class VoucherScreen extends StatefulWidget {
  const VoucherScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<VoucherScreen> createState() => _VoucherScreenState();
}

class _VoucherScreenState extends State<VoucherScreen> {
  static const _modes = ['CASH', 'UPI', 'GOLD'];

  final _partyController = TextEditingController();
  final _amountController = TextEditingController();
  final _narrationController = TextEditingController();

  bool _isCustomer = true;
  String _mode = 'CASH';
  int _nextNo = 1;
  bool _loading = true;
  bool _saving = false;
  List<String> _names = [];
  List<String> _suggestions = [];
  Map<String, double> _outstanding = const {'rupees': 0, 'grams': 0};
  Map<String, double> _rates = {};
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _partyController.addListener(_onParty);
    _load();
  }

  @override
  void dispose() {
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

  void _onParty() {
    final query = _partyController.text.trim();
    final lower = query.toLowerCase();
    setState(() {
      _suggestions = query.isEmpty
          ? []
          : _names
              .where((n) =>
                  n.toLowerCase().contains(lower) && n.toLowerCase() != lower)
              .take(4)
              .toList();
    });
    _refreshOutstanding();
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

  Future<void> _save() async {
    final name = _partyController.text.trim();
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    if (name.isEmpty) {
      _toast('Enter a name');
      return;
    }
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

    await DatabaseHelper.instance.ensureParty(name, isCustomer: _isCustomer);
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
      'dr': deltaG > 0 ? deltaG.toStringAsFixed(3) : '0',
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

    if (!mounted) return;
    setState(() => _saving = false);
    _partyController.clear();
    _amountController.clear();
    _narrationController.clear();
    _toast(
        'Voucher #$type-$_nextNo saved. New gold balance ${s.newGrams.toStringAsFixed(3)} g');
    _load();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final s = _settlement;
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
          const SizedBox(height: 12),
          TextField(
            controller: _partyController,
            decoration: InputDecoration(
              labelText: _isCustomer ? 'Customer Name' : 'Supplier Name',
              helperText: 'Name only is enough — old gold balance still shows',
            ),
          ),
          if (_suggestions.isNotEmpty)
            Column(
              children: _suggestions
                  .map((n) => ListTile(
                        dense: true,
                        title: Text(n, style: const TextStyle(fontSize: 13)),
                        onTap: () {
                          _partyController.text = n;
                          setState(() => _suggestions = []);
                        },
                      ))
                  .toList(),
            ),
          const SizedBox(height: 8),
          Text(
            'Old balance ${_outstanding['grams']?.toStringAsFixed(3) ?? '0.000'} g'
            '${GoldLedger.goldRate(_rates) > 0 ? '  ·  ₹${GoldLedger.goldToCash(_outstanding['grams'] ?? 0, GoldLedger.goldRate(_rates)).toStringAsFixed(2)}' : ''}',
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: AppColors.navy),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _mode,
                  decoration: const InputDecoration(labelText: 'Payment mode'),
                  items: _modes
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) => setState(() => _mode = v!),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: _mode == 'GOLD' ? 'Gold (g)' : 'Amount (₹)',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5EC),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              s.isGoldPayment
                  ? 'Gold ${s.paymentAmount.toStringAsFixed(3)} g received'
                  : s.ratePerGram <= 0
                      ? 'Set G.P RATE to convert cash to gold'
                      : '₹${s.paymentAmount.toStringAsFixed(2)} → ${s.cashToGoldGrams.toStringAsFixed(3)} g',
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: AppColors.totalGreen),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'New gold balance ${s.newGrams.toStringAsFixed(3)} g',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _narrationController,
            decoration: const InputDecoration(labelText: 'Narration'),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 42,
            child: ElevatedButton(
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
              fontWeight: FontWeight.w600, color: AppColors.mutedBlue),
        ),
        const SizedBox(height: 8),
        if (_history.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No vouchers yet')),
          )
        else
          ..._history.map((row) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.cardWhite,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListTile(
                dense: true,
                title: Text('${row['partyName']}  ·  ${row['voucherType']}-#${row['voucherNo']}'),
                subtitle: Text(
                  '${row['paymentMode']} ${row['amount']}  '
                  'cash→gold ${row['cashToGold'] ?? '0'} g  '
                  'old ${row['oldGrams']} → new ${row['newGrams']}  '
                  '${row['date']} ${row['time']}',
                ),
              ),
            );
          }),
      ],
    );

    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : WorkbenchLayout(primary: form, secondary: list, primaryWidth: 420);

    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('RECEIPT VOUCHER')),
      body: content,
    );
  }
}
